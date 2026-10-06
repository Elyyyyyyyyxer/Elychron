import Foundation
import UIKit

func check(_ condition: Bool, _ message: String) {
    guard condition else {
        print("FAIL: \(message)")
        exit(1)
    }
}

var events: [[[String: String]]] = []
let handler = ShareStreamHandler()
_ = handler.onListen(withArguments: nil) { value in
    if let items = value as? [[String: String]] { events.append(items) }
}
check(events.isEmpty, "an empty inbox must not deliver a share")

ShareInbox.items = [["batch": "first", "name": "synthetic-photo.png", "path": "/synthetic/photo.png"]]
NotificationCenter.default.post(name: UIScene.didActivateNotification, object: nil)
check(events.count == 1 && events[0][0]["batch"] == "first",
      "a scene returning to the foreground must deliver a newly saved photo")

NotificationCenter.default.post(name: UIScene.didActivateNotification, object: nil)
handler.emit()
check(events.count == 1, "scene and legacy activation must not duplicate delivery")

ShareInbox.items.append(["batch": "second", "text": "synthetic second share"])
NotificationCenter.default.post(name: UIScene.didActivateNotification, object: nil)
check(events.count == 2 && events[1].count == 1 && events[1][0]["batch"] == "second",
      "a later scene activation must deliver only the new batch")

_ = handler.onCancel(withArguments: nil)
ShareInbox.items.append(["batch": "third", "text": "synthetic canceled-stream share"])
NotificationCenter.default.post(name: UIScene.didActivateNotification, object: nil)
check(events.count == 2, "a canceled stream must stop delivering events")

_ = handler.onListen(withArguments: nil) { value in
    if let items = value as? [[String: String]] { events.append(items) }
}
check(events.count == 3 && events[2][0]["batch"] == "third",
      "reconnecting the stream must deliver the remaining undelivered batch")
_ = handler.onCancel(withArguments: nil)
print("ShareStream scene lifecycle regression tests passed")
