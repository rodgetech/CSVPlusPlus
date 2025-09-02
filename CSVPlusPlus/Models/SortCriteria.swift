import Foundation

enum SortDirection: String, CaseIterable {
    case ascending = "Ascending"
    case descending = "Descending"
}

struct SortCriteria: Identifiable, Hashable {
    let id = UUID()
    var columnIndex: Int
    var direction: SortDirection
    var priority: Int
    
    init(columnIndex: Int, direction: SortDirection = .ascending, priority: Int = 0) {
        self.columnIndex = columnIndex
        self.direction = direction
        self.priority = priority
    }
}

struct SortSet {
    var criteria: [SortCriteria] = []
    
    func apply(to rows: [CSVRow], columns: [CSVColumn]) -> [CSVRow] {
        guard !criteria.isEmpty else { return rows }
        
        let sortedCriteria = criteria.sorted { $0.priority < $1.priority }
        
        return rows.sorted { row1, row2 in
            for criterion in sortedCriteria {
                guard criterion.columnIndex < columns.count else { continue }
                
                let column = columns[criterion.columnIndex]
                let value1 = row1.value(at: criterion.columnIndex)
                let value2 = row2.value(at: criterion.columnIndex)
                
                var comparison: ComparisonResult = .orderedSame
                
                if column.type.isNumeric,
                   let num1 = Double(value1),
                   let num2 = Double(value2) {
                    if num1 < num2 {
                        comparison = .orderedAscending
                    } else if num1 > num2 {
                        comparison = .orderedDescending
                    }
                } else {
                    comparison = value1.localizedStandardCompare(value2)
                }
                
                if comparison != .orderedSame {
                    return criterion.direction == .ascending ?
                        comparison == .orderedAscending :
                        comparison == .orderedDescending
                }
            }
            return false
        }
    }
}