import Flutter
import Foundation
import UIKit

final class ShareStreamHandler: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    private var delivered = Set<String>()
    private var sceneActivationObserver: NSObjectProtocol?

    deinit {
        if let sceneActivationObserver {
            NotificationCenter.default.removeObserver(sceneActivationObserver)
        }
    }

    func initial() -> [[String: String]] {
        let items = ShareInbox.pending()
        delivered.formUnion(items.compactMap { $0["batch"] })
        return items
    }

    func acknowledge(_ batches: [String]) {
        ShareInbox.acknowledge(batches)
        delivered.subtract(batches)
    }

    func emit() {
        guard let sink else { return }
        let items = ShareInbox.pending().filter { item in
            guard let batch = item["batch"] else { return false }
            return !delivered.contains(batch)
        }
        guard !items.isEmpty else { return }
        delivered.formUnion(items.compactMap { $0["batch"] })
        sink(items)
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        if let sceneActivationObserver {
            NotificationCenter.default.removeObserver(sceneActivationObserver)
        }
        // UIScene apps no longer receive AppDelegate's foreground callback.
        sceneActivationObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.emit()
        }
        emit()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        if let sceneActivationObserver {
            NotificationCenter.default.removeObserver(sceneActivationObserver)
        }
        sceneActivationObserver = nil
        return nil
    }
}
