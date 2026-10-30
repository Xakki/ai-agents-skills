#!/usr/bin/env python3
"""Exercise git-path-run against disposable repositories and outside repositories."""
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'git-path-run.sh'


class GitMoveTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='git-move-test-')
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / 'repo'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        (self.repo / 'tracked').write_text('original')
        (self.repo / 'foreign').write_text('old')
        self.git('add', 'tracked', 'foreign')
        self.git('commit', '-qm', 'fixture')
        (self.repo / 'foreign').write_text('staged foreign')
        self.git('add', 'foreign')
        (self.repo / 'foreign').write_text('working foreign')

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.repo, check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

    def move(self, *args, cwd=None):
        return subprocess.run(['bash', str(HELPER), *args], cwd=cwd or self.repo,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def index_foreign(self):
        return self.git('show', ':foreign')

    def test_tracked_move_stages_rename_and_preserves_foreign_index(self):
        before = self.index_foreign()
        self.assertEqual(self.move('tracked', 'next/tracked').returncode, 0)
        self.assertEqual(self.git('show', ':next/tracked'), b'original')
        self.assertEqual(self.index_foreign(), before)
        self.assertEqual((self.repo / 'foreign').read_text(), 'working foreign')

    def test_untracked_move_and_outside_repo_move(self):
        (self.repo / 'local').write_text('local')
        before = self.git('diff', '--cached', '--name-status')
        self.assertEqual(self.move('local', 'new/local').returncode, 0)
        self.assertEqual((self.repo / 'new/local').read_text(), 'local')
        self.assertEqual(self.git('diff', '--cached', '--name-status'), before)
        outside = Path(self.tmp.name) / 'outside'
        outside.mkdir()
        (outside / 'a').write_text('a')
        self.assertEqual(self.move('a', 'b', cwd=outside).returncode, 0)
        self.assertEqual((outside / 'b').read_text(), 'a')

    def test_collisions_are_rejected_for_both_tracked_and_untracked(self):
        (self.repo / 'local').write_text('local')
        (self.repo / 'dest').write_text('keep')
        before = self.git('diff', '--cached', '--name-status')
        for source in ('tracked', 'local'):
            self.assertNotEqual(self.move(source, 'dest').returncode, 0)
            self.assertTrue((self.repo / source).exists())
            self.assertEqual((self.repo / 'dest').read_text(), 'keep')
            self.assertEqual(self.git('diff', '--cached', '--name-status'), before)

    def test_mixed_directories_rejected_for_move_and_remove(self):
        tree = self.repo / 'tree'
        tree.mkdir()
        (tree / 'tracked').write_text('tracked')
        self.git('add', 'tree/tracked')
        (tree / 'local').write_text('local')
        before = self.git('diff', '--cached', '--name-status')
        self.assertNotEqual(self.move('tree', 'new-tree').returncode, 0)
        self.assertNotEqual(self.move('--rm', '--recursive', 'tree').returncode, 0)
        self.assertTrue((tree / 'tracked').exists())
        self.assertTrue((tree / 'local').exists())
        self.assertEqual(self.git('diff', '--cached', '--name-status'), before)

    def test_tracked_directory_moves_if_all_contents_tracked(self):
        tree = self.repo / 'tree'
        tree.mkdir()
        (tree / 'a').write_text('a')
        self.git('add', 'tree/a')
        before = self.index_foreign()
        self.assertEqual(self.move('tree', 'new-tree').returncode, 0)
        self.assertEqual(self.git('show', ':new-tree/a'), b'a')
        self.assertEqual(self.index_foreign(), before)

    def test_tracked_directory_remove_and_foreign_index(self):
        tree = self.repo / 'tree'
        tree.mkdir()
        (tree / 'a').write_text('a')
        self.git('add', 'tree/a')
        self.git('commit', '-qm', 'add tree', '--', 'tree/a')
        before = self.index_foreign()
        self.assertEqual(self.move('--rm', 'tree').returncode, 0)
        self.assertFalse((tree / 'a').exists())
        self.assertEqual(self.index_foreign(), before)

    def test_ignored_descendant_and_dangling_destination_are_protected(self):
        tree = self.repo / 'tree'
        tree.mkdir()
        (tree / 'a').write_text('a')
        self.git('add', 'tree/a')
        (self.repo / '.gitignore').write_text('tree/ignored\n')
        (tree / 'ignored').write_text('private local state')
        self.assertNotEqual(self.move('tree', 'new-tree').returncode, 0)
        self.assertEqual((tree / 'ignored').read_text(), 'private local state')
        (self.repo / 'link').symlink_to('missing')
        self.assertNotEqual(self.move('tracked', 'link').returncode, 0)
        self.assertTrue((self.repo / 'link').is_symlink())

    def test_explicit_recursive_removal_and_batch_preflight(self):
        (self.repo / 'scratch').mkdir()
        (self.repo / 'scratch/data').write_text('data')
        (self.repo / 'local').write_text('local')
        self.assertNotEqual(self.move('--rm', 'local', 'scratch').returncode, 0)
        self.assertTrue((self.repo / 'local').exists())
        self.assertTrue((self.repo / 'scratch/data').exists())
        self.assertEqual(self.move('--rm', '--recursive', 'scratch').returncode, 0)
        self.assertFalse((self.repo / 'scratch').exists())
        before = self.index_foreign()
        self.assertEqual(self.move('--rm', 'tracked').returncode, 0)
        self.assertFalse((self.repo / 'tracked').exists())
        self.assertEqual(self.index_foreign(), before)

    def test_modified_tracked_file_cannot_be_deleted(self):
        (self.repo / 'tracked').write_text('uncommitted')
        before = self.git('diff', '--cached', '--name-status')
        self.assertNotEqual(self.move('--rm', 'tracked').returncode, 0)
        self.assertEqual((self.repo / 'tracked').read_text(), 'uncommitted')
        self.assertEqual(self.git('diff', '--cached', '--name-status'), before)

    def test_overlapping_batch_paths_and_cwd_removal_are_rejected(self):
        (self.repo / 'scratch').mkdir()
        (self.repo / 'scratch/data').write_text('data')
        self.assertNotEqual(self.move('--rm', '--recursive', 'scratch', 'scratch/data').returncode, 0)
        self.assertNotEqual(self.move('--rm', '--recursive', '.').returncode, 0)
        self.assertTrue((self.repo / 'scratch/data').exists())

    def test_intermediate_symlink_cannot_bypass_cwd_or_overlap_guard(self):
        (self.repo / 'alias').symlink_to(self.tmp.name, target_is_directory=True)
        marker = self.repo / 'marker'
        marker.write_text('preserve')
        self.assertNotEqual(self.move('--rm', '--recursive', 'alias/repo').returncode, 0)
        self.assertEqual(marker.read_text(), 'preserve')
        (self.repo / 'scratch').mkdir()
        (self.repo / 'scratch/data').write_text('preserve')
        self.assertNotEqual(self.move('--rm', '--recursive', 'scratch', 'alias/repo/scratch').returncode, 0)
        self.assertEqual((self.repo / 'scratch/data').read_text(), 'preserve')


if __name__ == '__main__':
    unittest.main()
