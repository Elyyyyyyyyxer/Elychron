import Foundation

let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("elychron-share-test-" + UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

let first = UUID().uuidString
let second = UUID().uuidString
try ShareInbox.save([["text": "第一条"]], batch: first, in: root)
try ShareInbox.save([["text": "第二条"]], batch: second, in: root)
let pending = ShareInbox.pending(in: root)
precondition(pending.count == 2)
precondition(Set(pending.compactMap { $0["batch"] }) == [first, second])

ShareInbox.acknowledge([first], in: root)
let remaining = ShareInbox.pending(in: root)
precondition(remaining.count == 1 && remaining[0]["batch"] == second)
print("ShareInbox smoke test passed")
