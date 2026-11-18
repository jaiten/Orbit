import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("sdk", ROOT / "scripts/check_ios_sdk.py")
sdk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sdk)


class SDKRequirement(unittest.TestCase):
    def test_toolchain_checks_the_device_sdk_not_only_xcode_version(self):
        with patch.object(sdk.subprocess, "check_output", side_effect=["Xcode 27.2\nBuild version 18C54\n", "26.2\n"]):
            with self.assertRaisesRegex(ValueError, "iOS SDK"):
                sdk.check_toolchain()
        with patch.object(sdk.subprocess, "check_output", side_effect=["Xcode 27.2\nBuild version 18C54\n", "27.2\n"]):
            sdk.check_toolchain()

    def test_old_or_unknown_versions_are_rejected(self):
        for version in ["26.2", "", "unknown", "27.2 beta", "garbage"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                sdk.require_version(version, "SDK")
        for version in ["27", "27.2", "28.0"]:
            sdk.require_version(version, "SDK")

    def test_archive_checks_app_and_every_extension(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / "Products/Applications/Orbit.app"
            extension = app / "PlugIns/OrbitWidgets.appex"
            extension.mkdir(parents=True)
            def write(bundle, name):
                (bundle / "Info.plist").write_bytes(plistlib.dumps({"DTSDKName": name}))
            write(app, "iphoneos27.2")
            write(extension, "iphoneos26.2")
            with self.assertRaisesRegex(ValueError, "OrbitWidgets"):
                sdk.check_archive(folder)
            write(extension, "iphoneos27.2")
            sdk.check_archive(folder)
            write(app, "iphonesimulator27.2")
            with self.assertRaisesRegex(ValueError, "Orbit.app"):
                sdk.check_archive(folder)

    def test_missing_archive_or_metadata_fails_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "no iOS application"):
                sdk.check_archive(folder)
            app = Path(folder) / "Products/Applications/Orbit.app"
            app.mkdir(parents=True)
            (app / "Info.plist").write_bytes(plistlib.dumps({}))
            with self.assertRaises(ValueError):
                sdk.check_archive(folder)


if __name__ == "__main__":
    unittest.main()
