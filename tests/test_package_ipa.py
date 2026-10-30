import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("package_ipa", Path(__file__).parents[1] / "scripts/package_ipa.py")
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "TravelEnglish.app"
        self.app.mkdir()
        self.write_fixture()

    def write_fixture(self, platform=2, supported="iPhoneOS", cpu=0x0100000C):
        (self.app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "TravelEnglish",
            "CFBundleSupportedPlatforms": [supported],
        }))
        header = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0)
        command = struct.pack("<6I", 0x32, 24, platform, 0, 0, 0)
        (self.app / "TravelEnglish").write_bytes(header + command)

    def test_payload_and_digest(self):
        output = self.root / "artifacts/app.ipa"
        digest = packager.package(self.app, output)
        with zipfile.ZipFile(output) as archive:
            self.assertEqual(set(archive.namelist()), {
                "Payload/TravelEnglish.app/Info.plist",
                "Payload/TravelEnglish.app/TravelEnglish",
            })
        self.assertEqual(output.with_suffix(".ipa.sha256").read_text().split()[0], digest)

    def test_rejects_simulator_even_with_iphone_plist(self):
        self.write_fixture(platform=7)
        with self.assertRaisesRegex(ValueError, "simulator"):
            packager.validate_app(self.app)

    def test_rejects_simulator_plist(self):
        self.write_fixture(supported="iPhoneSimulator")
        with self.assertRaisesRegex(ValueError, "iPhoneOS"):
            packager.validate_app(self.app)

    def test_rejects_wrong_architecture(self):
        self.write_fixture(cpu=0x01000007)
        with self.assertRaisesRegex(ValueError, "arm64"):
            packager.validate_app(self.app)

    def test_rejects_truncated_commands(self):
        binary = self.app / "TravelEnglish"
        binary.write_bytes(binary.read_bytes()[:-1])
        with self.assertRaisesRegex(ValueError, "Truncated"):
            packager.validate_app(self.app)

    def test_does_not_overwrite_artifact(self):
        output = self.root / "app.ipa"
        output.write_bytes(b"existing")
        with self.assertRaises(FileExistsError):
            packager.package(self.app, output)
        self.assertEqual(output.read_bytes(), b"existing")

    def test_rejects_bundle_path_escape(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "../outside",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
        }))
        with self.assertRaisesRegex(ValueError, "executable"):
            packager.validate_app(self.app)


if __name__ == "__main__":
    unittest.main()
