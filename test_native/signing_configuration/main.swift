import Foundation

let expected = CommandLine.arguments[1] == "nil" ? nil : CommandLine.arguments[1]
let actual = ShareInbox.groupIdentifier() as String?
guard actual == expected else {
    print("SIGNING_GROUP_FAILED expected=\(expected ?? "nil") actual=\(actual ?? "nil")")
    exit(1)
}
print("SIGNING_GROUP_PASSED")
