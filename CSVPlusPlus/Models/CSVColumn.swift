import Foundation
import CoreGraphics

enum ColumnType {
    case text
    case numeric
    case date
    case boolean
    
    static func detect(from samples: [String]) -> ColumnType {
        let nonEmpty = samples.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return .text }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateFormatter2 = DateFormatter()
        dateFormatter2.dateFormat = "MM/dd/yyyy"
        
        var numericCount = 0
        var dateCount = 0
        var boolCount = 0
        
        for sample in nonEmpty.prefix(100) {
            let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.lowercased() == "true" || trimmed.lowercased() == "false" ||
               trimmed == "0" || trimmed == "1" {
                boolCount += 1
            } else if Double(trimmed) != nil {
                numericCount += 1
            } else if dateFormatter.date(from: trimmed) != nil ||
                      dateFormatter2.date(from: trimmed) != nil {
                dateCount += 1
            }
        }
        
        let total = nonEmpty.count
        let threshold = Int(Double(total) * 0.8)
        if numericCount > threshold {
            return .numeric
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