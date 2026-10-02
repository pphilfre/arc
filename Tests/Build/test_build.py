import contextlib
import importlib.util
import io
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result
config = module("configure")
ipa = module("package_ipa")

class ConfigurationTests(unittest.TestCase):
    def test_production_forces_attribution_on(self):
        for environment, hidden in (("production", False), ("development", True)):
            with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {
                "MAPBOX_ACCESS_TOKEN": "pk.test", "ARC_BUILD_ENVIRONMENT": environment,
                "ARC_HIDE_MAP_ATTRIBUTION": "true"
            }, clear=True):
                path = Path(temp) / "out.plist"
                config.configure(Path(temp) / "missing", path)
                self.assertEqual(plistlib.loads(path.read_bytes())["ArcHideMapAttribution"], hidden)
    def test_public_token_only_and_no_secret_in_logs(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {}, clear=True):
            root = Path(temp)
            env = root / ".env.local"
            env.write_text('MAPBOX_ACCESS_TOKEN="pk.test_runtime"\nMAPBOX_DOWNLOADS_TOKEN=sk.test_secret\n')
            output = root / "generated.plist"
            logs = io.StringIO()
            with contextlib.redirect_stdout(logs): config.configure(env, output)
            info = plistlib.loads(output.read_bytes())
            self.assertEqual(info["MBXAccessToken"], "pk.test_runtime")
            self.assertNotIn(b"sk.test_secret", output.read_bytes())
            self.assertNotIn("pk.test_runtime", logs.getvalue())
            self.assertNotIn("sk.test_secret", logs.getvalue())
            self.assertEqual(info["UIBackgroundModes"], ["location", "audio"])
            self.assertTrue(info["NSSupportsLiveActivities"])

    def test_ci_precedence_and_xml_escaping(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {"MAPBOX_ACCESS_TOKEN": "pk.test&value"}, clear=True):
            root = Path(temp); env = root / "env"
            env.write_text("MAPBOX_ACCESS_TOKEN=pk.local\n")
            config.configure(env, root / "out.plist")
            self.assertEqual(plistlib.loads((root / "out.plist").read_bytes())["MBXAccessToken"], "pk.test&value")

    def test_rejects_secret_as_runtime_token_and_changed_bundle_id(self):
        for values in ({"MAPBOX_ACCESS_TOKEN": "sk.secret"},
                       {"MAPBOX_ACCESS_TOKEN": "pk.test", "ARC_BUNDLE_IDENTIFIER": "other.app"},
                       {"MAPBOX_ACCESS_TOKEN": "pk.replace_with_your_public_mapbox_token"}):
            with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, values, clear=True):
                with self.assertRaises(ValueError):
                    config.configure(Path(temp) / "missing", Path(temp) / "out")

    def test_safe_env_parser_does_not_execute_shell_text(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "env"
            path.write_text("# comment\nexport VALUE='$(arbitrary-command)'\n")
            self.assertEqual(config.read_env(path)["VALUE"], "$(arbitrary-command)")

class PackagingTests(unittest.TestCase):
    def make_app(self, root, platform="iphoneos"):
        app = root / "Arc.app"; app.mkdir()
        (app / "Arc").write_bytes(b"test-executable")
        (app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "dev.freddiephilpot.arc", "CFBundleExecutable": "Arc", "DTPlatformName": platform}))
        extension = app / "PlugIns/ArcActivity.appex"; extension.mkdir(parents=True)
        (extension / "ArcActivity").write_bytes(b"extension")
        framework = app / "Frameworks/Example.framework"; framework.mkdir(parents=True)
        (framework / "Example").write_bytes(b"framework")
        return app
    def test_payload_includes_executable_frameworks_and_extension(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); app = self.make_app(root)
            output = root / "Arc.ipa"; ipa.package(app, output)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(set(archive.namelist()), {
                    "Payload/Arc.app/Arc", "Payload/Arc.app/Info.plist",
                    "Payload/Arc.app/PlugIns/ArcActivity.appex/ArcActivity",
                    "Payload/Arc.app/Frameworks/Example.framework/Example"})
                self.assertTrue(all(entry.create_system == 3 for entry in archive.infolist()))
    def test_rejects_simulator_and_missing_executable(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); app = self.make_app(root, "iphonesimulator")
            with self.assertRaises(ValueError): ipa.package(app, root / "out.ipa")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); app = self.make_app(root); (app / "Arc").unlink()
            with self.assertRaises(ValueError): ipa.package(app, root / "out.ipa")
    @unittest.skipIf(os.name == "nt", "Creating symlinks needs additional Windows privileges")
    def test_preserves_framework_symlink(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); app = self.make_app(root)
            (app / "Frameworks/Current").symlink_to("Example.framework")
            output = root / "out.ipa"; ipa.package(app, output)
            with zipfile.ZipFile(output) as archive:
                entry = archive.getinfo("Payload/Arc.app/Frameworks/Current")
                self.assertEqual((entry.external_attr >> 16) & 0o170000, 0o120000)
                self.assertEqual(archive.read(entry), b"Example.framework")

if __name__ == "__main__": unittest.main()
