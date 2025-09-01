import Foundation
import SwiftUI

@MainActor
class CSVDataManager: ObservableObject {
    @Published var columns: [CSVColumn] = []
    @Published var filterSet = FilterSet() {
        didSet {
            if sqliteHandler != nil {
                Task { @MainActor in
                    await reloadSQLiteData()
                }
            }
        }
    }
    @Published var sortSet = SortSet() {
        didSet {
            print("🔄 sortSet didSet triggered, ignoring: \(ignoreSortSetChanges)")
            if !ignoreSortSetChanges && sqliteHandler != nil {
                Task { @MainActor in
                    await reloadSQLiteData()
                }
            }
        }
    }
    
    private var ignoreSortSetChanges = false
    
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var loadingMessage = ""
    @Published var errorMessage: String?
    
    @Published var totalRowCount = 0
    @Published var filteredRowCount = 0
    @Published var fileName = ""
    
    @Published var selectedColumn: CSVColumn?
    @Published var aggregationResults: [AggregationResult] = []
    @Published var visibleRows: [CSVRow] = []
    
    // SQLite integration
    private var sqliteHandler: SQLiteCSVHandler?
    
    let aggregationEngine = AggregationEngine()
    
    // MARK: - SQLite Methods
    
    func loadCSVWithSQLite(from url: URL) async {
        
        isLoading = true
        loadingProgress = 0
        errorMessage = nil
        fileName = url.lastPathComponent
        visibleRows = []
        
        do {
            // Create new SQLite handler
            sqliteHandler = SQLiteCSVHandler()
            
            loadingMessage = "Importing CSV to database..."
            loadingProgress = 0.3
            
            // Import CSV to SQLite
            let importedColumns = try await sqliteHandler!.importCSV(from: url) { [weak self] progress, message in
                Task { @MainActor in
                    self?.loadingProgress = 0.3 + (progress * 0.6)
                    self?.loadingMessage = message
                }
            }
            
            await MainActor.run {
                self.columns = importedColumns
                self.totalRowCount = try! self.sqliteHandler!.getTotalCount()
                self.filteredRowCount = self.totalRowCount
            }
            
            // Load first page
            await loadSQLiteData(page: 0, pageSize: 100)
            
            loadingMessage = "Complete!"
            loadingProgress = 1.0
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Error loading CSV: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    func loadSQLiteData(page: Int, pageSize: Int, sortColumn: String? = nil, sortAscending: Bool = true) async {
        guard let handler = sqliteHandler else { return }
        
        do {
            // Build filters from FilterSet
            let filters = buildSQLFilters()
            
            let offset = page * pageSize
            let rows = try handler.getRows(
                offset: offset,
                limit: pageSize,
                sortColumn: sortColumn,
                sortAscending: sortAscending,
                filters: filters
            )
            
            let totalCount = try handler.getTotalCount(filters: filters)
            
            await MainActor.run {
                if page == 0 {
                    // Replace data for new query
                    self.visibleRows = rows
                } else {
                    // Append data for pagination
                    self.visibleRows.append(contentsOf: rows)
                }
                self.filteredRowCount = totalCount
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Error loading data: \(error.localizedDescription)"
            }
        }
    }
    
    func appendSQLiteData(page: Int, pageSize: Int, sortColumn: String? = nil, sortAscending: Bool = true) async {
        guard let handler = sqliteHandler else { return }
        
        do {
            let filters = buildSQLFilters()
            let offset = page * pageSize
            
            let newRows = try handler.getRows(
                offset: offset,
                limit: pageSize,
                sortColumn: sortColumn,
                sortAscending: sortAscending,
                filters: filters
            )
            
            await MainActor.run {
                self.visibleRows.append(contentsOf: newRows)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error loading more data: \(error.localizedDescription)"
            }
        }
    }
    
    func loadMoreSQLiteRows() async {
        // Calculate next page based on current row count
        let pageSize = 100
        let currentPage = visibleRows.count / pageSize
        
        // Get current sort from sortSet
        var sortColumn: String? = nil
        var sortAscending = true
        
        if let firstSort = sortSet.criteria.first,
           firstSort.columnIndex < columns.count {
            sortColumn = columns[firstSort.columnIndex].name
            sortAscending = firstSort.direction == .ascending
        }
        
        await appendSQLiteData(
            page: currentPage,
            pageSize: pageSize,
            sortColumn: sortColumn,
            sortAscending: sortAscending
        )
    }
    
    private func reloadSQLiteData() async {
        print("🔄 reloadSQLiteData called")
        
        // Get current sort from sortSet
        var sortColumn: String? = nil
        var sortAscending = true
        
        if let firstSort = sortSet.criteria.first,
           firstSort.columnIndex < columns.count {
            sortColumn = columns[firstSort.columnIndex].name
            sortAscending = firstSort.direction == .ascending
            print("🔄 Reloading with sort: \(sortColumn ?? "nil") ascending: \(sortAscending)")
        } else {
            print("🔄 Reloading with no sort")
        }
        
        await loadSQLiteData(page: 0, pageSize: 100, sortColumn: sortColumn, sortAscending: sortAscending)
    }
    
    private func buildSQLFilters() -> [String] {
        var sqlFilters: [String] = []
        
        for filter in filterSet.filters where filter.isEnabled {
            guard filter.columnIndex < columns.count else { continue }
            let columnName = columns[filter.columnIndex].name
            
            switch filter.operation {
            case .contains:
                sqlFilters.append("\(columnName) LIKE '%\(filter.value)%'")
            case .equals:
                sqlFilters.append("\(columnName) = '\(filter.value)'")
            case .notEquals:
                sqlFilters.append("\(columnName) != '\(filter.value)'")
            case .greaterThan:
                if columns[filter.columnIndex].type == .numeric {
                    sqlFilters.append("\(columnName) > \(filter.value)")
                } else {
                    sqlFilters.append("\(columnName) > '\(filter.value)'")
                }
            case .lessThan:
                if columns[filter.columnIndex].type == .numeric {
                    sqlFilters.append("\(columnName) < \(filter.value)")
                } else {
                    sqlFilters.append("\(columnName) < '\(filter.value)'")
                }
            case .between:
                if let range = filter.numericRange {
                    sqlFilters.append("\(columnName) BETWEEN \(range.lowerBound) AND \(range.upperBound)")
                }
            case .regex:
                // SQLite doesn't support regex by default
                sqlFilters.append("\(columnName) LIKE '%\(filter.value)%'")
            }
        }
        
        return sqlFilters
    }
    
    // MARK: - NSTableView Support Methods
    
    func loadDataWindow(offset: Int, limit: Int) async {
        guard let handler = sqliteHandler else { return }
        
        do {
            let filters = buildSQLFilters()
            
            // Get current sort from sortSet
            var sortColumn: String? = nil
            var sortAscending = true
            
            if let firstSort = sortSet.criteria.first,
               firstSort.columnIndex < columns.count {
                sortColumn = columns[firstSort.columnIndex].name
                sortAscending = firstSort.direction == .ascending
            }
            
            let rows = try handler.getRows(
                offset: offset,
                limit: limit,
                sortColumn: sortColumn,
                sortAscending: sortAscending,
                filters: filters
            )
            
            await MainActor.run {
                self.visibleRows = rows
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Error loading data window: \(error.localizedDescription)"
            }
        }
    }
    
    func loadSortedData(columnIndex: Int, columnName: String, ascending: Bool) async {
        print("🔄 loadSortedData: \(columnName) ascending=\(ascending)")
        
        // Update sortSet to keep it in sync with NSTableView, but temporarily ignore changes to prevent circular updates
        ignoreSortSetChanges = true
        
        // Clear existing sorts and add the new one
        sortSet.criteria.removeAll()
        let newSort = SortCriteria(
            columnIndex: columnIndex,
            direction: ascending ? .ascending : .descending,
            priority: 0
        )
        sortSet.criteria.append(newSort)
        
        ignoreSortSetChanges = false
        
        // Load fresh sorted data from SQLite - this is the proper approach
        await loadSQLiteData(page: 0, pageSize: 100, sortColumn: columnName, sortAscending: ascending)
    }
    
    func loadSortedDataSilently(columnIndex: Int, columnName: String, ascending: Bool) async {
        print("🔄 loadSortedDataSilently: \(columnName) ascending=\(ascending)")
        
        // Load data without triggering any UI updates that might interfere with NSTableView sorting
        guard let handler = sqliteHandler else { return }
        
        do {
            let filters = buildSQLFilters()
            let rows = try handler.getRows(
                offset: 0,
                limit: 100,
                sortColumn: columnName,
                sortAscending: ascending,
                filters: filters
            )
            
            let totalCount = try handler.getTotalCount(filters: filters)
            
            await MainActor.run {
                self.visibleRows = rows
                self.filteredRowCount = totalCount
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Error loading sorted data: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Filter & Sort Management
    
    func addFilter() {
        guard !columns.isEmpty else { return }
        let newFilter = FilterCriteria(
            columnIndex: 0,
            operation: .contains,
            value: ""
        )
        filterSet.filters.append(newFilter)
    }
    
    func removeFilter(_ filter: FilterCriteria) {
        filterSet.filters.removeAll { $0.id == filter.id }
    }
    
    func addSort() {
        guard !columns.isEmpty else { return }
        let priority = sortSet.criteria.count
        let newSort = SortCriteria(
            columnIndex: 0,
            direction: .ascending,
            priority: priority
        )
        sortSet.criteria.append(newSort)
    }
    
    func removeSort(_ sort: SortCriteria) {
        sortSet.criteria.removeAll { $0.id == sort.id }
        updateSortPriorities()
    }
    
    private func updateSortPriorities() {
        for (index, _) in sortSet.criteria.enumerated() {
            sortSet.criteria[index].priority = index
        }
    }
    
    // MARK: - Column Selection & Aggregation
    
    func selectColumn(_ column: CSVColumn) {
        selectedColumn = column
        updateAggregations()
    }
    
    private func updateAggregations() {
        // TODO: Implement aggregations with SQLite queries
        // For now, calculate from visible rows
        if let column = selectedColumn {
            let result = aggregationEngine.calculate(for: visibleRows, column: column)
            aggregationResults = [result]
        } else {
            aggregationResults = columns.filter { $0.type == .numeric }
                .map { aggregationEngine.calculate(for: visibleRows, column: $0) }
        }
    }
    
    // MARK: - Data Management
    
    func clearData() {
        columns = []
        filterSet = FilterSet()
        sortSet = SortSet()
        totalRowCount = 0
        filteredRowCount = 0
        visibleRows = []
        aggregationResults = []
        selectedColumn = nil
        fileName = ""
        sqliteHandler = nil
    }
    
    // MARK: - Export
    
    func exportFilteredData(to url: URL) async throws {
        guard let handler = sqliteHandler else {
            throw CSVError.readError("No data source available")
        }
        
        // Export filtered data using SQLite
        let filters = buildSQLFilters()
        
        var lines: [String] = []
        let headerLine = columns.map { escapeCSVField($0.name) }.joined(separator: ",")
        lines.append(headerLine)
        
        // Get all filtered rows in chunks
        let chunkSize = 10000
        var offset = 0
        
        while true {
            let rows = try handler.getRows(
                offset: offset,
                limit: chunkSize,
                sortColumn: nil,
                sortAscending: true,
                filters: filters
            )
            
            if rows.isEmpty {
                break
            }
            
            for row in rows {
                let line = row.values.map { escapeCSVField($0) }.joined(separator: ",")
                lines.append(line)
            }
            
            offset += chunkSize
        }
        
        let csvContent = lines.joined(separator: "\n")
        try csvContent.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}

// MARK: - Error Types

enum CSVError: Error {
    case readError(String)
    case writeError(String)
    case parseError(String)
}