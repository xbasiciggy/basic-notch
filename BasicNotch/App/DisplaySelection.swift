import Foundation

enum DisplaySelection {
    static func ids(available: [Int], automatic: Int?, selected: Int, all: Bool) -> [Int] {
        guard !available.isEmpty else { return [] }
        if all { return Array(Set(available)).sorted() }
        if selected != 0 && available.contains(selected) { return [selected] }
        if let automatic, available.contains(automatic) { return [automatic] }
        return [available[0]]
    }
}
