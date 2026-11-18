"""Reject an old iOS build toolchain or archive before App Store export/upload."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess

MINIMUM_SDK = 27


def require_version(value, label):
    match = re.fullmatch(r"(\d+)(?:\.\d+)*", value.strip())
    if not match or int(match[1]) < MINIMUM_SDK:
        raise ValueError(f"{label} must be {MINIMUM_SDK} or later; found {value!r}")


def check_toolchain():
    version = subprocess.check_output(["xcodebuild", "-version"], text=True)
    match = re.search(r"^Xcode ([\d.]+)$", version, re.M)
    require_version(match[1] if match else "unknown", "Xcode")
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], text=True).strip()
    require_version(sdk, "iOS SDK")
    print(f"Verified {version.strip()}, iOS SDK {sdk}")


def check_archive(archive):
    applications = Path(archive) / "Products" / "Applications"
    apps = list(applications.glob("*.app"))
    if not apps:
        raise ValueError("Archive contains no iOS application")
    bundles = apps + [extension for app in apps for extension in app.rglob("*.appex")]
    for bundle in bundles:
        with (bundle / "Info.plist").open("rb") as file:
            info = plistlib.load(file)
        sdk = info.get("DTSDKName", "")
        match = re.fullmatch(r"iphoneos([\d.]+)", sdk)
        require_version(match[1] if match else "unknown", f"{bundle.name} SDK")
        print(f"Verified {bundle.name}: {sdk}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    if args.archive:
        check_archive(args.archive)
    else:
        check_toolchain()


if __name__ == "__main__":
    main()
