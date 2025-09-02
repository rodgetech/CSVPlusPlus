import Foundation

struct QueryResult {
    let columns: [CSVColumn]
    let rows: [CSVRow]
    let executionTimeMs: Double
    let affectedRows: Int?
    let queryType: QueryType
    
    enum QueryType {
        case select
        case insert
        case update
        case delete
        case create
        case drop
        case other
    }
}

enum QueryError: LocalizedError {
    case syntaxError(String)
    case executionError(String)
    case noResults
    case unsupportedOperation(String)
    case databaseNotInitialized
    
    var errorDescription: String? {
        switch self {
        case .syntaxError(let message):
            return "SQL Syntax Error: \(message)"
        case .executionError(let message):
            return "Query Execution Error: \(message)"
        case .noResults:
            return "Query returned no results"
        case .unsupportedOperation(let operation):
            return "Unsupported operation: \(operation)"
        case .databaseNotInitialized:
            return "Database not initialized. Please load a CSV file first."
        }
    }
}