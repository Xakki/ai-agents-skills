"""Synthetic tests for receipts and reviewed updates; sources are throw-away local Git repositories."""
import fcntl
import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GIT = ["git", "-c", "user.email=t@t", "-c", "user.name=t", "-c", "init.defaultBranch=main"]


def run(*cmd, cwd=None, check=True):
    return subprocess.run(list(cmd), cwd=cwd, capture_output=True, text=True, check=check)


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.tmp)]))
        self.src = self.tmp / "src"
        (self.src / "react" / "refs").mkdir(parents=True)
        self.write_upstream("react/SKILL.md", "---\nname: react\ndescription: React.\n---\n# v1\n")
        self.write_upstream("react/refs/a.md", "ref a\n")
        run(*GIT, "init", "-q", str(self.src))
        self.commit("init")
        self.sources = self.tmp / "sources.tsv"
        self.sources.write_text("mysrc\tfile://%s\tskills-repo\n" % self.src)
        self.cache, self.catalog = self.tmp / "cache", self.tmp / "catalog.tsv"
        self.refresh_cache()
        self.proj = self.tmp / "proj"
        self.proj.mkdir()
        run(*GIT, "init", "-q", str(self.proj))
        self.user_file = self.proj / "user.txt"
        self.user_file.write_text("staged by the user\n")
        run("git", "add", "--", "user.txt", cwd=self.proj)
        self.index_before = (self.proj / ".git/index").read_bytes()
        self.skill = self.proj / ".agents/skills/react"
        r = run("bash", str(ROOT / "import-skill.sh"), "mysrc", "react", "--project", str(self.proj), "--cache", str(self.cache),
                "--catalog", str(self.catalog), "--sources", str(self.sources))
        self.assertIn("Provenance receipt", r.stdout)

    def write_upstream(self, rel, text, mode=0o644):
        p = self.src / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        p.chmod(mode)

    def commit(self, msg):
        run(*GIT, "add", "-A", cwd=self.src)
        run(*GIT, "commit", "-qm", msg, cwd=self.src)

    def refresh_cache(self):
        run("bash", str(ROOT / "build-catalog.sh"), "--refresh", "--cache", str(self.cache), "--sources", str(self.sources), "--out", str(self.catalog))

    def update(self, *extra, check=False):
        return run("bash", str(ROOT / "update-skill.sh"), "mysrc", "react", "--project", str(self.proj), "--cache", str(self.cache),
                   "--catalog", str(self.catalog), "--sources", str(self.sources), *extra, check=check)

    def plan(self):
        r = self.update()
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def apply(self, plan, *extra):
        return self.update("--apply", "--plan-sha256", plan["plan_sha256"], *extra)

    def tree(self, root):
        return {str(p.relative_to(root)): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()}

    def upstream_v2(self):
        self.write_upstream("react/SKILL.md", "---\nname: react\ndescription: React.\n---\n# v2\n")
        self.write_upstream("react/refs/b.md", "ref b\n")
        (self.src / "react/refs/a.md").unlink()
        self.commit("v2")
        self.refresh_cache()


class ReceiptAndPlanTests(Fixture):
    def test_import_records_a_receipt_with_hashes(self):
        receipt = json.loads((self.skill / ".skill-import.json").read_text())
        head = run("git", "rev-parse", "HEAD", cwd=self.src).stdout.strip()
        self.assertEqual((receipt["source"], receipt["skill"], receipt["commit"], receipt["location"]), ("mysrc", "react", head, "react"))
        self.assertEqual(receipt["files"]["refs/a.md"][0], hashlib.sha256(b"ref a\n").hexdigest())
        self.assertNotIn(".skill-import.json", receipt["files"])

    def test_untouched_copy_is_up_to_date_and_apply_is_refused(self):
        plan = self.plan()
        self.assertTrue(plan["up_to_date"])
        self.assertEqual(self.apply(plan).returncode, 3)

    def test_plan_is_read_only(self):
        self.upstream_v2()
        before = self.tree(self.skill)
        self.plan()
        self.assertEqual(self.tree(self.skill), before)
        self.assertFalse((self.proj / ".agents/.skill-import-backups").exists())


