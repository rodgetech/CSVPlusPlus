# CSV++ - High-Performance CSV Analyzer for macOS

A powerful, fast, and memory-efficient CSV reader for macOS, capable of handling millions of rows without truncation or performance issues.

## Features

- **Handle Millions of Rows**: Stream-based parsing ensures efficient memory usage
- **Virtual Scrolling**: LazyVStack renders only visible rows for smooth performance
- **Advanced Filtering**: Multi-column filters with AND/OR logic, text/numeric/date operations
- **Multi-Column Sorting**: Sort by multiple columns with priority ordering
- **Aggregations**: Real-time sum, average, count, and distinct calculations
- **Native macOS UI**: Built with SwiftUI for a familiar, responsive experience
- **Column Type Detection**: Automatic detection of text, numeric, date, and boolean columns
- **Export Functionality**: Export filtered and sorted data to new CSV files

## Building the Project

1. Open `CSVPlusPlus.xcodeproj` in Xcode
2. Ensure you have macOS 14.0+ SDK installed
3. Select your development team in project settings
4. Build and run (⌘+R)

## Package Dependencies

The project uses Swift Package Manager for dependencies:
- **CodableCSV**: For efficient CSV parsing (added via Package.swift)

To add the dependency in Xcode:
1. Select the project in the navigator
2. Go to Package Dependencies tab
3. Click the + button
4. Enter: `https://github.com/dehesa/CodableCSV.git`
5. Select version 0.6.7 or later

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
- Click the Sort button in the toolbar
- Add multiple sort criteria with priority ordering
- Sort ascending or descending
- Adjust priority with up/down arrows

### Aggregations
- Click on any column header to see aggregations
- Numeric columns show: Sum, Average, Min, Max, Count
- All columns show: Count, Distinct Count

### Performance Tips
- The app displays up to 10,000 rows in the UI for optimal performance
- Filtering and sorting operate on the full dataset
- Export functionality works with the complete filtered dataset

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
- **CSVStreamReader**: Line-by-line file reading with buffering
- **CSVChunkProcessor**: Manages data in chunks for memory efficiency
- **CSVTableView**: Virtual table with LazyVStack for performance
- **FilterEngine**: Efficient row filtering with multiple criteria
- **SortEngine**: Multi-column sorting with priority support
- **AggregationEngine**: Real-time statistical calculations

### Performance Optimizations
- **Streaming**: Files are read line-by-line, never fully loaded
- **Virtualization**: Only visible rows are rendered
- **Chunking**: Data processed in manageable chunks
- **Debouncing**: Filter/sort operations are debounced for responsiveness
- **Memory Management**: Automatic cache eviction and memory monitoring

## System Requirements
- macOS 14.0 or later
- 8GB RAM recommended for files with millions of rows
- Swift 5.9 or later

## Known Limitations
- Display limited to 10,000 rows in UI (full data used for operations)
- Very large files (>10 million rows) may require additional optimization
- Complex regex patterns may impact filtering performance

## Future Enhancements
- Column statistics and visualizations
- Advanced data type detection
- Pivot table functionality
- Multi-file comparison
- Custom formula support
- Data validation rules