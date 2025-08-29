# CSV++ - High-Performance CSV Analyzer for macOS

## Overview
CSV++ is a SwiftUI-based macOS application designed to handle CSV files with millions of rows efficiently. The app uses SQLite as its backend for data storage and querying, providing fast filtering, sorting, and aggregation capabilities.

## Architecture

### Core Components

1. **SQLite Backend** (`CSVPlusPlus/Services/SQLiteCSVHandler.swift`)
   - Imports CSV data into a temporary SQLite database
   - Handles all data queries with SQL-based filtering and sorting
   - Provides pagination support for efficient memory usage
   - Key methods:
     - `importCSV(from:progress:)` - Imports CSV file to database
     - `getRows(offset:limit:sortColumn:sortAscending:filters:)` - Retrieves paginated data
     - `getTotalCount(filters:)` - Gets total row count with optional filters

2. **Data Manager** (`CSVPlusPlus/ViewModels/CSVDataManager.swift`)
   - Main view model that coordinates between UI and SQLite backend
   - Manages filter and sort state
   - Handles data loading and pagination
   - Key methods:
     - `loadCSVWithSQLite(from:)` - Loads CSV file using SQLite
     - `loadSQLiteData(page:pageSize:sortColumn:sortAscending:)` - Loads data page
     - `appendSQLiteData(page:pageSize:sortColumn:sortAscending:)` - Appends more rows

3. **Main UI** (`CSVPlusPlus/Views/SQLiteTableView.swift`)
   - Uses SwiftUI with LazyVStack for virtual scrolling
   - Implements synchronized horizontal/vertical scrolling with pinned headers
   - Shows aggregation results bar at bottom
   - Pagination with "Load More" button

4. **Entry Point** (`CSVPlusPlus/CSVPlusPlusApp.swift`)
   - Launches `MainCSVView()` as the root view

## Build Commands

```bash
# Build the project (verify compilation)
xcodebuild build -project CSVPlusPlus.xcodeproj -scheme CSVPlusPlus

# Run the app in Xcode
open CSVPlusPlus.xcodeproj
# Then press Cmd+R to run

# Clean build folder
xcodebuild clean -project CSVPlusPlus.xcodeproj -scheme CSVPlusPlus
```

## Common Tasks

### Adding a New Filter Operation
1. Add the operation to `FilterOperation` enum in `Models/FilterCriteria.swift`
2. Update `buildFilterClause` in `SQLiteCSVHandler.swift` to handle the SQL generation
3. Update `buildSQLFilters` in `CSVDataManager.swift` to build the filter string

### Modifying Table Display
- Edit `SQLiteTableView.swift` for UI changes
- The table uses LazyVStack with Section for pinned headers
- Data rows are in the Section body, headers are in the Section header

### Performance Considerations
- The app displays up to 10,000 rows in the UI for optimal performance
- Data is loaded in pages of 100 rows by default
- SQLite indexes are created on the first 5 columns for faster sorting

## Known Issues

### Column Alignment Issue
**Status**: PENDING FIX
**Description**: Data may not align correctly with column headers in some cases
**Debug Location**: Check `SQLiteTableView.swift` lines 18-36 where cell values are rendered
**Related**: The parseCSVLine method in SQLiteCSVHandler.swift handles CSV parsing

## Architecture Decisions

### Why SQLite?
- Previous implementation used in-memory virtual scrolling which had performance issues
- SQLite provides:
  - Efficient handling of millions of rows
  - SQL-based filtering and sorting
  - Minimal memory footprint
  - Fast aggregations

### Why Not SwiftUI Table?
- SwiftUI's native Table component lacks virtual scrolling
- Would load all rows in memory causing performance issues with large datasets
- LazyVStack provides better performance with custom virtual scrolling

### Deleted Components (Code Cleanup)
The following files were removed during cleanup as they're no longer needed:
- Virtual scrolling implementations (VirtualDataSource, VirtualScrollManager)
- Alternative table views (SimpleTableView, DatabaseTableView, VirtualTableView)
- Streaming CSV readers (replaced by SQLite import)
- Old data models (replaced by SQLite-based approach)

## Testing

### Test Files
- `sample_data.csv` - 20 rows for quick testing
- `large_sample_100k.csv` - 100,000 rows for performance testing
- Use `generate_large_csv.py` to create larger test files

### Manual Testing Checklist
1. Open a CSV file and verify data loads
2. Click column headers to sort
3. Add filters and verify results update
4. Scroll horizontally and verify headers stay aligned
5. Click "Load More Rows" and verify pagination works
6. Check aggregation results display correctly

## Dependencies
- **CodableCSV** (0.6.7+) - For initial CSV parsing during import
- **SQLite3** - Built into macOS, used for data storage

## System Requirements
- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## File Structure
```
CSVPlusPlus/
├── CSVPlusPlusApp.swift          # App entry point
├── Views/
│   ├── MainCSVView.swift         # Main container view
│   ├── SQLiteTableView.swift     # Table implementation
│   └── FilterView.swift          # Filter UI
├── ViewModels/
│   └── CSVDataManager.swift      # Main data manager
├── Services/
│   ├── SQLiteCSVHandler.swift    # SQLite operations
│   └── AggregationEngine.swift   # Aggregation calculations
└── Models/
    ├── CSVColumn.swift            # Column definition
    ├── CSVRow.swift              # Row data structure
    ├── FilterCriteria.swift      # Filter models
    └── SortCriteria.swift        # Sort models
```

## Important Notes
- Always use absolute paths when working with files
- The app creates temporary SQLite databases in NSTemporaryDirectory()
- Databases are cleaned up when the app closes
- Column names are sanitized for SQL compatibility (spaces become underscores)