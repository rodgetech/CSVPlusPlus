import Foundation
import CoreGraphics

enum ColumnType {
    case text
    case integer
    case decimal
    case date
    case boolean
    
    // Legacy compatibility - will be used in existing code
    var isNumeric: Bool {
        return self == .integer || self == .decimal
    }
    
    static func detect(from samples: [String]) -> ColumnType {
        let nonEmpty = samples.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return .text }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateFormatter2 = DateFormatter()
        dateFormatter2.dateFormat = "MM/dd/yyyy"
        
        var integerCount = 0
        var decimalCount = 0
        var dateCount = 0
        var boolCount = 0
        
        for sample in nonEmpty.prefix(100) {
            let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.lowercased() == "true" || trimmed.lowercased() == "false" {
                boolCount += 1
            } else if Int(trimmed) != nil {
                // Check if it's a valid integer first
                integerCount += 1
            } else if Double(trimmed) != nil {
                // If not an integer but is a valid number, it's a decimal
                decimalCount += 1
            } else if dateFormatter.date(from: trimmed) != nil ||
                      dateFormatter2.date(from: trimmed) != nil {
                dateCount += 1
            }
        }
        
        let total = nonEmpty.count
        let threshold = Int(Double(total) * 0.8)
        
        if integerCount > threshold {
            return .integer
        } else if (integerCount + decimalCount) > threshold {
            // If mostly numbers but not all integers, treat as decimal
            return decimalCount > integerCount ? .decimal : .integer
        } else if dateCount > threshold {
            return .date
        } else if boolCount > threshold {
            return .boolean
        } else {
            return .text
        }
    }
}

struct CSVColumn: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let index: Int
    var type: ColumnType
    var width: CGFloat
    
    init(name: String, index: Int, type: ColumnType = .text, width: CGFloat = 150) {
        self.name = name
        self.index = index
        self.type = type
        self.width = width
    }
}