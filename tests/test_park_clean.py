#!/usr/bin/env python3
"""Disposable repositories: park real work with park_task.py, then clean with park_task_clean.py."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PARK = ROOT / 'scripts/park_task.py'
CLEAN = ROOT / 'scripts/park-task-clean.sh'


class ParkClean(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='park-clean-')
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.log = self.root / 'log'
        self.log.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
        self.env.pop('SCHEDULE_SCOPE_ID', None)
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Synthetic')
        self.git('config', 'user.email', 'synthetic@example.invalid')
        for name, text in {'tracked.txt': 'one\n', 'other.txt': 'other\n', 'dir/inner.txt': 'inner\n',
                           'script.sh': '#!/bin/sh\n', '.agents/kanban/todo/K-001.md': 'card\n'}.items():
            self.put(name, text)
        (self.repo / 'script.sh').chmod(0o755)
        self.git('add', '-A')
        self.git('commit', '-qm', 'baseline')
        self.card = self.repo / '.agents/kanban/todo/K-001.md'

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args, check=True):
        return subprocess.run(['git', *args], cwd=self.repo, env=self.env, capture_output=True, text=True, check=check)

    def put(self, name, text):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def messy_tree(self):
        """Every kind of change a parked card can leave behind."""
        self.put('tracked.txt', 'one\nedited by the card\n')
        (self.repo / 'other.txt').unlink()
        self.put('new/deep/file.txt', 'fresh\n')
        self.put('new file.txt', 'with a space\n')
        (self.repo / 'link').symlink_to('tracked.txt')
        self.put('dir/inner.txt', 'staged edit\n')
        self.git('add', '--', 'dir/inner.txt')
        self.put('staged-new.txt', 'staged and new\n')
        self.git('add', '--', 'staged-new.txt')
        (self.repo / 'script.sh').chmod(0o644)
        self.put('.agents/kanban/todo/K-001.md', 'card\n## Parked\nblocked\n')

    def park(self, reason='blocker'):
        baseline = self.root / 'baseline'
        baseline.write_text('')
        done = subprocess.run(['python3', '-I', str(PARK), str(self.card), 'main', str(baseline), 'sess-1', str(self.log), reason],
                              cwd=self.repo, env=self.env, capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        return 'task/K-001'

    def clean(self, *args, extra_env=None):
        return subprocess.run(['bash', str(CLEAN), '--repo', str(self.repo), *args], cwd=self.root,
                              env={**self.env, **(extra_env or {})}, capture_output=True, text=True)

    def plan(self, branch, *args):
        done = self.clean('--branch', branch, *args)
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout)

    def apply(self, branch, plan, *extra):
        return self.clean('--branch', branch, '--apply', '--plan-sha256', plan['plan_sha256'], *extra)

    def state(self):
        files = {}
        for path in sorted(self.repo.rglob('*')):
            rel = path.relative_to(self.repo)
            if rel.parts[0] == '.git':
                continue
            if path.is_symlink():
                files[str(rel)] = ('link', os.readlink(path))
            elif path.is_file():
                files[str(rel)] = ('file', path.read_bytes(), path.stat().st_mode & 0o777)
        # index *content*: git refreshes stat data in the index file even for read-only commands
        return (self.git('rev-parse', 'HEAD').stdout, self.git('ls-files', '-s').stdout, files)

    def test_dry_run_is_read_only_and_describes_every_path(self):
        self.messy_tree()
        branch = self.park()
        before = self.state()
        plan = self.plan(branch)
        self.assertFalse(plan['applied'])
        self.assertEqual(self.state(), before)
        self.assertEqual(sorted(plan['remove']), ['link', 'new file.txt', 'new/deep/file.txt', 'staged-new.txt'])
        self.assertEqual(sorted(plan['restore']), ['.agents/kanban/todo/K-001.md', 'dir/inner.txt', 'other.txt',
                                                   'script.sh', 'tracked.txt'])
        self.assertEqual(sorted(plan['index_reset']), ['dir/inner.txt', 'staged-new.txt'])
        self.assertRegex(plan['plan_sha256'], r'^[0-9a-f]{64}$')

    def test_reviewed_apply_restores_the_checkout_and_keeps_the_snapshot(self):
        self.messy_tree()
        branch = self.park()
        tip = self.git('rev-parse', branch).stdout
        plan = self.plan(branch)
        done = self.apply(branch, plan)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue(json.loads(done.stdout)['applied'])
        self.assertEqual(self.git('status', '--porcelain', '--untracked-files=all').stdout, '')
        self.assertEqual(self.git('diff', '--cached', '--name-only').stdout, '')
        self.assertEqual((self.repo / 'tracked.txt').read_text(), 'one\n')
        self.assertTrue((self.repo / 'other.txt').exists())
        self.assertTrue(os.access(self.repo / 'script.sh', os.X_OK))
        self.assertFalse((self.repo / 'new').exists(), 'directories emptied by the removal are pruned')
        self.assertEqual(self.git('rev-parse', branch).stdout, tip)
        self.assertEqual(self.git('show', f'{branch}:new/deep/file.txt').stdout, 'fresh\n')
        self.assertEqual(self.git('show', f'{branch}:tracked.txt').stdout, 'one\nedited by the card\n')
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout, self.git('rev-parse', f'{branch}^').stdout)

    def test_hash_is_required_and_bound_to_the_reviewed_state(self):
        self.messy_tree()
        branch = self.park()
        plan = self.plan(branch)
        before = self.state()
        for args in ([], ['--plan-sha256', '0' * 64], ['--plan-sha256', 'not-a-hash']):
            done = self.clean('--branch', branch, '--apply', *args)
            self.assertEqual(done.returncode, 1, done.stdout)
            self.assertEqual(self.state(), before)
        bound = dict(plan, plan_sha256='f' * 64)
        self.assertEqual(self.apply(branch, bound).returncode, 1)
        self.assertEqual(self.state(), before)

    def test_edits_made_after_parking_are_never_discarded(self):
        self.messy_tree()
        branch = self.park()
        plan = self.plan(branch)
        self.put('tracked.txt', 'one\nedited by the card\nand again by the owner\n')
        before = self.state()
        for args in ([], ['--apply', '--plan-sha256', plan['plan_sha256']]):
            done = self.clean('--branch', branch, *args)
            self.assertEqual(done.returncode, 1, done.stdout)
            self.assertIn('differs from the snapshot', done.stderr)
        self.assertEqual(self.state(), before)

    def test_unrelated_dirty_files_are_left_alone_and_listed(self):
        self.messy_tree()
        branch = self.park()
        self.put('later-note.txt', 'written after parking\n')
        plan = self.plan(branch)
        self.assertEqual(plan['left_untouched'], ['later-note.txt'])
        self.assertEqual(self.apply(branch, plan).returncode, 0)
        self.assertEqual((self.repo / 'later-note.txt').read_text(), 'written after parking\n')
        self.assertEqual(self.git('status', '--porcelain', '--untracked-files=all').stdout, '?? later-note.txt\n')

    def test_a_third_staged_version_is_refused(self):
        self.messy_tree()
        branch = self.park()
        self.put('tracked.txt', 'one\nstaged differently\n')
        self.git('add', '--', 'tracked.txt')
        self.put('tracked.txt', 'one\nedited by the card\n')
        before = self.state()
        done = self.clean('--branch', branch)
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertIn('third version of tracked.txt', done.stderr)
        self.assertEqual(self.state(), before)

    def test_refuses_when_head_moved_or_branch_is_not_a_park_snapshot_or_in_scheduled_run(self):
        self.messy_tree()
        branch = self.park()
        before = self.state()
        scheduled = self.clean('--branch', branch, extra_env={'SCHEDULE_SCOPE_ID': 'a' * 64})
        self.assertEqual(scheduled.returncode, 1)
        self.assertIn('scheduled run', scheduled.stderr)
        self.git('branch', 'task/fake', 'HEAD')
        self.git('branch', 'feature/x', branch)
        # right parent and right content, but not made by park-task.sh
        impostor = self.git('commit-tree', f'{branch}^{{tree}}', '-p', 'HEAD', '-m', 'ordinary commit').stdout.strip()
        self.git('branch', 'task/impostor', impostor)
        self.assertIn('not a park snapshot', self.clean('--branch', 'task/impostor').stderr)
        for name in ('task/fake', 'feature/x', 'task/missing', 'task/../x', 'task/impostor'):
            done = self.clean('--branch', name)
            self.assertEqual(done.returncode, 1, (name, done.stdout))
        self.assertEqual(self.state(), before)
        self.git('stash', '-q', '--include-untracked')   # make the commit possible, then move HEAD
        self.git('commit', '-q', '--allow-empty', '-m', 'owner moved on')
        self.git('stash', 'pop', '-q', check=False)
        done = self.clean('--branch', branch)
        self.assertEqual(done.returncode, 1)
        self.assertIn('HEAD is not the commit', done.stderr)

    def test_record_must_agree_with_the_branch(self):
        self.messy_tree()
        branch = self.park()
        record = self.log / '.parked/K-001'
        self.assertEqual(self.plan(branch, '--record', str(record))['branch'], branch)
        stale = self.root / 'stale-record'
        stale.write_text('branch=%s\ncommit=%s\n' % (branch, '1' * 40))
        self.assertIn('no longer points', self.clean('--record', str(stale)).stderr)
        mismatch = self.root / 'other-record'
        mismatch.write_text('branch=task/other\ncommit=%s\n' % self.git('rev-parse', branch).stdout.strip())
        self.assertIn('disagrees', self.clean('--branch', branch, '--record', str(mismatch)).stderr)
        empty = self.root / 'empty-record'
        empty.write_text('branch=none\ncommit=none\n')
        self.assertIn('nothing to clean', self.clean('--record', str(empty)).stderr)

    def test_second_apply_and_concurrent_cleanup_are_refused(self):
        self.messy_tree()
        branch = self.park()
        plan = self.plan(branch)
        fd = os.open(self.repo / '.git/park-clean.lock', os.O_RDWR | os.O_CREAT, 0o600)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX)
        before = self.state()
        done = self.apply(branch, plan)
        self.assertEqual(done.returncode, 1)
        self.assertIn('another cleanup', done.stderr)
        self.assertEqual(self.state(), before)
        fcntl.flock(fd, fcntl.LOCK_UN)
        self.assertEqual(self.apply(branch, plan).returncode, 0)
        again = self.apply(branch, plan)
        self.assertEqual(again.returncode, 1)
        self.assertIn('differs from the snapshot', again.stderr)


if __name__ == '__main__':
    unittest.main()