class ApplyTests(Fixture):
    def test_clean_copy_updates_with_backup_and_untouched_index(self):
        old = self.tree(self.skill)
        self.upstream_v2()
        plan = self.plan()
        self.assertFalse(plan["discard_local_required"])
        self.assertEqual(plan["upstream_changes"], {"add": ["refs/b.md"], "change": ["SKILL.md"], "remove": ["refs/a.md"]})
        r = self.apply(plan)
        self.assertEqual(r.returncode, 0, r.stderr)
        result = json.loads(r.stdout)
        new = self.tree(self.skill)
        self.assertIn(b"# v2", new["SKILL.md"])
        self.assertNotIn("refs/a.md", new)
        self.assertEqual(self.tree(Path(result["backup"])), old)
        self.assertEqual(json.loads(new[".skill-import.json"])["commit"], result["commit"])
        self.assertEqual((self.proj / ".git/index").read_bytes(), self.index_before)
        self.assertTrue(self.plan()["up_to_date"])

    def test_local_modification_blocks_until_discard_is_explicit(self):
        (self.skill / "SKILL.md").write_text("---\nname: react\ndescription: edited.\n---\nlocal edit\n")
        (self.skill / ".hidden").write_text("mine\n")
        self.upstream_v2()
        plan = self.plan()
        self.assertTrue(plan["discard_local_required"])
        self.assertEqual(plan["local_changes"]["modified"], ["SKILL.md"])
        self.assertEqual(plan["local_changes"]["added"], [".hidden"])
        before = self.tree(self.skill)
        r = self.apply(plan)
        self.assertEqual(r.returncode, 3)
        self.assertIn("--discard-local", r.stderr)
        self.assertEqual(self.tree(self.skill), before)
        r = self.apply(plan, "--discard-local")
        self.assertEqual(r.returncode, 0, r.stderr)
        backup = Path(json.loads(r.stdout)["backup"])
        self.assertEqual((backup / ".hidden").read_text(), "mine\n")
        self.assertIn("local edit", (backup / "SKILL.md").read_text())
        self.assertFalse((self.skill / ".hidden").exists())

    def test_hash_is_required_and_bound_to_the_reviewed_state(self):
        self.upstream_v2()
        plan = self.plan()
        for extra in ([], ["--plan-sha256", "0" * 64]):
            r = self.update("--apply", *extra)
            self.assertEqual(r.returncode, 3)
        (self.skill / "refs" / "a.md").write_text("changed after review\n")
        before = self.tree(self.skill)
        r = self.apply(plan, "--discard-local")
        self.assertEqual(r.returncode, 3)
        self.assertIn("reviewed plan", r.stderr)
        self.assertEqual(self.tree(self.skill), before)
        self.assertFalse((self.proj / ".agents/.skill-import-backups").exists())

    def test_unreceipted_copy_needs_discard_and_is_fully_backed_up(self):
        (self.skill / ".skill-import.json").unlink()
        self.upstream_v2()
        plan = self.plan()
        self.assertFalse(plan["has_receipt"])
        self.assertTrue(plan["discard_local_required"])
        self.assertEqual(self.apply(plan).returncode, 3)
        r = self.apply(plan, "--discard-local")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((Path(json.loads(r.stdout)["backup"]) / "refs/a.md").exists())

    def test_exec_bit_is_preserved_and_second_update_gets_its_own_backup(self):
        self.write_upstream("react/run.sh", "#!/bin/sh\n", 0o755)
        self.commit("script")
        self.refresh_cache()
        first = json.loads(self.apply(self.plan()).stdout)
        self.assertTrue(os.access(self.skill / "run.sh", os.X_OK))
        self.write_upstream("react/refs/a.md", "ref a v3\n")
        self.commit("v3")
        self.refresh_cache()
        second = json.loads(self.apply(self.plan()).stdout)
        self.assertNotEqual(first["backup"], second["backup"])
        self.assertTrue(Path(first["backup"]).is_dir() and Path(second["backup"]).is_dir())

    def test_concurrent_operation_is_refused(self):
        self.upstream_v2()
        plan = self.plan()
        fd = os.open(self.proj / ".agents/skills/.skill-import.lock", os.O_RDWR | os.O_CREAT, 0o600)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX)
        before = self.tree(self.skill)
        r = self.apply(plan)
        self.assertEqual(r.returncode, 3)
        self.assertIn("lock", r.stderr)
        self.assertEqual(self.tree(self.skill), before)


class RefusalTests(Fixture):
    def test_symlink_inside_copy_dirty_cache_and_origin_mismatch_are_refused(self):
        self.upstream_v2()
        (self.skill / "link").symlink_to("SKILL.md")
        self.assertEqual(self.update().returncode, 3)
        (self.skill / "link").unlink()
        clone = self.cache / "repos/mysrc"
        (clone / "react/SKILL.md").write_text("dirty cache\n")
        self.assertIn("modified tracked files", self.update().stderr)
        run("git", "checkout", "--", "react/SKILL.md", cwd=clone)
        self.sources.write_text("mysrc\tfile://%s\tskills-repo\n" % (self.tmp / "other"))
        self.assertIn("origin does not match", self.update().stderr)

    def test_symlinked_destination_and_missing_skill_are_refused(self):
        real = self.proj / ".agents/real-skills"
        (self.proj / ".agents/skills").rename(real)
        (self.proj / ".agents/skills").symlink_to(real, target_is_directory=True)
        self.assertIn("symlink", self.update().stderr)
        (self.proj / ".agents/skills").unlink()
        real.rename(self.proj / ".agents/skills")
        subprocess.run(["rm", "-rf", str(self.skill)])
        self.assertIn("use import-skill.sh", self.update().stderr)

    def test_force_flags_and_bad_names_stay_refused(self):
        r = run("bash", str(ROOT / "import-skill.sh"), "mysrc", "react", "--force", check=False)
        self.assertEqual(r.returncode, 3)
        self.assertIn("update-skill.sh", r.stderr)
        r = run("bash", str(ROOT / "update-skill.sh"), "my/src", "react", "--project", str(self.proj), check=False)
        self.assertEqual(r.returncode, 3)


if __name__ == "__main__":
    unittest.main()
