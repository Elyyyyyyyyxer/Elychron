import Foundation

enum AppGroupConfiguration {
    static func identifier(in bundle: Bundle = .main) -> String? {
        let original = bundle.object(forInfoDictionaryKey: "ALTBundleIdentifier") as? String
            ?? bundle.bundleIdentifier ?? ""
        let root = [".ShareExtension", ".WidgetExtensions"].reduce(original) { value, suffix in
            value.hasSuffix(suffix) ? String(value.dropLast(suffix.count)) : value
        }
        guard !root.isEmpty else { return nil }
        let expected = "group." + root
        // AltStore writes the profile's effective groups into every bundle it signs.
        guard let metadata = bundle.object(forInfoDictionaryKey: "ALTAppGroups") else {
            return expected
        }
        guard let groups = metadata as? [String] else { return nil }
        let matches = Set(groups.filter { group in
            if group == expected { return true }
            guard group.hasPrefix(expected + ".") else { return false }
            let suffix = String(group.dropFirst(expected.count + 1))
            return suffix.range(of: "^[A-Za-z0-9]{10}$", options: .regularExpression) != nil
        })
        // Never pick an unrelated or ambiguous group, which could split app/extension data.
        return matches.count == 1 ? matches.first : nil
    }
}
