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
        
        // Modern grid styling - only horizontal lines, no vertical lines
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.gridColor = NSColor.separatorColor.withAlphaComponent(0.3)
        
        // Set custom row height for better spacing
        tableView.rowHeight = 34
        
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
        
        // Set up the callback for updating sort descriptors (only once)
        if dataManager.updateTableViewSortDescriptors == nil {
            dataManager.updateTableViewSortDescriptors = { [weak tableView, weak dataManager] in
                guard let tableView = tableView, let dataManager = dataManager else { return }
                let newDescriptors = dataManager.getCurrentSortDescriptors()
                DispatchQueue.main.async {
                    tableView.sortDescriptors = newDescriptors
                }
            }
        }
        
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
                    
                    // Improve header typography
                    tableColumn.headerCell.title = csvColumn.name
                    tableColumn.headerCell.font = NSFont.systemFont(ofSize: 13, weight: .heavy)
                    
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
                
                // Improved typography
                textField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
                textField.textColor = NSColor.labelColor
                
                cellView?.addSubview(textField)
                cellView?.textField = textField
                
                // Better padding - 10px horizontal, centered vertically
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 10),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -10),
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            }
            
            // Get data for this row
            let cellValue = getCellValue(row: row, columnIndex: columnIndex)
            cellView?.textField?.stringValue = cellValue
            
            // Set alignment based on column type
            let column = columns[columnIndex]
            switch column.type {
            case .integer, .decimal:
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
            let sortDescriptors = tableView.sortDescriptors
            
            guard !sortDescriptors.isEmpty else {
                return
            }
            
            // AppKit handles all the complexity - just convert to SQL and reload
            Task { @MainActor in
                await self.dataManager?.loadMultiSortedData(sortDescriptors: sortDescriptors)
                tableView.reloadData()
            }
        }
        
        // Row height is now set globally to 34px for better spacing
        
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            return true // Allow row selection
        }
        
        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            // Handle column header clicks for aggregation selection
            let columnIdentifier = tableColumn.identifier.rawValue
            guard let column = columns.first(where: { $0.name == columnIdentifier }) else {
                return
            }
            
            Task { @MainActor in
                dataManager?.selectColumnForAggregation(column)
            }
        }
    }
}

// Custom cell view with hover effects
class HoverableTableCellView: NSTableCellView {
    private var trackingArea: NSTrackingArea?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupTrackingArea()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTrackingArea()
    }
    
    private func setupTrackingArea() {
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.06).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    
    override var wantsUpdateLayer: Bool {
        return true
    }
    
    override func updateLayer() {
        layer?.cornerRadius = 0
    }
}