import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/audit-local-branches.py"
REAL_GIT = shutil.which("git")


class AuditTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Fixture")
        (self.repo / "file").write_text("base\n")
        self.git("add", "file")
        self.git("commit", "-qm", "base")
        self.git("branch", "old")
        self.git("checkout", "-qb", "same-patch")
        (self.repo / "file").write_text("base\npatch\n")
        self.git("commit", "-qam", "original patch")
        self.git("checkout", "-q", "main")
        self.git("cherry-pick", "--no-commit", "same-patch")
        self.git("commit", "-qm", "equivalent patch")
        self.git("checkout", "-qb", "unique")
        (self.repo / "extra").write_text("independent\n")
        self.git("add", "extra")
        self.git("commit", "-qm", "unique patch")
        self.git("checkout", "-q", "main")
        (self.repo / "staged").write_text("preserve staged data\n")
        self.git("add", "staged")

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.run([REAL_GIT, *args], cwd=self.repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

    def audit(self, env=None, base="refs/heads/main"):
        return subprocess.run(["python3", str(SCRIPT), "--base", base], cwd=self.repo, env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def test_evidence_and_index_remain_unchanged(self):
        before_refs = self.git("show-ref")
        before_status = self.git("status", "--porcelain=v1", "-z")
        before_index = self.git("diff", "--cached", "--raw", "--no-abbrev", "-z")
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        by_ref = {item["ref"]: item for item in data["branches"]}
        self.assertEqual(by_ref["refs/heads/old"]["status"], "ancestor")
        self.assertEqual(by_ref["refs/heads/same-patch"]["status"], "patch-equivalent")
        self.assertEqual(by_ref["refs/heads/unique"]["status"], "unique-patches")
        self.assertTrue(by_ref["refs/heads/main"]["checked_out"])
        self.assertEqual(self.git("show-ref"), before_refs)
        self.assertEqual(self.git("status", "--porcelain=v1", "-z"), before_status)
        self.assertEqual(self.git("diff", "--cached", "--raw", "--no-abbrev", "-z"), before_index)

    def test_failed_git_cherry_is_not_classified_as_merged(self):
        bindir = Path(self.tmp.name) / "bin"
        bindir.mkdir()
        fake = bindir / "git"
        fake.write_text("#!/bin/sh\nfor arg do [ \"$arg\" = cherry ] && exit 42; done\nexec '" + REAL_GIT + "' \"$@\"\n")
        fake.chmod(0o755)
        env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ["PATH"])
        result = self.audit(env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"failed", result.stderr)

    def test_missing_base_fails_without_output(self):
        result = self.audit(base="refs/heads/nonexistent")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")

    def test_empty_cherry_evidence_is_rejected(self):
        bindir = Path(self.tmp.name) / "bin"
        bindir.mkdir()
        fake = bindir / "git"
        fake.write_text("#!/bin/sh\nfor arg do [ \"$arg\" = cherry ] && exit 0; done\nexec '" + REAL_GIT + "' \"$@\"\n")
        fake.chmod(0o755)
        env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ["PATH"])
        result = self.audit(env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"empty or invalid evidence", result.stderr)

    def test_ref_drift_is_reported_before_results_are_emitted(self):
        bindir = Path(self.tmp.name) / "bin"
        bindir.mkdir()
        fake = bindir / "git"
        fake.write_text("#!/bin/sh\nfor arg do if [ \"$arg\" = cherry ]; then '" + REAL_GIT + "' update-ref refs/heads/unique refs/heads/main; break; fi; done\nexec '" + REAL_GIT + "' \"$@\"\n")
        fake.chmod(0o755)
        env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ["PATH"])
        result = self.audit(env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"changed", result.stderr)


if __name__ == "__main__":
    unittest.main()
