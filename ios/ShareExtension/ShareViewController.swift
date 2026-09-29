import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let message = UILabel()
    private let button = UIButton(type: .system)
    private var saved = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        message.text = "正在保存到 Elychron…"
        message.textAlignment = .center
        message.numberOfLines = 0
        message.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("取消", for: .normal)
        button.addTarget(self, action: #selector(finish), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(message)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            message.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            message.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            button.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 24),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
        Task { await saveInput() }
    }

    @MainActor
    private func saveInput() async {
        let batch = UUID().uuidString
        var entries: [[String: String]] = []
        for item in extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
            if let caption = item.attributedContentText?.string, !caption.isEmpty {
                entries.append(["text": caption])
            }
            for provider in item.attachments ?? [] {
                entries.append(await extract(provider, batch: batch))
            }
        }
        do {
            try ShareInbox.save(entries, batch: batch)
            saved = !entries.isEmpty
            message.text = saved
                ? "已保存。打开 Elychron 即可新建待办或添加到已有待办。"
                : "没有收到可分享的内容。"
            button.setTitle("完成", for: .normal)
        } catch {
            message.text = "保存失败：请检查 Elychron 的 App Group 权限。"
            button.setTitle("关闭", for: .normal)
        }
    }

    private func extract(_ provider: NSItemProvider, batch: String) async -> [String: String] {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            guard let value = await loadItem(provider, type: UTType.fileURL.identifier) else {
                return ["name": provider.suggestedName ?? "文件", "error": "unreadable"]
            }
            if let url = value as? URL {
                return copyFile(url, provider: provider, batch: batch)
            }
            if let text = value as? String, let url = URL(string: text), url.isFileURL {
                return copyFile(url, provider: provider, batch: batch)
            }
            return ["name": provider.suggestedName ?? "文件", "error": "unreadable"]
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let value = await loadItem(provider, type: UTType.url.identifier) {
            if let url = value as? URL {
                return url.isFileURL
                    ? copyFile(url, provider: provider, batch: batch)
                    : ["text": url.absoluteString]
            }
            if let text = value as? String {
                if let url = URL(string: text), url.isFileURL {
                    return copyFile(url, provider: provider, batch: batch)
                }
                return ["text": text]
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let value = await loadItem(provider, type: UTType.plainText.identifier) {
            if let text = value as? String { return ["text": text] }
            if let data = value as? Data,
               let text = String(data: data, encoding: .utf8) { return ["text": text] }
        }
        guard let typeID = provider.registeredTypeIdentifiers.first(where: {
            guard let type = UTType($0) else { return false }
            return type.conforms(to: .data)
        }) else {
            return ["name": provider.suggestedName ?? "文件", "error": "unreadable"]
        }
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { source, _ in
                do {
                    guard let source else { throw NSError(domain: "ElychronShare", code: 2) }
                    let copied = try ShareInbox.copyAttachment(from: source, batch: batch)
                    continuation.resume(returning: [
                        "path": copied.path,
                        "name": provider.suggestedName ?? source.lastPathComponent,
                        "mime": UTType(typeID)?.preferredMIMEType ?? "application/octet-stream",
                    ])
                } catch {
                    continuation.resume(returning: [
                        "name": provider.suggestedName ?? "文件", "error": "unreadable",
                    ])
                }
            }
        }
    }

    private func copyFile(_ source: URL, provider: NSItemProvider, batch: String) -> [String: String] {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            let copied = try ShareInbox.copyAttachment(from: source, batch: batch)
            let name = provider.suggestedName ?? source.lastPathComponent
            let mime = UTType(filenameExtension: source.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            return ["path": copied.path, "name": name, "mime": mime]
        } catch {
            return ["name": provider.suggestedName ?? "文件", "error": "unreadable"]
        }
    }

    private func loadItem(_ provider: NSItemProvider, type: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }

    @objc private func finish() {
        if saved {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: NSError(domain: "ElychronShare", code: 3))
        }
    }
}
