"""Safety and repeatability checks for the personal iOS helper (no Apple tooling)."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("ios.sh")


class PersonalIOSHelperTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "checkout with spaces"
        self.helper = self.root / "Tools/personal/ios.sh"
        self.helper.parent.mkdir(parents=True)
        shutil.copy2(SCRIPT, self.helper)
        (self.root / "Config").mkdir()
        (self.root / "Config/BundleId.xcconfig").write_text("// supported wrapper\n")
        self.config = self.root / "Config/BundleIdSecrets.xcconfig"
        self.commands = Path(self.tmp.name) / "commands"
        self.commands.mkdir()
        self.env = dict(os.environ)
        self.env["PATH"] = str(self.commands) + os.pathsep + self.env["PATH"]

    def run_helper(self, *args):
        return subprocess.run(
            ["bash", str(self.helper), *args], env=self.env,
            capture_output=True, text=True, check=False,
        )

    def configure(self, prefix="com.personal.test", team="ABCDE12345"):
        return self.run_helper("configure", "--prefix", prefix, "--team", team)

    def fake(self, name, body):
        executable = self.commands / name
        executable.write_text("#!/bin/sh\n" + body + "\n")
        executable.chmod(0o755)

    def fake_mac(self, xcode="26.0", sdk="26.0", xcodegen="2.45.0"):
        self.fake("uname", "echo Darwin")
        self.fake("xcodebuild", f"echo 'Xcode {xcode}'")
        self.fake("xcrun", f"echo '{sdk}'")
        self.fake("xcodegen", f"echo 'Version: {xcodegen}'")

    def test_configure_creates_private_file_and_is_repeatable(self):
        first = self.configure()
        self.assertEqual(first.returncode, 0, first.stderr)
        original = self.config.read_bytes()
        mtime = self.config.stat().st_mtime_ns
        self.assertIn(b"BUNDLE_ID_PREFIX = com.personal.test\n", original)
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)
        second = self.configure()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.config.read_bytes(), original)
        self.assertEqual(self.config.stat().st_mtime_ns, mtime)
        self.assertIn("already exists", second.stdout)

    def test_existing_different_configuration_is_preserved(self):
        original = "// existing user settings\nBUNDLE_ID_PREFIX = com.other.app\n"
        self.config.write_text(original)
        result = self.configure()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_text(), original)
        self.assertIn("preserved", result.stderr)

    def test_symlink_is_preserved_without_touching_target(self):
        target = Path(self.tmp.name) / "external.xcconfig"
        target.write_text("original\n")
        self.config.symlink_to(target)
        result = self.configure()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(target.read_text(), "original\n")

    def test_broken_symlink_is_rejected(self):
        self.config.symlink_to(Path(self.tmp.name) / "missing")
        self.assertNotEqual(self.configure().returncode, 0)
        self.assertTrue(self.config.is_symlink())

    def test_upstream_and_example_prefixes_are_rejected(self):
        for prefix in ("com.noopapp", "com.noopapp.personal", "com.example", "com.yourdomain"):
            with self.subTest(prefix=prefix):
                self.assertNotEqual(self.configure(prefix=prefix).returncode, 0)
                self.assertFalse(self.config.exists())

    def test_invalid_prefix_is_not_evaluated_or_written(self):
        marker = Path(self.tmp.name) / "should-not-exist"
        for prefix in ("nodots", "com.personal app", "com.personal\nEVIL = YES", f"com.$(touch {marker})"):
            with self.subTest(prefix=prefix):
                self.assertNotEqual(self.configure(prefix=prefix).returncode, 0)
                self.assertFalse(self.config.exists())
                self.assertFalse(marker.exists())

    def test_invalid_team_is_rejected_without_writing(self):
        for team in ("", "123", "YOURTEAMID", "apple@example.com", "abcdE12345", "ABCDE12345\nOTHER=1"):
            with self.subTest(team=team):
                self.assertNotEqual(self.configure(team=team).returncode, 0)
                self.assertFalse(self.config.exists())

    def test_missing_and_unknown_arguments_are_rejected(self):
        for args in (("configure", "--prefix"), ("configure", "--password", "bad"), ("build", "--upload"), ("publish",)):
            with self.subTest(args=args):
                self.assertNotEqual(self.run_helper(*args).returncode, 0)
                self.assertFalse(self.config.exists())

    def test_linux_refuses_apple_builds_with_explicit_reason(self):
        self.fake("uname", "echo Linux")
        for command in ("check", "baseline", "build", "open"):
            with self.subTest(command=command):
                result = self.run_helper(command)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("require a Mac", result.stderr)

    def test_version_preflight_accepts_required_and_newer_tools(self):
        for versions in (("26.0", "26.0", "2.45.0"), ("27.1", "27.1", "3.0.0")):
            with self.subTest(versions=versions):
                self.fake_mac(*versions)
                result = self.run_helper("check")
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_version_preflight_rejects_each_old_prerequisite(self):
        for versions in (("16.4", "26.0", "2.45.0"), ("26.0", "18.5", "2.45.0"), ("26.0", "26.0", "2.44.1")):
            with self.subTest(versions=versions):
                self.fake_mac(*versions)
                self.assertNotEqual(self.run_helper("check").returncode, 0)

    def test_fork_commands_require_explicit_personal_configuration(self):
        self.fake_mac()
        for command in ("build", "open"):
            with self.subTest(command=command):
                result = self.run_helper(command)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unique personal prefix", result.stderr)
                self.assertFalse(self.config.exists())


if __name__ == "__main__":
    unittest.main()
