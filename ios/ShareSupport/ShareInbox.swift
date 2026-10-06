import Foundation

enum ShareInbox {
    static func groupIdentifier() -> String? {
        AppGroupConfiguration.identifier()
    }

    static func directory() throws -> URL {
        guard let identifier = groupIdentifier(),
              let root = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier) else {
            throw NSError(domain: "ElychronShare", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "App Group unavailable"])
        }
        let inbox = root.appendingPathComponent("ShareInbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox,
                                                withIntermediateDirectories: true)
        return inbox
    }

    static func copyAttachment(from source: URL, batch: String) throws -> URL {
        let folder = try directory().appendingPathComponent(batch, isDirectory: true)
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)
        let name = source.lastPathComponent.isEmpty ? "attachment" : source.lastPathComponent
        let destination = folder.appendingPathComponent(UUID().uuidString + "-" + name)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func save(_ items: [[String: String]], batch: String) throws {
        try save(items, batch: batch, in: directory())
    }

    static func save(_ items: [[String: String]], batch: String, in inbox: URL) throws {
        guard !items.isEmpty else { return }
        let data = try JSONSerialization.data(withJSONObject: items)
        try data.write(to: inbox.appendingPathComponent(batch + ".json"),
                       options: .atomic)
    }

    static func pending() -> [[String: String]] {
        guard let inbox = try? directory() else { return [] }
        return pending(in: inbox)
    }

    static func pending(in inbox: URL) -> [[String: String]] {
        guard let files = try? FileManager.default.contentsOfDirectory(
                at: inbox, includingPropertiesForKeys: nil) else { return [] }
        var items: [[String: String]] = []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file),
                  let batchItems = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { continue }
            for var item in batchItems {
                item["batch"] = file.deletingPathExtension().lastPathComponent
                items.append(item)
            }
        }
        return items
    }

    static func acknowledge(_ batches: [String]) {
        guard let inbox = try? directory() else { return }
        acknowledge(batches, in: inbox)
    }

    static func acknowledge(_ batches: [String], in inbox: URL) {
        for batch in Set(batches) where UUID(uuidString: batch) != nil {
            try? FileManager.default.removeItem(at: inbox.appendingPathComponent(batch + ".json"))
            try? FileManager.default.removeItem(at: inbox.appendingPathComponent(batch, isDirectory: true))
        }
    }
}
