"""Exercise Makefile routing with a fake SDK; no downloads or hardware."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MakeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.sdk = Path(self.tmp.name) / "sdk"
        self.sdk.mkdir()
        self.log = Path(self.tmp.name) / "calls.jsonl"
        self.env = os.environ.copy()
        for name in ("MAKEFLAGS", "MFLAGS", "MAKELEVEL"):
            self.env.pop(name, None)
        self.env["CHIBI_TEST_LOG"] = str(self.log)
        (self.sdk / "export.sh").write_text(
            'export PATH="${CHIBI_IDF_DIR}:$PATH"\n'
        )
        tool = self.sdk / "idf.py"
        tool.write_text(
            '#!/usr/bin/env python3\n'
            'import json, os, sys\n'
            'with open(os.environ["CHIBI_TEST_LOG"], "a") as f:\n'
            '    f.write(json.dumps([os.environ.get("IDF_TARGET"), sys.argv[1:]]) + "\\n")\n'
            'sys.exit(int(os.environ.get("CHIBI_TEST_EXIT", "0")))\n'
        )
        tool.chmod(0o755)

    def run_make(self, *args):
        return subprocess.run(
            ["make", "--no-print-directory", f"IDF_DIR={self.sdk}", *args],
            cwd=ROOT, env=self.env, text=True, capture_output=True,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_build_and_serial_routing(self):
        for target in ("build", "menuconfig", "clean", "fullclean"):
            result = self.run_make(target)
            self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_make("flash-monitor", "PORT=/dev/test device")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [
            ["esp32", ["build"]], ["esp32", ["menuconfig"]],
            ["esp32", ["clean"]], ["esp32", ["fullclean"]],
            ["esp32", ["-p", "/dev/test device", "flash", "monitor"]],
        ])

    def test_missing_port_and_sdk_fail_clearly(self):
        result = self.run_make("flash", "PORT=")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Specify a serial port", result.stderr)
        self.assertFalse(self.log.exists())
        (self.sdk / "export.sh").unlink()
        result = self.run_make("build")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("make setup", result.stderr)

    def test_sdk_failure_reaches_make(self):
        self.env["CHIBI_TEST_EXIT"] = "7"
        self.assertNotEqual(self.run_make("build").returncode, 0)

    def test_setup_reuses_matching_checkout_and_rejects_wrong_version(self):
        install = self.sdk / "install.sh"
        install.write_text('printf "%s\\n" "$*" > "$CHIBI_TEST_LOG"\n')

        def git(*args):
            subprocess.run(
                ["git", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                 "-C", str(self.sdk), *args], check=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            )

        git("init")
        git("add", ".")
        git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
            "commit", "-m", "Fixture")
        git("tag", "v5.5.1")
        # Keep the installer log outside the checkout so repeating setup is safe.
        for _ in range(2):
            result = self.run_make("setup", "SKIP_DEPS=1")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.log.read_text(), "esp32\n")
        install.write_text(install.read_text() + "# changed\n")
        result = self.run_make("setup", "SKIP_DEPS=1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tracked changes", result.stderr)
        git("add", "install.sh")
        git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
            "commit", "-m", "Different version")
        result = self.run_make("setup", "SKIP_DEPS=1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be at v5.5.1", result.stderr)


if __name__ == "__main__":
    unittest.main()
