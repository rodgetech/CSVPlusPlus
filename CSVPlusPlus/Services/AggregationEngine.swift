import Foundation

struct AggregationResult {
    let columnName: String
    let sum: Double?
    let average: Double?
    let min: Double?
    let max: Double?
    let count: Int
    let distinctCount: Int
}

class AggregationEngine {
    
    func calculate(for rows: [CSVRow], column: CSVColumn) -> AggregationResult {
        let values = rows.map { $0.value(at: column.index) }
        let nonEmptyValues = values.filter { !$0.isEmpty }
        
        var sum: Double? = nil
        var average: Double? = nil
        var min: Double? = nil
        var max: Double? = nil
        
        if column.type.isNumeric {
            let numericValues = nonEmptyValues.compactMap { Double($0) }
            
            if !numericValues.isEmpty {
                sum = numericValues.reduce(0, +)
                average = sum! / Double(numericValues.count)
                min = numericValues.min()
                max = numericValues.max()
            }
        }
        
        let distinctValues = Set(nonEmptyValues)
        
        return AggregationResult(
            columnName: column.name,
            sum: sum,
            average: average,
            min: min,
            max: max,
            count: nonEmptyValues.count,
            distinctCount: distinctValues.count
        )
    }
    
    func calculateAll(for rows: [CSVRow], columns: [CSVColumn]) -> [AggregationResult] {
        return columns.map { column in
            calculate(for: rows, column: column)
        }
    }
    
    func formatResult(_ result: AggregationResult) -> String {
        var parts: [String] = []
        
        parts.append("Count: \(result.count)")
        parts.append("Distinct: \(result.distinctCount)")
        
        if let sum = result.sum {
            parts.append("Sum: \(formatNumber(sum))")
        }
        
        if let avg = result.average {
            parts.append("Avg: \(formatNumber(avg))")
        }
        
        if let min = result.min, let max = result.max {
            parts.append("Range: \(formatNumber(min)) - \(formatNumber(max))")
        }
        
        return parts.joined(separator: " | ")
    }
    
    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}