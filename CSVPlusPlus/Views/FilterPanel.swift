import SwiftUI

struct FilterPanel: View {
    @ObservedObject var dataManager: CSVDataManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Filters")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            
            HStack {
                Picker("Logic", selection: $dataManager.filterSet.logic) {
                    ForEach(FilterLogic.allCases, id: \.self) { logic in
                        Text(logic.rawValue).tag(logic)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                
                Spacer()
                
                Button(action: { dataManager.addFilter() }) {
                    Label("Add Filter", systemImage: "plus.circle")
                }
            }
            
            Divider()
            
            if dataManager.filterSet.filters.isEmpty {
                Text("No filters applied")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(dataManager.filterSet.filters) { filter in
                            FilterRow(
                                filter: filter,
                                columns: dataManager.columns,
                                dataManager: dataManager
                            )
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 600, height: 400)
    }
}

struct FilterRow: View {
    let filter: FilterCriteria
    let columns: [CSVColumn]
    @ObservedObject var dataManager: CSVDataManager
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: binding(for: \.isEnabled))
                .toggleStyle(.checkbox)
            
            Picker("Column", selection: binding(for: \.columnIndex)) {
                ForEach(columns) { column in
                    Text(column.name).tag(column.index)
                }
            }
            .frame(width: 150)
            
            Picker("Operation", selection: binding(for: \.operation)) {
                ForEach(FilterOperation.allCases, id: \.self) { operation in
                    if !operation.requiresNumeric || selectedColumn?.type == .numeric {
                        Text(operation.rawValue).tag(operation)
                    }
                }
            }
            .frame(width: 120)
            
            TextField("Value", text: binding(for: \.value))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            
            if filter.operation == .between {
                TextField("To", text: binding(for: \.secondValue))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            
            Button(action: { dataManager.removeFilter(filter) }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
    
    var selectedColumn: CSVColumn? {
        columns.first { $0.index == filter.columnIndex }
    }
    
    func binding<T>(for keyPath: WritableKeyPath<FilterCriteria, T>) -> Binding<T> {
        Binding(
            get: {
                if let index = dataManager.filterSet.filters.firstIndex(where: { $0.id == filter.id }) {
                    return dataManager.filterSet.filters[index][keyPath: keyPath]
                }
                return filter[keyPath: keyPath]
            },
            set: { newValue in
                if let index = dataManager.filterSet.filters.firstIndex(where: { $0.id == filter.id }) {
                    dataManager.filterSet.filters[index][keyPath: keyPath] = newValue
                }
            }
        )
    }
}