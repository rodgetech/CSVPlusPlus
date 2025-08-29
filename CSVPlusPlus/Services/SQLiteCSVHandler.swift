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
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw SQLiteCSVError.databaseError("Cannot open database")
        }
        
        // Enable optimizations
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA cache_size=10000", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA temp_store=MEMORY", nil, nil, nil)
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
        
        // Read header and detect column types
        let file = try FileHandle(forReadingFrom: url)
        defer { file.closeFile() }
        
        // Read first line for headers
        guard let headerData = try file.readLine(),
              let headerLine = String(data: headerData, encoding: .utf8) else {
            throw SQLiteCSVError.readError("Cannot read CSV header")
        }
        
        let headers = parseCSVLine(headerLine).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        print("📊 SQLite Parsed headers: \(headers)")
        print("📊 SQLite Header count: \(headers.count)")
        print("📊 SQLite Raw header line: '\(headerLine)'")
        
        // Sample first 100 rows for type detection
        var sampleRows: [[String]] = []
        for _ in 0..<100 {
            guard let lineData = try file.readLine(),
                  let line = String(data: lineData, encoding: .utf8) else { break }
            sampleRows.append(parseCSVLine(line))
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
        
        // Reset file to beginning
        file.seek(toFileOffset: 0)
        _ = try file.readLine() // Skip header
        
        // Import data in batches
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        var bytesRead: Int64 = 0
        var rowCount = 0
        let batchSize = 1000
        var batch: [[String]] = []
        
        // Start transaction for better performance and data consistency
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        
        while let lineData = try file.readLine() {
            bytesRead += Int64(lineData.count)
            let line = String(data: lineData, encoding: .utf8) ?? ""
            let values = parseCSVLine(line).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            // Debug: Print first few data rows during import
            if rowCount < 3 {
                print("📊 SQLite Import row \(rowCount): '\(line.prefix(200))'")
                print("📊 SQLite Parsed values[\(values.count)]: \(values.prefix(5))")
            }
            
            if values.count == headers.count {
                batch.append(values)
                rowCount += 1
                
                if batch.count >= batchSize {
                    try insertBatch(batch)
                    batch.removeAll()
                    
                    let progressValue = Double(bytesRead) / Double(fileSize)
                    await MainActor.run {
                        progress(progressValue, "Imported \(rowCount.formatted()) rows...")
                    }
                }
            }
        }
        
        // Insert remaining batch
        if !batch.isEmpty {
            try insertBatch(batch)
        }
        
        // Commit transaction
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        
        // Create indexes for better performance
        try createIndexes()
        
        // Debug: Inspect database after import
        try inspectDatabase()
        
        await MainActor.run {
            progress(1.0, "Import complete: \(rowCount.formatted()) rows")
        }
        
        return columns
    }
    
    private func createTable() throws {
        var createSQL = "CREATE TABLE IF NOT EXISTS \(tableName) (row_id INTEGER PRIMARY KEY AUTOINCREMENT"
        
        for column in columns {
            let columnName = column.name
            let dataType = column.type == .numeric ? "REAL" : "TEXT"
            createSQL += ", \(columnName) \(dataType)"
        }
        createSQL += ")"
        
        if sqlite3_exec(db, createSQL, nil, nil, nil) != SQLITE_OK {
            throw SQLiteCSVError.databaseError("Cannot create table")
        }
    }
    
    private func createIndexes() throws {
        // Create index on first few columns for sorting
        for column in columns.prefix(5) {
            let indexSQL = "CREATE INDEX IF NOT EXISTS idx_\(column.name) ON \(tableName)(\(column.name))"
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
        
        for (rowNum, row) in rows.enumerated() {
            if rowNum < 3 {
                print("📊 SQLite Inserting row \(rowNum): \(row.prefix(5))")
                print("📊 SQLite Column mapping:")
                for (index, value) in row.enumerated() {
                    if index < columns.count {
                        print("📊   [\(index)] \(columns[index].name) = '\(value)'")
                    }
                }
            }
            for (index, value) in row.enumerated() {
                if index < columns.count {
                    if columns[index].type == .numeric, let doubleValue = Double(value) {
                        sqlite3_bind_double(stmt, Int32(index + 1), doubleValue)
                    } else {
                        // Properly bind Swift String to SQLite with TRANSIENT to copy the data
                        value.withCString { cString in
                            sqlite3_bind_text(stmt, Int32(index + 1), cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                        }
                    }
                }
            }
            
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
    }
    
    // MARK: - Query Methods
    
    func getRows(offset: Int, limit: Int, sortColumn: String? = nil, sortAscending: Bool = true, filters: [String] = []) throws -> [CSVRow] {
        var querySQL = "SELECT \(columns.map { $0.name }.joined(separator: ", ")) FROM \(tableName)"
        
        // Debug: Print column info
        print("🔍 SQLite columns: \(columns.map { "\($0.name)(idx:\($0.index))" }.joined(separator: ", "))")
        print("🔍 SQLite query: \(querySQL)")
        
        // Add WHERE clause for filters
        if !filters.isEmpty {
            querySQL += " WHERE " + filters.joined(separator: " AND ")
        }
        
        // Add ORDER BY clause
        if let sortColumn = sortColumn {
            querySQL += " ORDER BY \(sortColumn) \(sortAscending ? "ASC" : "DESC")"
        } else {
            querySQL += " ORDER BY row_id"
        }
        
        // Add pagination
        querySQL += " LIMIT \(limit) OFFSET \(offset)"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            print("❌ SQLite prepare error: \(errorMsg)")
            throw SQLiteCSVError.databaseError("Cannot prepare select statement: \(errorMsg)")
        }
        defer { sqlite3_finalize(stmt) }
        
        var rows: [CSVRow] = []
        var rowCounter = offset
        while sqlite3_step(stmt) == SQLITE_ROW {
            var values: [String] = []
            
            for i in 0..<columns.count {
                let columnIndex = Int32(i)
                if let cString = sqlite3_column_text(stmt, columnIndex) {
                    let value = String(cString: cString)
                    values.append(value)
                    
                    // Debug: Print first few rows and columns
                    if rows.count < 3 && i < 5 {
                        print("🔍 SQLite data[row:\(rows.count)][col:\(i):\(columns[i].name)] = '\(value)'")
                    }
                } else {
                    values.append("")
                    
                    // Debug: Print empty values
                    if rows.count < 3 && i < 5 {
                        print("🔍 SQLite data[row:\(rows.count)][col:\(i):\(columns[i].name)] = '' (NULL)")
                    }
                }
            }
            
            rows.append(CSVRow(id: rowCounter, values: values))
            rowCounter += 1
            
            // Debug: Print first few rows
            if rows.count <= 3 {
                print("🔍 SQLite Row \(rowCounter - 1): \(values.prefix(3))")
            }
        }
        
        print("🔍 SQLite getRows returning \(rows.count) rows")
        
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
        var previousChar: Character?
        
        for char in line {
            if char == "\"" {
                if inQuotes && previousChar == "\"" {
                    current.append(char)
                    previousChar = nil
                    continue
                }
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
            previousChar = char
        }
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
            let defaultValue = sqlite3_column_text(stmt, 4)
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