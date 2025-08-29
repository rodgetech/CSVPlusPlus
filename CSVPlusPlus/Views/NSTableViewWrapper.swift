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
            
            // Only reload if data actually changed
            if hasNewData {
                print("🔄 NSTableView reloading with \(dataManager.visibleRows.count) rows")
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
            // Remove existing columns
            let existingColumns = Array(tableView.tableColumns)
            for column in existingColumns {
                tableView.removeTableColumn(column)
            }
            
            // Add new columns
            for (index, csvColumn) in columns.enumerated() {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "column_\(index)"))
                tableColumn.title = csvColumn.name
                tableColumn.minWidth = 80
                tableColumn.maxWidth = 400
                tableColumn.width = max(100, csvColumn.width)
                
                // Configure sorting
                let sortDescriptor = NSSortDescriptor(key: csvColumn.name, ascending: true)
                tableColumn.sortDescriptorPrototype = sortDescriptor
                
                // Set cell identifier for performance
                tableColumn.headerCell.title = csvColumn.name
                
                tableView.addTableColumn(tableColumn)
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
            
            // Extract column index from identifier
            let columnIndexStr = identifier.rawValue.replacingOccurrences(of: "column_", with: "")
            guard let columnIndex = Int(columnIndexStr),
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
            guard let sortDescriptor = tableView.sortDescriptors.first,
                  let key = sortDescriptor.key else { return }
            
            // Find column by name
            if let columnIndex = columns.firstIndex(where: { $0.name == key }) {
                Task { @MainActor in
                    // Update data manager sort
                    await self.dataManager?.applySortFromTableView(
                        columnIndex: columnIndex,
                        ascending: sortDescriptor.ascending
                    )
                }
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