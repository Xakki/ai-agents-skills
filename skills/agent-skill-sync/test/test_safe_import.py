#!/usr/bin/env python3
"""Only synthetic local Git repositories; no remote network or plugin installation."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
class SafeImport(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='safe-skill-import-'); self.root=Path(self.temp.name);self.home=self.root/'home';self.home.mkdir();self.project=self.root/'project';self.project.mkdir();self.cache=self.root/'cache';self.clone=self.cache/'repos/demo';self.clone.mkdir(parents=True);self.catalog=self.cache/'catalog.tsv';self.sources=self.root/'sources.tsv'
  self.env=dict(os.environ,HOME=str(self.home));self.git(self.project,'init','-q');self.git(self.project,'config','user.name','Test');self.git(self.project,'config','user.email','test@example.invalid')
  self.user=self.project/'user.txt';self.user.write_text('baseline');self.git(self.project,'add','--','user.txt');self.git(self.project,'commit','-qm','fixture');self.user.write_text('user staged');self.git(self.project,'add','--','user.txt')
  self.git(self.clone,'init','-q');self.git(self.clone,'config','user.name','Test');self.git(self.clone,'config','user.email','test@example.invalid');self.git(self.clone,'remote','add','origin','https://example.invalid/repo.git')
  self.src=self.clone/'skills/example';self.src.mkdir(parents=True);(self.src/'SKILL.md').write_text('---\nname: example\ndescription: Synthetic example.\n---\nBody\n');(self.src/'asset.txt').write_text('tracked asset');self.git(self.clone,'add','--','skills/example');self.git(self.clone,'commit','-qm','source')
  self.sources.write_text('demo\thttps://example.invalid/repo.git\tskills-repo\n');self.catalog.write_text('source\tskill\tkind\tlocation\tdescription\ndemo\texample\tlocal\tskills/example\tsynthetic\n')
 def tearDown(self):self.temp.cleanup()
 def git(self,repo,*args,check=True):return subprocess.run(['git','-C',str(repo),*args],check=check,capture_output=True,text=True,env=self.env)
 def index(self):return (self.project/'.git/index').read_bytes()
 def call(self,script,*args):return subprocess.run(['bash',str(ROOT/script),*args],cwd=self.project,env=self.env,capture_output=True,text=True,timeout=15)
 def import_args(self):return ['demo','example','--project',str(self.project),'--cache',str(self.cache),'--catalog',str(self.catalog),'--sources',str(self.sources)]
 def test_import_uses_tracked_head_without_staging_or_manifest(self):
  (self.src/'.hidden-user-file').write_text('ignored user artifact');(self.clone/'.git/info/exclude').write_text('.hidden-user-file\n')
  root=self.project/'.agents/skills';root.mkdir(parents=True);manifest=root/'.imported.tsv';manifest.write_text('unowned manifest\n');idx=self.index()
  p=self.call('import-skill.sh',*self.import_args());self.assertEqual(p.returncode,0,p.stderr)
  dest=root/'example';self.assertEqual((dest/'asset.txt').read_text(),'tracked asset');self.assertFalse((dest/'.hidden-user-file').exists());self.assertEqual(manifest.read_text(),'unowned manifest\n');self.assertEqual(self.index(),idx)
 def test_force_existing_hidden_and_untracked_refused(self):
  dest=self.project/'.agents/skills/example';dest.mkdir(parents=True);(dest/'.private').write_text('keep');(dest/'SKILL.md').write_text('own skill');idx=self.index()
  for extra in ([],['--force']):
   p=self.call('import-skill.sh',*self.import_args(),*extra);self.assertNotEqual(p.returncode,0);self.assertEqual((dest/'.private').read_text(),'keep');self.assertEqual((dest/'SKILL.md').read_text(),'own skill');self.assertEqual(self.index(),idx)
 def test_mismatch_ambiguous_and_external_are_refused(self):
  self.git(self.clone,'remote','set-url','origin','https://other.invalid/repo.git');p=self.call('import-skill.sh',*self.import_args());self.assertNotEqual(p.returncode,0);self.assertIn('origin',p.stderr)
  self.git(self.clone,'remote','set-url','origin','https://example.invalid/repo.git');self.catalog.write_text(self.catalog.read_text()+'demo\texample\tlocal\tskills/example\tx\n');p=self.call('import-skill.sh',*self.import_args());self.assertNotEqual(p.returncode,0);self.assertIn('ambiguous',p.stderr)
  self.catalog.write_text('demo\texample\texternal\thttps://example.invalid/repo\tx\n');p=self.call('import-skill.sh',*self.import_args());self.assertNotEqual(p.returncode,0);self.assertIn('disabled',p.stderr)
 def test_destination_symlink_and_escape_are_refused(self):
  outside=self.root/'outside';outside.mkdir();(self.project/'.agents').symlink_to(outside,target_is_directory=True);p=self.call('import-skill.sh',*self.import_args());self.assertNotEqual(p.returncode,0);self.assertEqual(list(outside.iterdir()),[])
  (self.project/'.agents').unlink();p=self.call('import-skill.sh',*self.import_args(),'--dest',str(outside));self.assertNotEqual(p.returncode,0);self.assertEqual(list(outside.iterdir()),[])
 def test_traversal_and_tracked_symlink_are_refused(self):
  self.catalog.write_text('demo\texample\tlocal\t../other\tx\n');p=self.call('import-skill.sh',*self.import_args());self.assertNotEqual(p.returncode,0)
  self.catalog.write_text('demo\texample\tlocal\tskills/example\tx\n');(self.src/'alias').symlink_to('asset.txt');self.git(self.clone,'add','--','skills/example/alias');self.git(self.clone,'commit','-qm','symlink');p=self.call('import-skill.sh',*self.import_args());self.assertNotEqual(p.returncode,0);self.assertIn('unsafe',p.stderr)
 def test_catalog_failure_preserves_existing_catalog_and_untracked_cache(self):
  keep=self.catalog.read_bytes();p=self.call('build-catalog.sh','--cache',str(self.cache),'--sources',str(self.root/'missing.tsv'),'--out',str(self.catalog));self.assertNotEqual(p.returncode,0);self.assertEqual(self.catalog.read_bytes(),keep)
  (self.src/'asset.txt').write_text('dirty source');idx=(self.clone/'.git/index').read_bytes();p=self.call('build-catalog.sh','--refresh','--cache',str(self.cache),'--sources',str(self.sources),'--out',str(self.catalog));self.assertNotEqual(p.returncode,0);self.assertEqual((self.src/'asset.txt').read_text(),'dirty source');self.assertEqual((self.clone/'.git/index').read_bytes(),idx);self.assertEqual(self.catalog.read_bytes(),keep)
 def test_refresh_fast_forwards_clean_local_fixture_without_network(self):
  remote=self.root/'upstream.git';self.git(self.root,'clone','--bare',str(self.clone),str(remote))
  self.git(self.clone,'remote','set-url','origin',remote.as_uri());self.sources.write_text('demo\t'+remote.as_uri()+'\tskills-repo\n')
  producer=self.root/'producer';self.git(self.root,'clone',str(remote),str(producer));self.git(producer,'config','user.name','Test');self.git(producer,'config','user.email','test@example.invalid')
  (producer/'skills/example/asset.txt').write_text('upstream');self.git(producer,'add','--','skills/example/asset.txt');self.git(producer,'commit','-qm','update');self.git(producer,'push','-q','origin','HEAD')
  p=self.call('build-catalog.sh','--refresh','--cache',str(self.cache),'--sources',str(self.sources),'--out',str(self.catalog));self.assertEqual(p.returncode,0,p.stderr);self.assertEqual((self.src/'asset.txt').read_text(),'upstream');self.assertIn('demo\texample\tlocal',self.catalog.read_text())
 def test_refresh_divergence_fails_without_reset_or_catalog_loss(self):
  remote=self.root/'upstream.git';self.git(self.root,'clone','--bare',str(self.clone),str(remote));self.git(self.clone,'remote','set-url','origin',remote.as_uri());self.sources.write_text('demo\t'+remote.as_uri()+'\tskills-repo\n')
  producer=self.root/'producer';self.git(self.root,'clone',str(remote),str(producer));self.git(producer,'config','user.name','Test');self.git(producer,'config','user.email','test@example.invalid')
  (producer/'skills/example/asset.txt').write_text('remote');self.git(producer,'add','--','skills/example/asset.txt');self.git(producer,'commit','-qm','remote');self.git(producer,'push','-q','origin','HEAD')
  (self.src/'asset.txt').write_text('local');self.git(self.clone,'add','--','skills/example/asset.txt');self.git(self.clone,'commit','-qm','local')
  head=self.git(self.clone,'rev-parse','HEAD').stdout;index=(self.clone/'.git/index').read_bytes();before=self.catalog.read_bytes()
  p=self.call('build-catalog.sh','--refresh','--cache',str(self.cache),'--sources',str(self.sources),'--out',str(self.catalog))
  self.assertNotEqual(p.returncode,0);self.assertEqual(self.git(self.clone,'rev-parse','HEAD').stdout,head);self.assertEqual((self.clone/'.git/index').read_bytes(),index);self.assertEqual((self.src/'asset.txt').read_text(),'local');self.assertEqual(self.catalog.read_bytes(),before)
 def test_preview_and_force_do_not_change_existing_skill_or_manifest(self):
  root=self.project/'.agents/skills';dest=root/'example';dest.mkdir(parents=True);(dest/'SKILL.md').write_text('user data');(dest/'.private').write_text('private');manifest=root/'.imported.tsv';manifest.write_text('example\tdemo\turl\tskills/example\tabc\t2020-01-01\n');idx=self.index();before=manifest.read_bytes()
  args=['--project',str(self.project),'--cache',str(self.cache),'--catalog',str(self.catalog),'--sources',str(self.sources)]
  p=self.call('update-imported.sh',*args);self.assertEqual(p.returncode,4,p.stderr);p=self.call('update-imported.sh',*args,'--force');self.assertNotEqual(p.returncode,0);self.assertEqual((dest/'.private').read_text(),'private');self.assertEqual((dest/'SKILL.md').read_text(),'user data');self.assertEqual(manifest.read_bytes(),before);self.assertEqual(self.index(),idx)
 def test_root_skill_archive_supported(self):
  root_md=self.clone/'SKILL.md';root_md.write_text('---\nname: example\ndescription: Example.\n---\n');self.git(self.clone,'add','--','SKILL.md');self.git(self.clone,'commit','-qm','root skill');self.catalog.write_text('demo\texample\tlocal\t.\tx\n')
  p=self.call('import-skill.sh',*self.import_args());self.assertEqual(p.returncode,0,p.stderr);self.assertTrue((self.project/'.agents/skills/example/SKILL.md').is_file());self.assertFalse((self.project/'.agents/skills/example/.git').exists())

if __name__=='__main__':unittest.main()
