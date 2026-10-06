import plistlib
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
cases = [
    ("renamed", "com.example.elychron.ABCDEF1234", {
        "ALTBundleIdentifier": "com.example.elychron",
        "ALTAppGroups": ["group.com.example.elychron.ABCDEF1234"],
    }, "group.com.example.elychron.ABCDEF1234"),
    ("share", "com.example.elychron.ShareExtension.ABCDEF1234", {
        "ALTBundleIdentifier": "com.example.elychron.ShareExtension",
        "ALTAppGroups": ["group.com.example.elychron.ABCDEF1234"],
    }, "group.com.example.elychron.ABCDEF1234"),
    ("widget", "com.example.elychron.WidgetExtensions.ABCDEF1234", {
        "ALTBundleIdentifier": "com.example.elychron.WidgetExtensions",
        "ALTAppGroups": ["group.com.example.elychron.ABCDEF1234"],
    }, "group.com.example.elychron.ABCDEF1234"),
    ("debug", "com.example.elychron.debug.ShareExtension", {},
     "group.com.example.elychron.debug"),
    ("ordinary", "com.example.elychron", {}, "group.com.example.elychron"),
    ("upstream", "top.celechron.celechron.WidgetExtensions", {},
     "group.top.celechron.celechron"),
    ("missing_group", "com.example.elychron.ABCDEF1234", {
        "ALTBundleIdentifier": "com.example.elychron", "ALTAppGroups": [],
    }, "nil"),
    ("unrelated", "com.example.elychron.ABCDEF1234", {
        "ALTBundleIdentifier": "com.example.elychron",
        "ALTAppGroups": ["group.unrelated.ABCDEF1234"],
    }, "nil"),
    ("ambiguous", "com.example.elychron.ABCDEF1234", {
        "ALTBundleIdentifier": "com.example.elychron",
        "ALTAppGroups": ["group.com.example.elychron.ABCDEF1234",
                         "group.com.example.elychron.OTHER12345"],
    }, "nil"),
]

with tempfile.TemporaryDirectory(prefix="elychron-signing-") as temporary:
    directory = Path(temporary)
    binary = directory / "signing-test"
    sources = [root / "ios/ShareSupport/ShareInbox.swift",
               root / "test_native/signing_configuration/main.swift"]
    configuration = root / "ios/ShareSupport/AppGroupConfiguration.swift"
    if configuration.exists():
        sources.insert(0, configuration)
    subprocess.run(["swiftc", "-module-cache-path", str(directory / "cache"),
                    *map(str, sources), "-o", str(binary)], check=True)
    for name, identifier, metadata, expected in cases:
        app = directory / (name + ".app") / "Contents"
        executable = app / "MacOS" / "SigningTest"
        executable.parent.mkdir(parents=True)
        executable.write_bytes(binary.read_bytes())
        executable.chmod(0o755)
        (app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier, "CFBundleExecutable": "SigningTest",
            "CFBundlePackageType": "APPL", **metadata,
        }))
        subprocess.run([str(executable), expected], check=True)
print("SIGNING_CONFIGURATION_TESTS_PASSED")
