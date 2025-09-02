import SwiftUI
import UniformTypeIdentifiers

struct SQLQueryView: View {
    @ObservedObject var dataManager: CSVDataManager
    
    @State private var sqlQuery: String = ""
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var queryResult: QueryResult?
    @State private var queryError: QueryError?
    @State private var isExecuting = false
    @State private var queryHistory: [String] = []
    @State private var showingHistory = false
    
    private let sampleQueries: [String] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Query editor section
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Button("Execute Query") {
                        executeCurrentQuery()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isExecuting || sqlQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button("Clear Query") {
                        sqlQuery = ""
                        queryResult = nil
                        queryError = nil
                    }
                    .disabled(sqlQuery.isEmpty)
                    
                    Spacer()
                    
                    Button("Query History") {
                        showingHistory.toggle()
                    }
                    .disabled(isExecuting)
                    
                    Button("Schema Info") {
                        showSchemaInfo()
                    }
                    .disabled(isExecuting)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                // SQL Editor
                SQLTextEditor(text: $sqlQuery, selectedRange: $selectedRange)
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .onTapGesture {
                        // Force focus when tapped
                    }
                    .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Results section
            QueryResultsView(
                queryResult: queryResult,
                queryError: queryError,
                isExecuting: isExecuting
            )
        }
        .onAppear {
            loadInitialQuery()
        }
        .sheet(isPresented: $showingHistory) {
            QueryHistorySheet(
                sampleQueries: sampleQueries,
                queryHistory: queryHistory,
                onQuerySelected: { query in
                    sqlQuery = query
                    showingHistory = false
                }
            )
        }
    }
    
    private func loadInitialQuery() {
        if sqlQuery.isEmpty {
            sqlQuery = "-- Welcome to CSV++ SQL Query Interface!\n-- The CSV data is loaded into a table called 'csv_data'\n-- Try these sample queries:\n\nSELECT * FROM csv_data LIMIT 10;\n\n-- SELECT COUNT(*) FROM csv_data;\n-- SELECT column_name FROM csv_data WHERE condition;\n-- SELECT column_name, COUNT(*) FROM csv_data GROUP BY column_name;"
        }
    }
    
    private func executeCurrentQuery() {
        let textEditor = SQLTextEditor(text: $sqlQuery, selectedRange: $selectedRange)
        let queryToExecute = textEditor.getCurrentQuery()
        
        guard !queryToExecute.isEmpty else {
            queryError = QueryError.syntaxError("No query to execute")
            return
        }
        
        // Clear previous results
        queryResult = nil
        queryError = nil
        isExecuting = true
        
        // Add to history if not already present
        if !queryHistory.contains(queryToExecute) {
            queryHistory.insert(queryToExecute, at: 0)
            // Keep only last 20 queries
            if queryHistory.count > 20 {
                queryHistory = Array(queryHistory.prefix(20))
            }
        }
        
        Task {
            do {
                guard let sqliteHandler = dataManager.sqliteHandler else {
                    throw QueryError.databaseNotInitialized
                }
                
                let result = try sqliteHandler.executeArbitrarySQL(queryToExecute)
                
                await MainActor.run {
                    queryResult = result
                    isExecuting = false
                }
            } catch let error as QueryError {
                await MainActor.run {
                    queryError = error
                    isExecuting = false
                }
            } catch {
                await MainActor.run {
                    queryError = QueryError.executionError(error.localizedDescription)
                    isExecuting = false
                }
            }
        }
    }
    
    private func showSchemaInfo() {
        let schemaQuery = """
        -- Schema Information for csv_data table
        PRAGMA table_info(csv_data);
        """
        
        sqlQuery = schemaQuery
        executeCurrentQuery()
    }
}

struct QueryHistorySheet: View {
    let sampleQueries: [String]
    let queryHistory: [String]
    let onQuerySelected: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Query History")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            if !queryHistory.isEmpty {
                List {
                    ForEach(queryHistory, id: \.self) { query in
                        QueryRow(query: query, onSelect: onQuerySelected)
                    }
                }
                .listStyle(.plain)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    Text("No Query History")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Execute some queries to see them appear here for quick access.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 500, height: 400)
    }
}

struct QueryRow: View {
    let query: String
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(cleanQueryForDisplay(query))
                .font(.system(.body, design: .monospaced))
                .lineLimit(3)
                .foregroundColor(.primary)
            
            if query.components(separatedBy: "\n").count > 1 {
                Text("Multi-line query")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(query)
        }
    }
    
    private func cleanQueryForDisplay(_ query: String) -> String {
        // Remove comment lines and extra whitespace for display
        let lines = query.components(separatedBy: "\n")
        let sqlLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && !trimmed.hasPrefix("--")
        }
        
        if sqlLines.isEmpty {
            return query.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return sqlLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}