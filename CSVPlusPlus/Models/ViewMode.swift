import Foundation

enum ViewMode: String, CaseIterable, Identifiable {
    case table = "Table"
    case query = "Query"
    
    var id: String { self.rawValue }
}