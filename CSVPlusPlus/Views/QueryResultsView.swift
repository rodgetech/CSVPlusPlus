import SwiftUI

struct QueryResultsView: View {
    let queryResult: QueryResult?
    let queryError: QueryError?
    let isExecuting: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if isExecuting {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                    
                    Text("Executing query...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = queryError {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("Query Error")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text(error.localizedDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = queryResult {
                // Results state
                VStack(spacing: 0) {
                    // Results header with execution info
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Query Results")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            HStack(spacing: 16) {
                                Label("\(result.rows.count) rows", systemImage: "number")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Label("\(String(format: "%.2f", result.executionTimeMs)) ms", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if let affectedRows = result.affectedRows, result.queryType != .select {
                                    Label("\(affectedRows) affected", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if !result.rows.isEmpty {
                            Button("Export Results") {
                                exportResults(result)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    if result.rows.isEmpty {
                        // No results state
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.6))
                            
                            Text("No Results")
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            Text(result.queryType == .select ? "Query executed successfully but returned no rows." : "Query executed successfully.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Results table
                        QueryResultTable(columns: result.columns, rows: result.rows)
                    }
                }
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor.opacity(0.6))
                    
                    Text("Ready to Execute")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Write your SQL query above and press ⌘ + Enter to execute")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func exportResults(_ result: QueryResult) {
        // Create CSV content
        var csvContent = ""
        
        // Add headers
        csvContent += result.columns.map { $0.name }.joined(separator: ",") + "\n"
        
        // Add rows
        for row in result.rows {
            csvContent += row.values.map { value in
                // Escape values that contain commas or quotes
                if value.contains(",") || value.contains("\"") || value.contains("\n") {
                    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
                } else {
                    return value
                }
            }.joined(separator: ",") + "\n"
        }
        
        // Save to file
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "query_results.csv"
        savePanel.title = "Export Query Results"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try csvContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to export results: \(error)")
            }
        }
    }
}

struct QueryResultTable: View {
    let columns: [CSVColumn]
    let rows: [CSVRow]
    
    @State private var sortColumn: String?
    @State private var sortAscending = true
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                headerRow
                dataRows
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.name) { column in
                headerCell(for: column)
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
    
    private func headerCell(for column: CSVColumn) -> some View {
        Button(action: {
            if sortColumn == column.name {
                sortAscending.toggle()
            } else {
                sortColumn = column.name
                sortAscending = true
            }
        }) {
            HStack {
                Text(column.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if sortColumn == column.name {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
                
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .frame(width: 120, height: 32, alignment: .leading)
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .trailing
        )
    }
    
    private var dataRows: some View {
        LazyVStack(spacing: 0) {
            ForEach(sortedRows, id: \.id) { row in
                dataRow(for: row)
            }
        }
    }
    
    private func dataRow(for row: CSVRow) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 120, height: 24, alignment: .leading)
                    .padding(.horizontal, 8)
                    .overlay(
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(Color(NSColor.separatorColor)),
                        alignment: .trailing
                    )
            }
        }
        .background(row.id % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor).opacity(0.3)),
            alignment: .bottom
        )
    }
    
    private var sortedRows: [CSVRow] {
        guard let sortColumn = sortColumn,
              let columnIndex = columns.firstIndex(where: { $0.name == sortColumn }) else {
            return rows
        }
        
        return rows.sorted { row1, row2 in
            guard columnIndex < row1.values.count && columnIndex < row2.values.count else {
                return false
            }
            
            let value1 = row1.values[columnIndex]
            let value2 = row2.values[columnIndex]
            
            // Try to compare as numbers first
            if let num1 = Double(value1), let num2 = Double(value2) {
                return sortAscending ? num1 < num2 : num1 > num2
            } else {
                // Fall back to string comparison
                return sortAscending ? value1 < value2 : value1 > value2
            }
        }
    }
}