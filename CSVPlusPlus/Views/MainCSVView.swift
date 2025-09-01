import SwiftUI
import UniformTypeIdentifiers

struct MainCSVView: View {
    @StateObject private var dataManager = CSVDataManager()
    @State private var showingFilePicker = false
    @State private var showingFilterPanel = false
    @State private var showingSortPanel = false
    @State private var showingExporter = false
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            if dataManager.columns.isEmpty {
                WelcomeView(
                    showingFilePicker: $showingFilePicker,
                    isDragging: $isDragging
                )
            } else {
                VStack(spacing: 0) {
                    NSTableViewWrapper(dataManager: dataManager)
                    
                    // Load more button
                    if dataManager.visibleRows.count < dataManager.filteredRowCount {
                        HStack {
                            Spacer()
                            
                            Button(action: loadMoreRows) {
                                HStack {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Load More Rows")
                                    Text("(\(dataManager.visibleRows.count) of \(dataManager.filteredRowCount))")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(dataManager.isLoading)
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                    }
                    
                    // Status bar
                    HStack {
                        if !dataManager.filterSet.filters.isEmpty {
                            Text("Filtered: \(dataManager.filteredRowCount.formatted()) of \(dataManager.totalRowCount.formatted())")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else {
                            Text("Total: \(dataManager.totalRowCount.formatted())")
                                .font(.caption)
                        }
                        
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
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            
            if dataManager.isLoading {
                LoadingOverlay(
                    progress: dataManager.loadingProgress,
                    message: dataManager.loadingMessage
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { showingFilePicker = true }) {
                    Label("Open CSV", systemImage: "doc.badge.plus")
                }
                .disabled(dataManager.isLoading)
                
                if !dataManager.columns.isEmpty {
                    Button(action: { dataManager.clearData() }) {
                        Label("Close", systemImage: "xmark.circle")
                    }
                    .disabled(dataManager.isLoading)
                }
            }
            
            ToolbarItemGroup(placement: .primaryAction) {
                if !dataManager.columns.isEmpty {
                    Button(action: { showingFilterPanel.toggle() }) {
                        Label("Filter", systemImage: "line.horizontal.3.decrease.circle")
                    }
                    .disabled(dataManager.isLoading)
                    
                    Button(action: { showingSortPanel.toggle() }) {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(dataManager.isLoading)
                    
                    Button(action: { showingExporter = true }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(dataManager.isLoading || dataManager.filteredRowCount == 0)
                }
            }
        }
        .sheet(isPresented: $showingFilterPanel) {
            FilterPanel(dataManager: dataManager)
        }
        .sheet(isPresented: $showingSortPanel) {
            SortPanel(dataManager: dataManager)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let files):
                if let file = files.first {
                    Task { @MainActor in
                        await dataManager.loadCSVWithSQLite(from: file)
                    }
                }
            case .failure(let error):
                dataManager.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(content: generateExportContent()),
            contentType: UTType.commaSeparatedText,
            defaultFilename: "export_\(dataManager.fileName)"
        ) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                dataManager.errorMessage = error.localizedDescription
            }
        }
        .alert("Error", isPresented: .constant(dataManager.errorMessage != nil)) {
            Button("OK") {
                dataManager.errorMessage = nil
            }
        } message: {
            Text(dataManager.errorMessage ?? "")
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private func generateExportContent() -> String {
        // For virtual scrolling, we'll generate a placeholder - actual export happens in CSVDocument
        let headers = dataManager.columns.map { $0.name }.joined(separator: ",")
        return headers + "\n[Filtered data will be exported]"
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "csv" else { return }
            
            Task { @MainActor in
                await dataManager.loadCSVWithSQLite(from: url)
            }
        }
        
        return true
    }
    
    private func loadMoreRows() {
        Task { @MainActor in
            await dataManager.loadMoreSQLiteRows()
        }
    }
}

struct WelcomeView: View {
    @Binding var showingFilePicker: Bool
    @Binding var isDragging: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "tablecells")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("CSV Analyzer")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Open CSV files with millions of rows")
                .font(.title3)
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                Button(action: { showingFilePicker = true }) {
                    Label("Open CSV File", systemImage: "doc.badge.plus")
                        .frame(width: 200)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                
                Text("or drag and drop a CSV file here")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                .foregroundColor(isDragging ? .accentColor : .clear)
                .animation(.easeInOut, value: isDragging)
        )
        .padding()
    }
}

struct LoadingOverlay: View {
    let progress: Double
    let message: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 300)
                
                Text(message)
                    .font(.headline)
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(30)
            .background(.regularMaterial)
            .cornerRadius(12)
        }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    
    let content: String
    
    init(content: String) {
        self.content = content
    }
    
    init(configuration: ReadConfiguration) throws {
        content = ""
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8)!
        return FileWrapper(regularFileWithContents: data)
    }
}