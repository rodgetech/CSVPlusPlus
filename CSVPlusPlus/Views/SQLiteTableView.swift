import SwiftUI

struct SQLiteTableView: View {
    @ObservedObject var dataManager: CSVDataManager
    @State private var currentPage = 0
    @State private var pageSize = 100
    @State private var sortColumn: String?
    @State private var sortAscending = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Single synchronized ScrollView for both headers and data
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        // Data rows
                        ForEach(dataManager.visibleRows) { row in
                            HStack(spacing: 0) {
                                ForEach(dataManager.columns) { column in
                                    let cellValue = row.value(at: column.index)
                                    Text(cellValue)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                        .frame(width: column.width, alignment: columnAlignment(for: column))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .overlay(
                                            Rectangle()
                                                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                                        )
                                        .onAppear {
                                            if row.id < 3 && column.index < 3 {
                                                print("🎯 SQLite Cell[\(row.id)][\(column.index)] = '\(cellValue)' | Column: '\(column.name)' | Row values: \(row.values.prefix(5))")
                                            }
                                        }
                                }
                            }
                            .background(row.id % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
                        }
                        
                        // Load more button at the bottom
                        if dataManager.visibleRows.count < dataManager.totalRowCount {
                            Button(action: loadMoreRows) {
                                HStack {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Load More Rows")
                                }
                                .padding()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                        }
                    } header: {
                        // Pinned column headers that scroll horizontally with data
                        HStack(spacing: 0) {
                            ForEach(dataManager.columns) { column in
                                Button(action: {
                                    if sortColumn == column.name {
                                        sortAscending.toggle()
                                    } else {
                                        sortColumn = column.name
                                        sortAscending = true
                                    }
                                    loadData()
                                }) {
                                    HStack {
                                        Text(column.name)
                                            .font(.headline)
                                            .lineLimit(1)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        if sortColumn == column.name {
                                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                .frame(width: column.width)
                                .background(Color.gray.opacity(0.15))
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                                )
                            }
                        }
                        .background(Color.gray.opacity(0.1))
                    }
                }
            }
            
            Divider()
            
            // Status bar
            HStack {
                Text("Total: \(dataManager.totalRowCount.formatted())")
                    .font(.caption)
                
                Spacer()
                
                Text("Showing: \(dataManager.visibleRows.count.formatted()) rows")
                    .font(.caption)
                
                if !dataManager.filterSet.filters.isEmpty {
                    Divider()
                        .frame(height: 12)
                        .padding(.horizontal, 8)
                    
                    Label("\(dataManager.filterSet.filters.count) filters active", systemImage: "line.horizontal.3.decrease.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                if sortColumn != nil {
                    Divider()
                        .frame(height: 12)
                        .padding(.horizontal, 8)
                    
                    Label("Sorted by \(sortColumn ?? "")", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Aggregation bar (if we have aggregation results)
            if !dataManager.aggregationResults.isEmpty {
                Divider()
                AggregationBar(dataManager: dataManager)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .onAppear {
            loadData()
        }
        .onChange(of: dataManager.filterSet.filters) { _ in
            currentPage = 0
            loadData()
        }
    }
    
    private func columnAlignment(for column: CSVColumn) -> Alignment {
        switch column.type {
        case .numeric:
            return .trailing
        case .boolean:
            return .center
        default:
            return .leading
        }
    }
    
    private func loadData() {
        Task {
            await dataManager.loadSQLiteData(
                page: currentPage,
                pageSize: pageSize,
                sortColumn: sortColumn,
                sortAscending: sortAscending
            )
        }
    }
    
    private func loadMoreRows() {
        currentPage += 1
        Task {
            await dataManager.appendSQLiteData(
                page: currentPage,
                pageSize: pageSize,
                sortColumn: sortColumn,
                sortAscending: sortAscending
            )
        }
    }
}

struct AggregationBar: View {
    @ObservedObject var dataManager: CSVDataManager
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(dataManager.aggregationResults, id: \.columnName) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.columnName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        Text(dataManager.aggregationEngine.formatResult(result))
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
    }
}