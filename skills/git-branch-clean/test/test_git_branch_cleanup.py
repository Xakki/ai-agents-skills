import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/git-branch-clean.sh"
REAL_GIT = shutil.which("git")
PLAN_RE = re.compile(r"^plan_sha256: ([0-9a-f]{64})", re.M)


class CleanupTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.origin = root / "origin.git"
        self.work = root / "work"
        self.other = root / "other"
        self.bin = root / "bin"
        self.bin.mkdir()
        gh = self.bin / "gh"
        gh.write_text("#!/bin/sh\nexit 1\n")  # no GitHub in the fixture: the script must degrade, not call out
        gh.chmod(0o755)
        self.env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", "GIT_CONFIG_GLOBAL": os.devnull,
                    "GIT_CONFIG_SYSTEM": os.devnull}
        self.run_git(root, "init", "-q", "--bare", "-b", "main", str(self.origin))
        self.run_git(root, "clone", "-q", str(self.origin), str(self.work))
        self.identity(self.work)
        self.write(self.work, "file", "base\n")
        self.commit(self.work, "base")
        self.git("branch", "merged-ancestor")
        self.git("branch", "dev")
        self.git("branch", "backup/keep")
        self.git("branch", "wt-branch")
        self.git("worktree", "add", "-q", str(root / "wt"), "wt-branch")
        self.git("checkout", "-qb", "merged-patches")
        self.write(self.work, "patch", "patch\n")
        self.commit(self.work, "original patch")
        self.git("checkout", "-q", "main")
        self.git("cherry-pick", "--no-commit", "merged-patches")
        self.commit(self.work, "equivalent patch")
        self.git("checkout", "-qb", "unmerged")
        self.write(self.work, "extra", "independent\n")
        self.commit(self.work, "unique patch")
        self.git("checkout", "-q", "main")
        self.git("push", "-q", "origin", "main", "merged-ancestor", "merged-patches", "unmerged", "dev", "backup/keep")
        self.git("remote", "set-head", "origin", "main")
        self.run_git(root, "clone", "-q", str(self.origin), str(self.other))
        self.identity(self.other)

    def tearDown(self):
        self.tmp.cleanup()

    def run_git(self, cwd, *args):
        return subprocess.run([REAL_GIT, *args], cwd=cwd, check=True, env=self.env, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True).stdout.strip()

    def git(self, *args):
        return self.run_git(self.work, *args)

    def identity(self, repo):
        self.run_git(repo, "config", "user.email", "fixture@example.invalid")
        self.run_git(repo, "config", "user.name", "Fixture")

    def write(self, repo, name, text):
        (repo / name).write_text(text)
        self.run_git(repo, "add", name)

    def commit(self, repo, message):
        self.run_git(repo, "commit", "-qm", message)

    def cleanup(self, *args):
        return subprocess.run(["bash", str(SCRIPT), *args], cwd=self.work, env=self.env, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True)

    def plan(self, *args):
        done = self.cleanup(*args)
        self.assertEqual(done.returncode, 0, done.stderr)
        return PLAN_RE.search(done.stdout).group(1), done.stdout

    def local_branches(self):
        return set(self.git("for-each-ref", "--format=%(refname:short)", "refs/heads/").split())

    def remote_branches(self):
        out = self.run_git(self.work, "ls-remote", "--heads", "origin")
        return {line.split("refs/heads/", 1)[1] for line in out.splitlines()}

    def test_dry_run_reports_the_plan_and_deletes_nothing(self):
        before_local, before_remote = self.local_branches(), self.remote_branches()
        plan, out = self.plan()
        self.assertIn("merged-ancestor", out)
        self.assertIn("merged-patches", out)
        self.assertIn("mode: DRY-RUN", out)
        self.assertEqual((self.local_branches(), self.remote_branches()), (before_local, before_remote))
        self.assertFalse((self.work / ".git/branch-cleanup").exists())

    def test_apply_needs_the_reviewed_plan_hash(self):
        before = self.local_branches()
        for extra in ([], ["--plan-sha256", "0" * 64]):
            done = self.cleanup("--apply", *extra)
            self.assertEqual(done.returncode, 3, done.stdout)
            self.assertEqual(self.local_branches(), before)
        self.assertEqual(self.cleanup("--apply", "--plan-sha256", "nothex").returncode, 2)
        self.assertEqual(self.cleanup("--scope", "bogus").returncode, 2)
        self.assertFalse((self.work / ".git/branch-cleanup").exists())

    def test_reviewed_apply_deletes_only_merged_local_branches_and_records_them(self):
        plan, _ = self.plan()
        remote_before = self.remote_branches()
        tips = {name: self.git("rev-parse", name) for name in ("merged-ancestor", "merged-patches")}
        done = self.cleanup("--apply", "--plan-sha256", plan)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.local_branches(), {"main", "dev", "backup/keep", "wt-branch", "unmerged"})
        self.assertEqual(self.remote_branches(), remote_before)
        records = list((self.work / ".git/branch-cleanup").glob("deleted-*.tsv"))
        self.assertEqual(len(records), 1)
        text = records[0].read_text()
        for name, tip in tips.items():
            self.assertIn(f"local\t{name}\t{tip}\t", text)
        self.assertEqual(oct((self.work / ".git/branch-cleanup").stat().st_mode & 0o777), "0o700")
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.git("branch", "restored", tips["merged-patches"])  # the recorded sha really restores the work
        self.assertIn("restored", self.local_branches())

    def test_a_moved_branch_invalidates_the_reviewed_plan(self):
        plan, _ = self.plan()
        self.git("branch", "-f", "merged-ancestor", "merged-patches")
        before = self.local_branches()
        done = self.cleanup("--apply", "--plan-sha256", plan)
        self.assertEqual(done.returncode, 3, done.stdout)
        self.assertIn("differ from the reviewed plan", done.stderr)
        self.assertEqual(self.local_branches(), before)

    def test_remote_deletion_is_a_separate_explicit_scope(self):
        local_before = self.local_branches()
        plan, out = self.plan("--scope", "remote")
        self.assertIn("scope: remote", out)
        done = self.cleanup("--apply", "--scope", "remote", "--plan-sha256", plan)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.remote_branches(), {"main", "dev", "backup/keep", "unmerged"})
        self.assertEqual(self.local_branches(), local_before)
        # a hash reviewed for the default (local) scope cannot authorize remote deletion
        local_plan, _ = self.plan()
        self.assertEqual(self.cleanup("--apply", "--scope", "both", "--plan-sha256", local_plan).returncode, 3)

    def test_remote_branch_advanced_after_review_is_not_deleted(self):
        plan, _ = self.plan("--scope", "remote")
        self.run_git(self.other, "checkout", "-q", "merged-ancestor")
        self.write(self.other, "late", "late work\n")
        self.commit(self.other, "work pushed after the review")
        self.run_git(self.other, "push", "-q", "origin", "merged-ancestor")
        done = self.cleanup("--apply", "--scope", "remote", "--plan-sha256", plan)
        self.assertEqual(done.returncode, 3, done.stdout)
        self.assertIn("merged-ancestor", self.remote_branches())

    def test_protected_branches_stay_even_when_merged(self):
        _, out = self.plan("--scope", "both")
        skipped = out.split("== SKIPPED", 1)[1]
        for name in ("dev", "backup/keep", "wt-branch"):
            self.assertIn(name, skipped)
        deletions = out.split("== NOT merged", 1)[0]
        for name in ("dev", "backup/keep", "wt-branch", "unmerged"):
            self.assertNotRegex(deletions, rf"^{re.escape(name)}\t", "protected or unmerged branch listed for deletion")

    def test_it_refuses_to_run_outside_a_repository(self):
        done = subprocess.run(["bash", str(SCRIPT), "--no-fetch"], cwd=self.tmp.name, env=self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertNotEqual(done.returncode, 0)


if __name__ == "__main__":
    unittest.main()
