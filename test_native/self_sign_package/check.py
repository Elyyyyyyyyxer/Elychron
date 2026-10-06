import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

with tempfile.TemporaryDirectory(prefix="elychron-package-check-") as temporary:
    root = Path(temporary).resolve()
    with zipfile.ZipFile(sys.argv[1]) as archive:
        assert archive.testzip() is None, "IPA ZIP invalid"
        for info in archive.infolist():
            target = (root / info.filename).resolve()
            assert target.is_relative_to(root), "ZIP path escapes package"
            archive.extract(info, root)
            if not info.is_dir():
                target.chmod((info.external_attr >> 16) & 0o777)
    assert not list(root.rglob("*.mobileprovision")), "Personal provisioning profile present"
    assert not list(root.rglob("*.p12")), "Signing certificate archive present"
    app = root / "Payload/Runner.app"
    identifier = plistlib.loads((app / "Info.plist").read_bytes())["CFBundleIdentifier"]
    extensions = list((app / "PlugIns").glob("*.appex"))
    assert {p.name for p in extensions} == {"ShareExtension.appex", "WidgetExtensions.appex"}
    for bundle in [app, *extensions, *app.rglob("*.framework"), *app.rglob("*.dylib")]:
        details = subprocess.run(["codesign", "-d", "--verbose=4", str(bundle)],
                                 check=True, capture_output=True, text=True).stderr
        assert "Signature=adhoc" in details, "Personal signing identity present"
        assert "TeamIdentifier=not set" in details, "Personal signing team present"
    for bundle in [app, *extensions]:
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        assert not {"ALTDeviceID", "ALTServerID", "ALTCertificateID"}.intersection(info)
        entitlements = plistlib.loads(subprocess.check_output(
            ["codesign", "-d", "--entitlements", ":-", str(bundle)],
            stderr=subprocess.DEVNULL))
        assert entitlements == {
            "com.apple.security.application-groups": ["group." + identifier]
        }, "Shared capability missing or personal entitlements present"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print("SELF_SIGN_PACKAGE_PRIVACY_AND_CAPABILITIES_PASSED")
