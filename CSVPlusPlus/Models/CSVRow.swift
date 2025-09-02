import Foundation

struct CSVRow: Identifiable, Hashable {
    let id: Int
    let values: [String]
    
    init(id: Int, values: [String]) {
        self.id = id
        self.values = values
    }
    
    func value(at columnIndex: Int) -> String {
        guard columnIndex >= 0 && columnIndex < values.count else {
            return ""
        }
        return values[columnIndex]
    }
    
    func matches(filter: FilterCriteria, columns: [CSVColumn]) -> Bool {
        guard let column = columns.first(where: { $0.index == filter.columnIndex }) else {
            return false
        }
        
        let value = self.value(at: filter.columnIndex)
        
        switch filter.operation {
        case .contains:
            return value.localizedCaseInsensitiveContains(filter.value)
        case .equals:
            return value.caseInsensitiveCompare(filter.value) == .orderedSame
        case .notEquals:
            return value.caseInsensitiveCompare(filter.value) != .orderedSame
        case .greaterThan:
            if column.type.isNumeric,
               let numValue = Double(value),
               let filterNum = Double(filter.value) {
                return numValue > filterNum
            }
            return value > filter.value
        case .lessThan:
            if column.type.isNumeric,
               let numValue = Double(value),
               let filterNum = Double(filter.value) {
                return numValue < filterNum
            }
            return value < filter.value
        case .between:
            if column.type.isNumeric,
               let numValue = Double(value),
               let range = filter.numericRange {
                return numValue >= range.lowerBound && numValue <= range.upperBound
            }
            return false
        case .regex:
            do {
                let regex = try NSRegularExpression(pattern: filter.value, options: .caseInsensitive)
                let range = NSRange(value.startIndex..., in: value)
                return regex.firstMatch(in: value, range: range) != nil
            } catch {
                return false
            }
        }
    }
}