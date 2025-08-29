import Foundation

enum FilterOperation: String, CaseIterable {
    case contains = "Contains"
    case equals = "Equals"
    case notEquals = "Not Equals"
    case greaterThan = "Greater Than"
    case lessThan = "Less Than"
    case between = "Between"
    case regex = "Regex"
    
    var requiresNumeric: Bool {
        switch self {
        case .greaterThan, .lessThan, .between:
            return true
        default:
            return false
        }
    }
}

enum FilterLogic: String, CaseIterable {
    case and = "AND"
    case or = "OR"
}

struct FilterCriteria: Identifiable, Hashable {
    let id = UUID()
    var columnIndex: Int
    var operation: FilterOperation
    var value: String
    var secondValue: String = ""
    var isEnabled: Bool = true
    
    var numericRange: ClosedRange<Double>? {
        guard operation == .between else { return nil }
        guard let lower = Double(value), let upper = Double(secondValue) else { return nil }
        return min(lower, upper)...max(lower, upper)
    }
}

struct FilterSet {
    var filters: [FilterCriteria] = []
    var logic: FilterLogic = .and
    
    func apply(to rows: [CSVRow], columns: [CSVColumn]) -> [CSVRow] {
        guard !filters.isEmpty else { return rows }
        
        let activeFilters = filters.filter { $0.isEnabled }
        guard !activeFilters.isEmpty else { return rows }
        
        return rows.filter { row in
            switch logic {
            case .and:
                return activeFilters.allSatisfy { row.matches(filter: $0, columns: columns) }
            case .or:
                return activeFilters.contains { row.matches(filter: $0, columns: columns) }
            }
        }
    }
}