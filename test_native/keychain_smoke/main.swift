import Foundation
import Security

guard CommandLine.arguments.count == 2 else {
    print("Usage: keychain-smoke <app-group>")
    exit(2)
}

// Use a unique synthetic record; never read or alter the user's credentials.
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "elychron-keychain-smoke",
    kSecAttrAccount as String: UUID().uuidString,
    kSecAttrAccessGroup as String: CommandLine.arguments[1],
    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
]
let testValue = Data("synthetic-test-only".utf8)
var writeQuery = query
writeQuery[kSecValueData as String] = testValue
let writeStatus = SecItemAdd(writeQuery as CFDictionary, nil)

var readQuery = query
readQuery[kSecReturnData as String] = true
var result: CFTypeRef?
let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &result)
let matches = (result as? Data) == testValue
let deleteStatus = SecItemDelete(query as CFDictionary)

print("KEYCHAIN_SMOKE write=\(writeStatus) read=\(readStatus) matches=\(matches) delete=\(deleteStatus)")
exit(writeStatus == errSecSuccess && readStatus == errSecSuccess &&
     matches && deleteStatus == errSecSuccess ? 0 : 1)
