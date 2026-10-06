"""Package a built Elychron app for user signing without personal profiles/certificates."""

import argparse
import hashlib
import plistlib
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path


def sign(bundle, entitlements=None):
    command = ["codesign", "--force", "--sign", "-", "--timestamp=none"]
    if entitlements:
        command += ["--entitlements", str(entitlements)]
    subprocess.run([*command, str(bundle)], check=True, capture_output=True)


def package(app, output):
    if not (app / "Info.plist").is_file():
        raise ValueError("Input must be a built iOS app")
    if output.exists():
        raise ValueError("Output already exists; choose a new path")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="elychron-self-sign-") as temporary:
        root = Path(temporary)
        staged = root / "Payload/Runner.app"
        shutil.copytree(app, staged)
        extensions = list((staged / "PlugIns").glob("*.appex"))
        if {p.name for p in extensions} != {"ShareExtension.appex", "WidgetExtensions.appex"}:
            raise ValueError("Both Elychron extensions must be retained")
        for path in staged.rglob("*"):
            if path.is_file() and path.suffix.lower() in {".mobileprovision", ".p12", ".pfx"}:
                path.unlink()
        for bundle in [staged, *extensions]:
            info_path = bundle / "Info.plist"
            info = plistlib.loads(info_path.read_bytes())
            for key in ["ALTDeviceID", "ALTServerID", "ALTCertificateID", "ALTAppGroups",
                        "ALTBundleIdentifier"]:
                info.pop(key, None)
            info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        for library in staged.rglob("*.dylib"):
            sign(library)
        for framework in sorted(staged.rglob("*.framework"), key=lambda p: len(p.parts), reverse=True):
            sign(framework)
        identifier = plistlib.loads((staged / "Info.plist").read_bytes())["CFBundleIdentifier"]
        for bundle in [*extensions, staged]:
            neutral = root / "capabilities.plist"
            neutral.write_bytes(plistlib.dumps({
                "com.apple.security.application-groups": ["group." + identifier],
            }))
            # Ad hoc signatures retain capability metadata for AltStore; no personal certificate.
            sign(bundle, neutral)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(staged)], check=True)
        temporary_ipa = root / "self-sign.ipa"
        with zipfile.ZipFile(temporary_ipa, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted((root / "Payload").rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(root))
        shutil.move(str(temporary_ipa), output)
    with output.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    output.with_suffix(output.suffix + ".sha256").write_text(digest + "  " + output.name + "\n")
    print("SELF_SIGN_IPA_PACKAGED " + str(output))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package(args.app.resolve(), args.output.resolve())
