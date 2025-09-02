import Foundation
import SQLite3

class SQLiteCSVHandler {
    private var db: OpaquePointer?
    private let dbPath: String
    private var columns: [CSVColumn] = []
    private var tableName = "csv_data"
    
    init() {
        // Create temporary database in memory or temp directory
        let tempDir = NSTemporaryDirectory()
        dbPath = (tempDir as NSString).appendingPathComponent("csv_\(UUID().uuidString).db")
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Database Management
    
    func openDatabase() throws {
        // Use SQLITE_OPEN_FULLMUTEX for thread safety
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw SQLiteCSVError.databaseError("Cannot open database")
        }
        
        // Aggressive optimizations for import speed
        sqlite3_exec(db, "PRAGMA journal_mode = OFF", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = OFF", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA cache_size = 50000", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA locking_mode = EXCLUSIVE", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA temp_store = MEMORY", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA mmap_size = 268435456", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA page_size = 32768", nil, nil, nil)
    }
    
    func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
            try? FileManager.default.removeItem(atPath: dbPath)
        }
    }
    
    // MARK: - CSV Import
    
    func importCSV(from url: URL, progress: @escaping (Double, String) -> Void) async throws -> [CSVColumn] {
        try openDatabase()
        
        // Read entire file into memory for faster processing (if file is reasonable size)
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        
        // Use memory-mapped reading for large files
        let fileData: Data
        if fileSize < 500_000_000 { // Less than 500MB - read into memory
            fileData = try Data(contentsOf: url, options: .mappedIfSafe)
        } else {
            fileData = try Data(contentsOf: url, options: .alwaysMapped)
        }
        
        // Parse CSV data
        let csvString = String(data: fileData, encoding: .utf8) ?? ""
        // Handle both Unix (\n) and Windows (\r\n) line endings properly
        let normalizedString = csvString.replacingOccurrences(of: "\r\n", with: "\n")
                                        .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedString.components(separatedBy: "\n")
        
        guard !lines.isEmpty else {
            throw SQLiteCSVError.readError("Empty CSV file")
        }
        
        // Parse headers
        let headers = parseCSVLine(lines[0]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // Sample rows for type detection
        var sampleRows: [[String]] = []
        for i in 1..<min(201, lines.count) {
            if !lines[i].isEmpty {
                sampleRows.append(parseCSVLine(lines[i]))
            }
        }
        
        // Detect column types
        columns = headers.enumerated().map { index, name in
            let samples = sampleRows.compactMap { row in
                index < row.count ? row[index] : nil
            }
            let type = ColumnType.detect(from: samples)
            return CSVColumn(name: sanitizeColumnName(name), index: index, type: type)
        }
        
        // Create table
        try createTable()
        
        // Prepare batch insert statement once
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let insertSQL = "INSERT INTO \(tableName) (\(columns.map { $0.name }.joined(separator: ", "))) VALUES (\(placeholders))"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteCSVError.databaseError("Cannot prepare insert statement")
        }
        defer { sqlite3_finalize(stmt) }
        
        // Import data with much larger batch size
        var rowCount = 0
        let batchSize = 25000 // Much larger batch size for better performance
        var batch: [[String]] = []
        batch.reserveCapacity(batchSize)
        
        // Start transaction
        sqlite3_exec(db, "BEGIN EXCLUSIVE TRANSACTION", nil, nil, nil)
        
        // Process all lines
        for i in 1..<lines.count {
            if lines[i].isEmpty { continue }
            
            let values = parseCSVLine(lines[i]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            if values.count == headers.count {
                batch.append(values)
                rowCount += 1
                
                if batch.count >= batchSize {
                    try insertBatchOptimized(batch, stmt: stmt)
                    batch.removeAll(keepingCapacity: true)
                    
                    if rowCount % 100000 == 0 { // Update progress less frequently
                        let progressValue = Double(i) / Double(lines.count)
                        let formattedCount = rowCount.formatted()
                        await MainActor.run {
                            progress(progressValue, "Imported \(formattedCount) rows...")
                        }
                    }
                }
            }
        }
        
        // Insert remaining batch
        if !batch.isEmpty {
            try insertBatchOptimized(batch, stmt: stmt)
        }
        
        // Commit transaction
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        
        // Create indexes AFTER import (in same thread to avoid multi-threading issues)
        try createIndexes()
        
        // Re-enable normal pragmas for queries
        sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = NORMAL", nil, nil, nil)
        
        // Debug: Inspect database after import
        if rowCount < 1000 {
            try inspectDatabase()
        }
        
        let finalCount = rowCount.formatted()
        await MainActor.run {
            progress(1.0, "Import complete: \(finalCount) rows")
        }
        
        return columns
    }
    
    private func createTable() throws {
        var createSQL = "CREATE TABLE IF NOT EXISTS \(tableName) (row_id INTEGER PRIMARY KEY AUTOINCREMENT"
        
        for column in columns {
            let columnName = column.name
            let dataType = column.type.isNumeric ? 
                (column.type == .integer ? "INTEGER" : "REAL") : "TEXT"
            createSQL += ", \(columnName) \(dataType)"
        }
        createSQL += ")"
        
        if sqlite3_exec(db, createSQL, nil, nil, nil) != SQLITE_OK {
            throw SQLiteCSVError.databaseError("Cannot create table")
        }
    }
    
    private func createIndexes() throws {
        // Create a single covering index instead of multiple indexes
        if columns.count > 0 {
            let indexColumns = columns.prefix(5).map { $0.name }.joined(separator: ", ")
            let indexSQL = "CREATE INDEX IF NOT EXISTS idx_covering ON \(tableName)(\(indexColumns))"
            sqlite3_exec(db, indexSQL, nil, nil, nil)
        }
    }
    
    private func insertBatch(_ rows: [[String]]) throws {
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let insertSQL = "INSERT INTO \(tableName) (\(columns.map { $0.name }.joined(separator: ", "))) VALUES (\(placeholders))"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteCSVError.databaseError("Cannot prepare insert statement")
        }
        defer { sqlite3_finalize(stmt) }
        
        for (_, row) in rows.enumerated() {
            for (index, value) in row.enumerated() {
                if index < columns.count {
                    let columnType = columns[index].type
                    if columnType == .integer, let intValue = Int(value) {
                        sqlite3_bind_int64(stmt, Int32(index + 1), Int64(intValue))
                    } else if columnType.isNumeric, let doubleValue = Double(value) {
                        sqlite3_bind_double(stmt, Int32(index + 1), doubleValue)
                    } else {
                        // Properly bind Swift String to SQLite with TRANSIENT to copy the data
                        _ = value.withCString { cString in
                            sqlite3_bind_text(stmt, Int32(index + 1), cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                        }
                    }
                }
            }
            
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
    }
    
    private func insertBatchOptimized(_ rows: [[String]], stmt: OpaquePointer?) throws {
        for row in rows {
            for (index, value) in row.enumerated() {
                if index < columns.count {
                    let columnType = columns[index].type
                    if columnType == .integer {
                        if let intValue = Int(value) {
                            sqlite3_bind_int64(stmt, Int32(index + 1), Int64(intValue))
                        } else {
                            sqlite3_bind_null(stmt, Int32(index + 1))
                        }
                    } else if columnType.isNumeric {
                        if let doubleValue = Double(value) {
                            sqlite3_bind_double(stmt, Int32(index + 1), doubleValue)
                        } else {
                            sqlite3_bind_null(stmt, Int32(index + 1))
                        }
                    } else {
                        // Use SQLITE_TRANSIENT to ensure data is copied
                        _ = value.withCString { cString in
                            sqlite3_bind_text(stmt, Int32(index + 1), cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                        }
                    }
                }
            }
            
            sqlite3_step(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_reset(stmt)
        }
    }
    
    // MARK: - Query Methods
    
    func getRows(offset: Int, limit: Int, sortColumn: String? = nil, sortAscending: Bool = true, filters: [String] = []) throws -> [CSVRow] {
        // Legacy single-column sorting - convert to multi-column format
        var sortClauses: [String] = []
        if let sortColumn = sortColumn {
            sortClauses = ["\(sortColumn) \(sortAscending ? "ASC" : "DESC")"]
        }
        
        return try getRowsWithMultiSort(offset: offset, limit: limit, sortClauses: sortClauses, filters: filters)
    }
    
    func getRowsWithMultiSort(offset: Int, limit: Int, sortClauses: [String], filters: [String] = []) throws -> [CSVRow] {
        var querySQL = "SELECT \(columns.map { $0.name }.joined(separator: ", ")) FROM \(tableName)"
        
        // Add WHERE clause for filters
        if !filters.isEmpty {
            querySQL += " WHERE " + filters.joined(separator: " AND ")
        }
        
        // Add ORDER BY clause
        if !sortClauses.isEmpty {
            querySQL += " ORDER BY " + sortClauses.joined(separator: ", ")
        } else {
            querySQL += " ORDER BY row_id"
        }
        
        // Add pagination
        querySQL += " LIMIT \(limit) OFFSET \(offset)"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw SQLiteCSVError.databaseError("Cannot prepare select statement: \(errorMsg)")
        }
        defer { sqlite3_finalize(stmt) }
        
        var rows: [CSVRow] = []
        var rowCounter = offset
        while sqlite3_step(stmt) == SQLITE_ROW {
            var values: [String] = []
            
            for i in 0..<columns.count {
                let columnIndex = Int32(i)
                let columnType = columns[i].type
                
                if sqlite3_column_type(stmt, columnIndex) == SQLITE_NULL {
                    values.append("")
                } else if columnType == .integer {
                    let intValue = sqlite3_column_int64(stmt, columnIndex)
                    values.append(String(intValue))
                } else if columnType.isNumeric {
                    let doubleValue = sqlite3_column_double(stmt, columnIndex)
                    values.append(String(doubleValue))
                } else {
                    if let cString = sqlite3_column_text(stmt, columnIndex) {
                        let value = String(cString: cString)
                        values.append(value)
                    } else {
                        values.append("")
                    }
                }
            }
            
            rows.append(CSVRow(id: rowCounter, values: values))
            rowCounter += 1
        }
        
        return rows
    }
    
    func getTotalCount(filters: [String] = []) throws -> Int {
        var querySQL = "SELECT COUNT(*) FROM \(tableName)"
        
        if !filters.isEmpty {
            querySQL += " WHERE " + filters.joined(separator: " AND ")
        }
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteCSVError.databaseError("Cannot prepare count statement")
        }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        
        return 0
    }
    
    func getColumns() -> [CSVColumn] {
        return columns
    }
    
    // MARK: - Aggregation Methods
    
    func getAggregation(for column: CSVColumn, filters: [String] = []) throws -> AggregationResult? {
        // Build the appropriate aggregation query based on column type
        let columnName = column.name
        var aggregationSQL: String
        
        if column.type.isNumeric {
            aggregationSQL = """
                SELECT 
                    COUNT(*) as count,
                    COUNT(DISTINCT \(columnName)) as distinct_count,
                    COUNT(CASE WHEN \(columnName) IS NOT NULL AND \(columnName) != '' THEN 1 END) as non_empty_count,
                    SUM(CASE WHEN \(columnName) IS NOT NULL AND \(columnName) != '' THEN CAST(\(columnName) AS REAL) END) as sum,
                    AVG(CASE WHEN \(columnName) IS NOT NULL AND \(columnName) != '' THEN CAST(\(columnName) AS REAL) END) as avg,
                    MIN(CASE WHEN \(columnName) IS NOT NULL AND \(columnName) != '' THEN CAST(\(columnName) AS REAL) END) as min,
                    MAX(CASE WHEN \(columnName) IS NOT NULL AND \(columnName) != '' THEN CAST(\(columnName) AS REAL) END) as max
                FROM \(tableName)
            """
        } else {
            aggregationSQL = """
                SELECT 
                    COUNT(*) as count,
                    COUNT(DISTINCT \(columnName)) as distinct_count,
                    COUNT(CASE WHEN \(columnName) IS NOT NULL AND \(columnName) != '' THEN 1 END) as non_empty_count,
                    NULL as sum,
                    NULL as avg,
                    NULL as min,
                    NULL as max
                FROM \(tableName)
            """
        }
        
        // Add WHERE clause for filters
        if !filters.isEmpty {
            aggregationSQL += " WHERE " + filters.joined(separator: " AND ")
        }
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, aggregationSQL, -1, &stmt, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw SQLiteCSVError.databaseError("Cannot prepare aggregation statement: \(errorMsg)")
        }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            _ = Int(sqlite3_column_int(stmt, 0)) // total count (unused for this calculation)
            let distinctCount = Int(sqlite3_column_int(stmt, 1))
            let nonEmptyCount = Int(sqlite3_column_int(stmt, 2))
            
            var sum: Double? = nil
            var average: Double? = nil
            var min: Double? = nil
            var max: Double? = nil
            
            // Only get numeric aggregations if column is numeric
            if column.type.isNumeric {
                if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                    sum = sqlite3_column_double(stmt, 3)
                }
                if sqlite3_column_type(stmt, 4) != SQLITE_NULL {
                    average = sqlite3_column_double(stmt, 4)
                }
                if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
                    min = sqlite3_column_double(stmt, 5)
                }
                if sqlite3_column_type(stmt, 6) != SQLITE_NULL {
                    max = sqlite3_column_double(stmt, 6)
                }
            }
            
            return AggregationResult(
                columnName: column.name,
                sum: sum,
                average: average,
                min: min,
                max: max,
                count: nonEmptyCount,
                distinctCount: distinctCount
            )
        }
        
        return nil
    }
    
    // MARK: - Filter Building
    
    func buildFilterClause(for criteria: FilterCriteria, column: CSVColumn) -> String {
        let columnName = column.name
        let value = criteria.value.replacingOccurrences(of: "'", with: "''")
        
        switch criteria.operation {
        case .contains:
            return "\(columnName) LIKE '%\(value)%'"
        case .equals:
            return "\(columnName) = '\(value)'"
        case .notEquals:
            return "\(columnName) != '\(value)'"
        case .greaterThan:
            return "\(columnName) > '\(value)'"
        case .lessThan:
            return "\(columnName) < '\(value)'"
        case .between:
            let secondValue = criteria.secondValue.replacingOccurrences(of: "'", with: "''")
            return "\(columnName) BETWEEN '\(value)' AND '\(secondValue)'"
        case .regex:
            // SQLite doesn't support regex by default, use LIKE instead
            return "\(columnName) LIKE '\(value)'"
        }
    }
    
    // MARK: - Helpers
    
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        
        while i < chars.count {
            let char = chars[i]
            
            if char == "\"" {
                if inQuotes {
                    // Check if next char is also a quote (escaped quote)
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        current.append("\"")
                        i += 2 // Skip both quotes
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
                i += 1
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
                i += 1
            } else {
                current.append(char)
                i += 1
            }
        }
        
        // Don't forget the last field
        result.append(current)
        
        return result
    }
    
    private func sanitizeColumnName(_ name: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)  // Remove newlines and spaces
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "\n", with: "")  // Explicitly remove newlines
            .replacingOccurrences(of: "\r", with: "")  // Remove carriage returns
        
        // Ensure it starts with a letter or underscore
        if let first = cleaned.first, !first.isLetter && first != "_" {
            return "_" + cleaned
        }
        
        return cleaned.isEmpty ? "column" : cleaned
    }
    
    // Debug method to inspect database schema
    func inspectDatabase() throws {
        print("🔍 === DATABASE INSPECTION ===")
        
        // Get table schema
        var stmt: OpaquePointer?
        let schemaSQL = "PRAGMA table_info(\(tableName))"
        guard sqlite3_prepare_v2(db, schemaSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteCSVError.databaseError("Cannot prepare schema query")
        }
        defer { sqlite3_finalize(stmt) }
        
        print("🔍 Table schema:")
        while sqlite3_step(stmt) == SQLITE_ROW {
            let columnId = sqlite3_column_int(stmt, 0)
            let columnName = String(cString: sqlite3_column_text(stmt, 1))
            let columnType = String(cString: sqlite3_column_text(stmt, 2))
            let notNull = sqlite3_column_int(stmt, 3)
            _ = sqlite3_column_text(stmt, 4) // defaultValue (unused)
            let primaryKey = sqlite3_column_int(stmt, 5)
            
            print("🔍   Column \(columnId): \(columnName) (\(columnType)) notNull:\(notNull) pk:\(primaryKey)")
        }
        
        // Get first few rows
        var dataStmt: OpaquePointer?
        let dataSQL = "SELECT * FROM \(tableName) LIMIT 3"
        guard sqlite3_prepare_v2(db, dataSQL, -1, &dataStmt, nil) == SQLITE_OK else {
            throw SQLiteCSVError.databaseError("Cannot prepare data query")
        }
        defer { sqlite3_finalize(dataStmt) }
        
        print("🔍 Sample data:")
        var rowIndex = 0
        while sqlite3_step(dataStmt) == SQLITE_ROW {
            let columnCount = sqlite3_column_count(dataStmt)
            var rowValues: [String] = []
            
            for i in 0..<columnCount {
                if let cString = sqlite3_column_text(dataStmt, i) {
                    rowValues.append(String(cString: cString))
                } else {
                    rowValues.append("NULL")
                }
            }
            
            print("🔍   Row \(rowIndex): \(rowValues)")
            rowIndex += 1
        }
        
        print("🔍 === END DATABASE INSPECTION ===")
    }
    
    // MARK: - Arbitrary SQL Execution
    
    func executeArbitrarySQL(_ query: String) throws -> QueryResult {
        guard db != nil else {
            throw QueryError.databaseNotInitialized
        }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw QueryError.syntaxError("Empty query")
        }
        
        let queryType = determineQueryType(trimmedQuery)
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // For SELECT queries, use prepared statements to get structured results
        if queryType == .select {
            return try executeSelectQuery(trimmedQuery, startTime: startTime)
        } else {
            // For non-SELECT queries, use sqlite3_exec
            return try executeNonSelectQuery(trimmedQuery, queryType: queryType, startTime: startTime)
        }
    }
    
    private func executeSelectQuery(_ query: String, startTime: CFAbsoluteTime) throws -> QueryResult {
        // Preprocess query to replace SELECT * with actual column names (excluding row_id)
        let processedQuery = preprocessSelectQuery(query)
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, processedQuery, -1, &stmt, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw QueryError.executionError(errorMsg)
        }
        defer { sqlite3_finalize(stmt) }
        
        // Get column information
        let columnCount = sqlite3_column_count(stmt)
        var resultColumns: [CSVColumn] = []
        
        for i in 0..<columnCount {
            let columnName = String(cString: sqlite3_column_name(stmt, i))
            // For query results, we'll detect type dynamically or default to text
            resultColumns.append(CSVColumn(name: columnName, index: Int(i), type: .text))
        }
        
        // Execute query and collect results
        var resultRows: [CSVRow] = []
        var rowIndex = 0
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            var values: [String] = []
            
            for i in 0..<columnCount {
                let columnType = sqlite3_column_type(stmt, i)
                let value: String
                
                switch columnType {
                case SQLITE_NULL:
                    value = ""
                case SQLITE_INTEGER:
                    value = String(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    value = String(sqlite3_column_double(stmt, i))
                case SQLITE_TEXT:
                    value = String(cString: sqlite3_column_text(stmt, i))
                default:
                    value = ""
                }
                values.append(value)
            }
            
            resultRows.append(CSVRow(id: rowIndex, values: values))
            rowIndex += 1
        }
        
        let executionTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to milliseconds
        
        return QueryResult(
            columns: resultColumns,
            rows: resultRows,
            executionTimeMs: executionTime,
            affectedRows: resultRows.count,
            queryType: .select
        )
    }
    
    private func executeNonSelectQuery(_ query: String, queryType: QueryResult.QueryType, startTime: CFAbsoluteTime) throws -> QueryResult {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, query, nil, nil, &errorMessage)
        
        if result != SQLITE_OK {
            let error = errorMessage != nil ? String(cString: errorMessage!) : "Unknown error"
            sqlite3_free(errorMessage)
            throw QueryError.executionError(error)
        }
        
        let executionTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to milliseconds
        let affectedRows = Int(sqlite3_changes(db))
        
        return QueryResult(
            columns: [],
            rows: [],
            executionTimeMs: executionTime,
            affectedRows: affectedRows,
            queryType: queryType
        )
    }
    
    private func determineQueryType(_ query: String) -> QueryResult.QueryType {
        let upperQuery = query.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if upperQuery.hasPrefix("SELECT") || upperQuery.hasPrefix("PRAGMA") {
            return .select
        } else if upperQuery.hasPrefix("INSERT") {
            return .insert
        } else if upperQuery.hasPrefix("UPDATE") {
            return .update
        } else if upperQuery.hasPrefix("DELETE") {
            return .delete
        } else if upperQuery.hasPrefix("CREATE") {
            return .create
        } else if upperQuery.hasPrefix("DROP") {
            return .drop
        } else {
            return .other
        }
    }
    
    private func preprocessSelectQuery(_ query: String) -> String {
        let upperQuery = query.uppercased()
        
        // Don't preprocess PRAGMA queries - they should be executed as-is
        if upperQuery.hasPrefix("PRAGMA") {
            return query
        }
        
        // Simple pattern matching for "SELECT * FROM csv_data" type queries
        if upperQuery.contains("SELECT *") && upperQuery.contains("FROM \(tableName.uppercased())") {
            // Replace SELECT * with actual column names (excluding row_id)
            let columnNames = columns.map { $0.name }.joined(separator: ", ")
            return query.replacingOccurrences(of: "SELECT *", with: "SELECT \(columnNames)", options: [.caseInsensitive])
        }
        
        return query
    }
}

// Extension for FileHandle to read line by line
extension FileHandle {
    func readLine() throws -> Data? {
        var lineData = Data()
        
        while true {
            let chunk = self.readData(ofLength: 1)
            if chunk.isEmpty {
                return lineData.isEmpty ? nil : lineData
            }
            
            if let byte = chunk.first {
                if byte == 10 { // newline character
                    return lineData
                }
                lineData.append(chunk)
            }
        }
    }
}

enum SQLiteCSVError: LocalizedError {
    case readError(String)
    case databaseError(String)
    
    var errorDescription: String? {
        switch self {
        case .readError(let message):
            return "Read Error: \(message)"
        case .databaseError(let message):
            return "Database Error: \(message)"
        }
    }
}