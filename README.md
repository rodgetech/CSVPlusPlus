# CSV++ - High-Performance CSV Analyzer for macOS

A powerful, fast, and memory-efficient CSV reader for macOS, capable of handling millions of rows without truncation or performance issues.

## Features

- **Handle Millions of Rows**: SQLite-based backend handles massive datasets efficiently
- **Native macOS Performance**: NSTableView provides professional-grade performance like Numbers
- **Advanced Filtering**: Multi-column filters with AND/OR logic, text/numeric/date operations
- **Multi-Column Sorting**: Click column headers to sort, with SQL-based processing
- **Pagination**: Load data incrementally for responsive UI
- **Native macOS UI**: Built with SwiftUI and AppKit for optimal performance
- **Column Type Detection**: Automatic detection of text, numeric, date, and boolean columns
- **Export Functionality**: Export filtered and sorted data to new CSV files

## Building the Project

1. Open `CSVPlusPlus.xcodeproj` in Xcode
2. Ensure you have macOS 14.0+ SDK installed
3. Select your development team in project settings
4. Build and run (⌘+R)

## Dependencies

The project uses native system libraries for optimal performance:
- **SQLite3**: Built into macOS, used for data storage and querying
- **AppKit**: NSTableView for professional-grade table performance
- **SwiftUI**: Modern declarative UI framework

## Usage

### Opening CSV Files
- Click "Open CSV" in the toolbar
- Drag and drop CSV files onto the application window
- Use File > Open menu

### Filtering Data
- Click the Filter button in the toolbar
- Add multiple filter criteria
- Choose between AND/OR logic for combining filters
- Supported operations:
  - Text: Contains, Equals, Not Equals, Regex
  - Numeric: Greater Than, Less Than, Between
  - All types support regex patterns

### Sorting Data
- Click column headers to sort data ascending/descending
- SQL-based sorting handles millions of rows efficiently
- Multiple sort criteria supported through the Sort panel

### Pagination
- Data loads in pages of 100 rows by default
- Click "Load More Rows" to load additional data
- UI remains responsive regardless of total file size

### Aggregations
- Click on any column header to see aggregations
- Numeric columns show: Sum, Average, Min, Max, Count
- All columns show: Count, Distinct Count

### Performance Tips
- SQLite backend handles millions of rows without memory issues
- Filtering and sorting operate on the full dataset via SQL queries
- Only visible rows are rendered for optimal UI performance

## Test Files

### Sample Data
- `sample_data.csv`: Small 20-row sample for quick testing
- `large_sample_100k.csv`: 100,000 rows for performance testing

### Generate Larger Files
Use the included Python script to generate test files:

```bash
# Generate 100,000 rows (already generated)
python3 generate_large_csv.py

# To generate 1 million rows, modify the script and run:
# generate_large_csv('large_sample_1m.csv', 1000000)
```

## Architecture

### MVVM Pattern
- **Models**: Core data structures (CSVRow, CSVColumn, FilterCriteria, SortCriteria)
- **ViewModels**: CSVDataManager handles business logic and state
- **Views**: SwiftUI components for UI rendering

### Key Components
- **SQLiteCSVHandler**: Imports CSV data to SQLite database for efficient querying
- **NSTableViewWrapper**: SwiftUI bridge to native NSTableView for optimal performance
- **CSVDataManager**: Main view model coordinating data operations
- **AggregationEngine**: Real-time statistical calculations
- **FilterEngine**: SQL-based row filtering with multiple criteria

### Performance Optimizations
- **SQLite Backend**: Database-powered operations handle millions of rows
- **Native NSTableView**: Professional-grade table performance like Numbers app
- **Pagination**: Load data on-demand to maintain UI responsiveness
- **SQL Queries**: Efficient filtering and sorting at the database level
- **Memory Efficiency**: Constant memory usage regardless of file size

## System Requirements
- macOS 14.0 or later
- 4GB RAM minimum (8GB recommended for very large files)
- Swift 5.9 or later

## Performance Characteristics
- **Memory Usage**: Constant ~10-50MB regardless of file size
- **File Size**: Tested with 100K+ row files, supports millions of rows
- **Load Time**: Initial import creates SQLite database for fast subsequent access
- **UI Responsiveness**: Smooth scrolling and interaction with paginated data loading

## Future Enhancements
- Column statistics and visualizations
- Advanced data type detection
- Pivot table functionality
- Multi-file comparison
- Custom formula support
- Data validation rules