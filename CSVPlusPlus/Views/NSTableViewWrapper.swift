import SwiftUI
import AppKit

struct NSTableViewWrapper: NSViewRepresentable {
    @ObservedObject var dataManager: CSVDataManager
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        
        // Configure table view
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        
        // Add visible grid lines
        tableView.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        tableView.gridColor = NSColor.separatorColor
        
        // Enable sorting
        tableView.allowsColumnSelection = false
        tableView.allowsMultipleSelection = false
        
        // Store references in coordinator
        context.coordinator.tableView = tableView
        context.coordinator.dataManager = dataManager
        
        // Configure scroll view
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }
        
        let coordinator = context.coordinator
        
        // Update coordinator data - this fixes MainActor issues
        Task { @MainActor in
            let hasNewData = coordinator.updateData(
                columns: dataManager.columns,
                rows: dataManager.visibleRows,
                totalRowCount: dataManager.totalRowCount
            )
            
            // Update table columns if they changed
            coordinator.updateColumns(in: tableView)
            
            // Only reload if data actually changed - let sorting handle its own reloads
            if hasNewData {
                tableView.reloadData()
            }
        }
    }
}

extension NSTableViewWrapper {
    @MainActor
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var tableView: NSTableView?
        weak var dataManager: CSVDataManager?
        
        private var columns: [CSVColumn] = []
        private var rows: [CSVRow] = []
        private var totalRowCount: Int = 0
        var isSorting = false
        
        // Data cache for windowed loading
        private var dataWindow: [CSVRow] = []
        private var windowStart: Int = 0
        private var windowSize: Int = 1000
        
        func updateData(columns: [CSVColumn], rows: [CSVRow], totalRowCount: Int) -> Bool {
            let hasNewData = self.rows.count != rows.count || self.columns.count != columns.count
            
            self.columns = columns
            self.rows = rows
            self.totalRowCount = totalRowCount
            self.dataWindow = rows
            self.windowStart = 0
            
            return hasNewData
        }
        
        func updateColumns(in tableView: NSTableView) {
            // Only update columns if they actually changed to preserve sort descriptors
            let existingColumnCount = tableView.tableColumns.count
            let newColumnCount = columns.count
            
            // Check if column structure changed
            var columnsChanged = existingColumnCount != newColumnCount
            if !columnsChanged {
                for (index, csvColumn) in columns.enumerated() {
                    if index < existingColumnCount {
                        let existingColumn = tableView.tableColumns[index]
                        if existingColumn.identifier.rawValue != csvColumn.name {
                            columnsChanged = true
                            break
                        }
                    }
                }
            }
            
            // Only rebuild columns if they actually changed
            if columnsChanged {
                // Store current sort descriptors to restore them
                let currentSortDescriptors = tableView.sortDescriptors
                
                // Remove existing columns
                let existingColumns = Array(tableView.tableColumns)
                for column in existingColumns {
                    tableView.removeTableColumn(column)
                }
                
                // Add new columns
                for (_, csvColumn) in columns.enumerated() {
                    let columnIdentifier = NSUserInterfaceItemIdentifier(rawValue: csvColumn.name)
                    let tableColumn = NSTableColumn(identifier: columnIdentifier)
                    tableColumn.title = csvColumn.name
                    tableColumn.minWidth = 80
                    tableColumn.maxWidth = 400
                    tableColumn.width = max(100, csvColumn.width)
                    
                    // Set up sort descriptor prototypes
                    let sortDescriptor = NSSortDescriptor(key: csvColumn.name, ascending: true)
                    tableColumn.sortDescriptorPrototype = sortDescriptor
                    
                    tableColumn.headerCell.title = csvColumn.name
                    tableView.addTableColumn(tableColumn)
                }
                
                // Restore sort descriptors if they're still valid
                if !currentSortDescriptors.isEmpty {
                    tableView.sortDescriptors = currentSortDescriptors
                }
            }
        }
        
        // MARK: - NSTableViewDataSource
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            // Return current visible rows count to prevent infinite loading
            return rows.count
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn = tableColumn else { return nil }
            
            let identifier = tableColumn.identifier
            
            // Find column index by name
            guard let columnIndex = columns.firstIndex(where: { $0.name == identifier.rawValue }),
                  columnIndex < columns.count else { return nil }
            
            // Get or create cell view
            let cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "cell_\(columnIndex)")
            var cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
            
            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = cellIdentifier
                
                let textField = NSTextField()
                textField.isBordered = false
                textField.backgroundColor = .clear
                textField.isEditable = false
                textField.isSelectable = false
                textField.cell?.lineBreakMode = .byTruncatingTail
                textField.translatesAutoresizingMaskIntoConstraints = false
                
                cellView?.addSubview(textField)
                cellView?.textField = textField
                
                // Add constraints
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            }
            
            // Get data for this row
            let cellValue = getCellValue(row: row, columnIndex: columnIndex)
            cellView?.textField?.stringValue = cellValue
            
            // Set alignment based on column type
            let column = columns[columnIndex]
            switch column.type {
            case .numeric:
                cellView?.textField?.alignment = .right
            case .boolean:
                cellView?.textField?.alignment = .center
            default:
                cellView?.textField?.alignment = .left
            }
            
            return cellView
        }
        
        private func getCellValue(row: Int, columnIndex: Int) -> String {
            // Simple bounds check - return from visible rows only
            guard row < rows.count else {
                return "Loading..." // Show loading state for rows outside current window
            }
            
            let csvRow = rows[row]
            return csvRow.value(at: columnIndex)
        }
        
        // MARK: - NSTableViewDelegate
        
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            print("🔄 sortDescriptorsDidChange: \(tableView.sortDescriptors.map { "\($0.key ?? "nil"):\($0.ascending)" })")
            
            guard let sortDescriptor = tableView.sortDescriptors.first,
                  let columnName = sortDescriptor.key else { 
                print("🔄 No valid sort descriptor")
                return 
            }
            
            print("🔄 Sorting by \(columnName) ascending=\(sortDescriptor.ascending)")
            
            // Load sorted data from SQLite and reload table - don't touch sortDescriptors!
            Task { @MainActor in
                guard let columnIndex = self.columns.firstIndex(where: { $0.name == columnName }) else {
                    print("🔄 Column not found: \(columnName)")
                    return
                }
                
                // Fetch sorted data from SQLite
                await self.dataManager?.loadSortedData(
                    columnIndex: columnIndex,
                    columnName: columnName,
                    ascending: sortDescriptor.ascending
                )
                
                // Only reload data, preserving sort descriptors
                tableView.reloadData()
                
                print("🔄 Sort complete - data reloaded")
            }
        }
        
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            return 20 // Standard row height
        }
        
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            return true // Allow row selection
        }
    }
}