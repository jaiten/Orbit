import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("mtimes", ROOT / "scripts/restore_source_mtimes.py")
mtimes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mtimes)


class SourceTimestamps(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.name", "CI test")
        self.git("config", "user.email", "ci@example.invalid")
        (self.repo / "ios").mkdir()
        (self.repo / "shared").mkdir()
        self.source = self.repo / "ios/App.swift"
        self.shared = self.repo / "shared/tokens.json"
        self.source.write_text("first")
        self.shared.write_text("{}")
        self.commit("2020-01-01T00:00:00+00:00")

    def git(self, *args, **kwargs):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], **kwargs)

    def commit(self, date):
        self.git("add", ".")
        self.git("-c", "commit.gpgsign=false", "commit", "-qm", "fixture",
                 env={**os.environ, "GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date})

    def test_per_file_dates_keep_unchanged_inputs_reusable(self):
        self.source.write_text("changed")
        self.commit("2020-01-02T00:00:00+00:00")
        os.utime(self.source, (1700000000, 1700000000))
        os.utime(self.shared, (1700000000, 1700000000))
        self.assertEqual(mtimes.restore(self.repo), 2)
        self.assertEqual(self.source.stat().st_mtime, 1577923200)
        self.assertEqual(self.shared.stat().st_mtime, 1577836800)
        self.assertEqual(self.source.read_text(), "changed")
        self.assertEqual(self.git("status", "--porcelain"), b"")

    def test_dirty_inputs_are_never_hidden_from_the_compiler(self):
        self.source.write_text("uncommitted")
        os.utime(self.source, (1700000000, 1700000000))
        with self.assertRaisesRegex(RuntimeError, "clean"):
            mtimes.restore(self.repo)
        self.assertEqual(self.source.stat().st_mtime, 1700000000)

    def test_shallow_history_is_rejected(self):
        clone = self.repo / "shallow"
        subprocess.check_call(["git", "clone", "--quiet", "--depth=1", self.repo.as_uri(), str(clone)])
        with self.assertRaisesRegex(RuntimeError, "Full Git history"):
            mtimes.restore(clone)


class TestSelection(unittest.TestCase):
    def invoke(self, scope, target="", phase="test"):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            command = folder / "xcodebuild"
            output = folder / "arguments.json"
            command.write_text(f'#!{sys.executable}\nimport json,os,sys\nopen(os.environ["ORBIT_CI_ARGS"],"w").write(json.dumps(sys.argv[1:]))\n')
            command.chmod(0o755)
            result = subprocess.run(["bash", str(ROOT / "scripts/run_ios_tests.sh"), phase],
                                    env={**os.environ, "PATH": str(folder) + os.pathsep + os.environ["PATH"],
                                         "ORBIT_CI_ARGS": str(output), "IOS_TEST_SCOPE": scope,
                                         "IOS_TEST_FILTER": target, "DEVICE_ID": "fixture", "RUNNER_TEMP": str(folder)},
                                    capture_output=True, text=True)
            return result, json.loads(output.read_text()) if output.exists() else None

    def test_smoke_selects_real_ui_methods_and_the_whole_unit_bundle(self):
        result, args = self.invoke("smoke")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args[0], "test-without-building")
        self.assertIn("-only-testing:OrbitTests", args)
        methods = [value.split(":", 1)[1] for value in args if value.startswith("-only-testing:OrbitUITests/")]
        self.assertTrue(methods)
        for selector in methods:
            _, test_class, method = selector.split("/")
            source = (ROOT / f"ios/UITests/{test_class}.swift").read_text()
            self.assertRegex(source, rf"func\s+{re.escape(method)}\s*\(")

    def test_focused_filter_is_one_argument_and_never_executed_as_shell(self):
        target = "OrbitUITests/ChecklistUITests/testNotesHaveSectionsAndPages"
        result, args = self.invoke("focused", target)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-only-testing:" + target, args)
        result, args = self.invoke("focused", target + ";echo unsafe")
        self.assertEqual(result.returncode, 2)
        self.assertIsNone(args)

    def test_full_does_not_filter_and_build_can_be_reused_by_test_phase(self):
        result, args = self.invoke("full", phase="build")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args[0], "build-for-testing")
        self.assertFalse(any(arg.startswith("-only-testing:") for arg in args))
