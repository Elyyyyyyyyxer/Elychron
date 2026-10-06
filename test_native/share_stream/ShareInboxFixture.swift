import Foundation

// Isolate the stream adapter from the user's App Group files.
enum ShareInbox {
    static var items: [[String: String]] = []

    static func pending() -> [[String: String]] { items }

    static func acknowledge(_ batches: [String]) {
        items.removeAll { batches.contains($0["batch"] ?? "") }
    }
}
