import SwiftUI

struct SortPanel: View {
    @ObservedObject var dataManager: CSVDataManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Sort Options")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            
            HStack {
                Text("Sort criteria are applied in priority order")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { dataManager.addSort() }) {
                    Label("Add Sort", systemImage: "plus.circle")
                }
            }
            
            Divider()
            
            if dataManager.sortSet.criteria.isEmpty {
                Text("No sort criteria applied")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(dataManager.sortSet.criteria.sorted { $0.priority < $1.priority }) { sort in
                            SortRow(
                                sort: sort,
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
        .frame(width: 500, height: 400)
    }
}

struct SortRow: View {
    let sort: SortCriteria
    let columns: [CSVColumn]
    @ObservedObject var dataManager: CSVDataManager
    
    var body: some View {
        HStack(spacing: 12) {
            Text("Priority \(sort.priority + 1)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 60)
            
            Picker("Column", selection: binding(for: \.columnIndex)) {
                ForEach(columns) { column in
                    Text(column.name).tag(column.index)
                }
            }
            .frame(width: 180)
            
            Picker("Direction", selection: binding(for: \.direction)) {
                ForEach(SortDirection.allCases, id: \.self) { direction in
                    Text(direction.rawValue).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            
            Button(action: { moveSortUp() }) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(sort.priority == 0)
            
            Button(action: { moveSortDown() }) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(sort.priority == dataManager.sortSet.criteria.count - 1)
            
            Button(action: { dataManager.removeSort(sort) }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
    
    func binding<T>(for keyPath: WritableKeyPath<SortCriteria, T>) -> Binding<T> {
        Binding(
            get: {
                if let index = dataManager.sortSet.criteria.firstIndex(where: { $0.id == sort.id }) {
                    return dataManager.sortSet.criteria[index][keyPath: keyPath]
                }
                return sort[keyPath: keyPath]
            },
            set: { newValue in
                if let index = dataManager.sortSet.criteria.firstIndex(where: { $0.id == sort.id }) {
                    dataManager.sortSet.criteria[index][keyPath: keyPath] = newValue
                }
            }
        )
    }
    
    func moveSortUp() {
        guard let currentIndex = dataManager.sortSet.criteria.firstIndex(where: { $0.id == sort.id }),
              currentIndex > 0 else { return }
        
        dataManager.sortSet.criteria[currentIndex].priority -= 1
        dataManager.sortSet.criteria[currentIndex - 1].priority += 1
    }
    
    func moveSortDown() {
        guard let currentIndex = dataManager.sortSet.criteria.firstIndex(where: { $0.id == sort.id }),
              currentIndex < dataManager.sortSet.criteria.count - 1 else { return }
        
        dataManager.sortSet.criteria[currentIndex].priority += 1
        dataManager.sortSet.criteria[currentIndex + 1].priority -= 1
    }
}