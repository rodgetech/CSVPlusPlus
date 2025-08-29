# Product Requirements Document (PRD)

**Project Name:** CSV Analyzer (Mac OS)  
**Author:** Luis Rodge  
**Date:** 2025-08-28  
**Version:** 1.1

---

## 1. Overview

The CSV Analyzer is a macOS-native application designed to efficiently load, view, and analyze CSV files containing millions of rows. Unlike Numbers or Excel, which truncate or struggle with large datasets, this application ensures **full dataset visibility** and provides **basic data analysis functionalities** without performance degradation.

The app will use **SwiftUI** for the interface, leveraging its modern, declarative UI framework and virtualized components for performance.

---

## 2. Goals

- Enable developers and analysts to open CSV files with millions of rows without truncation.
- Provide essential analysis tools:
  - Filter rows by one or multiple columns.
  - Sort rows by one or multiple columns.
  - Sum values in numeric columns.
- Maintain high performance and low memory footprint using streaming and virtualization techniques.
- Provide a table-like UI similar to Numbers/Excel for familiarity.

---

## 3. Target Users

- Software engineers and data analysts who work with large CSV reports.
- Users on macOS who need to quickly analyze data without relying on Excel or other paid software.
- Users who require a fast, responsive application for data inspection.

---

## 4. Core Features

### 4.1 CSV Import

- Import CSV files from the local file system.
- Handle files **up to millions of rows** without truncation.
- Streaming parsing to avoid high memory usage.

### 4.2 Table Rendering

- Use **SwiftUI** with `LazyVStack` or equivalent virtualized components.
- Render only visible rows to maintain smooth scrolling and low memory usage.
- Column headers should remain sticky during scrolling.
- Support dynamic column resizing and reordering.

### 4.3 Filtering

- Filter rows by one or multiple columns.
- Multiple filter conditions using AND/OR logic.
- Support for text, numeric, and date-based filtering.

### 4.4 Sorting

- Sort rows by one or multiple columns.
- Support ascending and descending order.
- Sorting should be optimized to handle large datasets efficiently.

### 4.5 Aggregations

- Sum numeric columns.
- Optionally, count distinct values in a column.
- Aggregations should work on filtered datasets as well.

### 4.6 UI/UX

- Native macOS interface using **SwiftUI**.
- Table navigation with keyboard and mouse.
- Display total rows loaded and currently filtered rows.

---

## 5. Performance Requirements

- Must handle **CSV files with up to 10 million rows** on a typical MacBook.
- Streaming CSV parsing to avoid loading the entire file into memory.
- Virtualized SwiftUI table to render only visible rows for smooth scrolling.
- Filtering, sorting, and summing operations should be executed with minimal latency (< 1 second for typical operations).

---

## 6. Technical Requirements

- Language: **Swift**
- Framework: **SwiftUI**
- Data handling:
  - Use **streaming CSV parser** for large files (e.g., `CodableCSV` or `FileHandle` line-by-line parsing).
  - Maintain lightweight in-memory models for visible rows; use chunked or disk-backed storage for very large datasets.
- UI:
  - Use `LazyVStack` or similar SwiftUI virtualization for the table.
  - Support dynamic column resizing, reordering, and filtering UI.

---

## 7. Non-Functional Requirements

- User-friendly and familiar UI.
- High reliability and crash-free handling of large datasets.
- Extensible for future features like export to CSV, additional aggregation functions, and more advanced filtering.

---

## 8. Milestones

1. **MVP**
   - CSV import and streaming parsing.
   - Virtualized SwiftUI table rendering.
   - Basic filtering, sorting, and summing.
2. **Performance Optimization**
   - Memory-efficient data storage.
   - Optimized filtering and sorting for large datasets.
3. **UX Enhancements**
   - Sticky headers, column resizing, reordering.
   - Display row counts, filtered row counts.
4. **Optional Future Features**
   - Export filtered/sorted data.
   - Additional aggregation functions.
   - Multi-file comparison.

---

## 9. Success Metrics

- Ability to load and render CSV files with millions of rows without truncation or crashing.
- Filter and sort operations execute under 1 second on large datasets.
- Users can perform basic analysis (filter, sort, sum) without technical assistance.

---

## 10. Risks

- Extremely large CSV files could still hit memory limits; mitigation through streaming and chunking.
- Sorting multi-million-row datasets may require temporary on-disk storage or optimized algorithms.
- Developers need to carefully implement SwiftUI virtualization for smooth performance.

---

## 11. References

- [SwiftUI LazyVStack & Virtualization](https://developer.apple.com/documentation/swiftui/lazyvstack)
- CSV parsing libraries: `CSV.swift`, `CodableCSV`
