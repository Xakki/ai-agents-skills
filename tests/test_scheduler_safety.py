#!/usr/bin/env python3
"""Regression tests use disposable repositories and mock every scheduler/agent executable."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'scripts'

class SchedulerSafety(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='scheduler-safety-')
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'; self.repo.mkdir()
        self.home = self.root / 'home'; self.home.mkdir()
        self.bin = self.root / 'bin'; self.bin.mkdir()
        self.record = self.root / 'record'
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin)+':'+os.environ['PATH'], TEST_RECORD=str(self.record), TEST_REPO=str(self.repo))
        self.git('init', '-q'); self.git('config','user.name','Synthetic'); self.git('config','user.email','synthetic@example.invalid')
        self.todo = self.repo / '.agents/kanban/todo'; self.todo.mkdir(parents=True)
        self.card = self.todo / 'K-001.md'; self.card.write_text('card\n')
        self.card2 = self.todo / 'K-002.md'; self.card2.write_text('another\n')
        self.foreign = self.repo / 'foreign.txt'; self.foreign.write_text('original\n')
        self.git('add','--','.agents/kanban/todo/K-001.md','.agents/kanban/todo/K-002.md','foreign.txt'); self.git('commit','-qm','baseline')
        self.scope = self.run_script('create-task-scope.sh','--repo',str(self.repo),'--approved','--approval-source','explicit-user','--card',str(self.card),'--card',str(self.card2),check=True).stdout.strip().split('=',1)[1]
        self.mock('at', 'echo at >> "$TEST_RECORD"; exit 1')
        self.mock('atq', 'echo atq >> "$TEST_RECORD"; exit 0')
        self.mock('atrm', 'echo atrm >> "$TEST_RECORD"; exit 1')
        self.mock('systemctl', 'exit 0')
        self.mock('tmux', 'echo tmux "$@" >> "$TEST_RECORD"; exit 0')
        self.mock('claude', 'echo invoked >> "$TEST_RECORD"; printf "%s\\n" "$@" >> "$TEST_RECORD"; exit 0')

    def tearDown(self): self.temp.cleanup()
    def git(self,*args,check=True):
        return subprocess.run(['git',*args],cwd=self.repo,env=self.env,capture_output=True,text=True,check=check)
    def mock(self,name,script):
        p=self.bin/name; p.write_text('#!/usr/bin/env bash\nset -eu\n'+script+'\n'); p.chmod(0o755)
    def run_script(self,name,*args,check=False,extra_env=None):
        env=dict(self.env,**(extra_env or {}))
        return subprocess.run(['bash',str(SCRIPTS/name),*args],cwd=self.repo,env=env,input='\n',capture_output=True,text=True,timeout=20,check=check)
    def head(self): return self.git('rev-parse','HEAD').stdout.strip()
    def index(self): return (self.repo/'.git/index').read_bytes()
    def records(self): return self.record.read_text() if self.record.exists() else ''

    def test_preexisting_staged_work_blocks_inner_and_outer(self):
        self.foreign.write_text('unrelated staged bytes\n');self.git('add','--','foreign.txt')
        original_index=self.index(); before=self.head()
        for script in ('run-claude-task.sh','run-claude-task-inner.sh'):
            with self.subTest(script=script):
                result=self.run_script(script,str(self.card),self.scope)
                self.assertNotEqual(result.returncode,0); self.assertIn('staged',result.stderr)
                self.assertEqual(self.index(),original_index);self.assertEqual(self.head(),before)
        self.assertEqual(self.records(),'')

    def test_inner_does_not_commit_or_cancel_after_fake_agent_stages_foreign_content(self):
        self.mock('claude', 'echo invoked >> "$TEST_RECORD"; printf "%s\\n" "$@" >> "$TEST_RECORD"; printf "new\\n" >> "$TEST_REPO/foreign.txt"; git -C "$TEST_REPO" add -- foreign.txt; exit 0')
        before=self.head();result=self.run_script('run-claude-task-inner.sh',str(self.card),self.scope)
        self.assertNotEqual(result.returncode,0);self.assertEqual(self.head(),before)
        self.assertEqual(self.git('diff','--cached','--name-only').stdout.strip(),'foreign.txt')
        self.assertNotIn('--dangerously-skip-permissions',self.records());self.assertNotIn('atrm',self.records())
        self.assertIn('automatic staging and commit disabled',result.stdout)

    def test_nonzero_agent_exit_cannot_become_success_from_a_stale_marker(self):
        self.mock('claude', '''echo invoked >> "$TEST_RECORD"
while [ "$#" -gt 0 ]; do if [ "$1" = --session-id ]; then sid="$2"; shift 2; else shift; fi; done
encoded="$(printf '%s' "$TEST_REPO" | tr '/' '-')"
mkdir -p "$HOME/.claude/projects/$encoded"
printf '%s\\n' 'AUTO-RUN-RESULT: ok:' > "$HOME/.claude/projects/$encoded/$sid.jsonl"
exit 5''')
        result=self.run_script('run-claude-task-inner.sh',str(self.card),self.scope)
        self.assertNotEqual(result.returncode,0);self.assertIn('result=unknown',result.stdout); self.assertNotIn('atrm',self.records())

    def test_clean_outer_uses_configured_tmux_without_starting_it(self):
        result=self.run_script('run-claude-task.sh',str(self.card),self.scope,extra_env={'SCHEDULE_TMUX_SESSION':'test-session','SCHEDULE_TMUX_SOCKET':str(self.root/'tmux.sock')})
        self.assertEqual(result.returncode,0,result.stderr); self.assertIn('tmux -S '+str(self.root/'tmux.sock'),self.records());self.assertNotIn('invoked',self.records())

    # --- parking: snapshot to a side branch, never touching branch, index or worktree ---
    def park_args(self, reason='blocker', card=None, base=None, baseline=None):
        base = base or self.git('branch', '--show-current').stdout.strip()
        log = self.home / '.local/state/claude-auto-runs/repo'
        return [str(card or self.card), base, str(baseline or self.empty_baseline()), 'sess-1', str(log), reason]

    def empty_baseline(self):
        path = self.root / 'baseline-empty'; path.write_text(''); return path

    def park(self, *args, extra_env=None, **kw):
        env = {'SCHEDULE_SCOPE_ID': self.scope, **(extra_env or {})}
        return self.run_script('park-task.sh', *(args or self.park_args(**kw)), extra_env=env)

    def tree_state(self):
        return (self.head(), self.index(), self.git('branch', '--show-current').stdout,
                sorted((q.name, q.read_bytes()) for q in self.repo.iterdir() if q.is_file()))

    def test_park_snapshots_work_to_side_branch_and_leaves_checkout_untouched(self):
        hook = self.repo / '.git/hooks/pre-commit'; hook.write_text('#!/bin/sh\necho ran >> "$TEST_RECORD"\nexit 1\n'); hook.chmod(0o755)
        self.card.write_text('card\n## Parked\nQA failed\n')
        self.foreign.write_text('staged foreign edit\n'); self.git('add', '--', 'foreign.txt')
        (self.repo / 'new file.txt').write_text('fresh\n')
        self.card2.unlink()
        before = self.tree_state(); head = self.head()
        result = self.park()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.tree_state(), before)
        self.assertEqual(self.git('rev-parse', 'task/K-001^').stdout.strip(), head)
        changed = self.git('diff', '--no-renames', '--name-status', head, 'task/K-001').stdout.split('\n')
        self.assertEqual(sorted(x for x in changed if x), sorted([
            'M\t.agents/kanban/todo/K-001.md', 'D\t.agents/kanban/todo/K-002.md', 'M\tforeign.txt', 'A\tnew file.txt']))
        self.assertEqual(self.git('show', 'task/K-001:new file.txt').stdout, 'fresh\n')
        record = (self.home / '.local/state/claude-auto-runs/repo/.parked/K-001').read_text()
        self.assertIn('branch=task/K-001\n', record); self.assertIn('reason=blocker\n', record)
        self.assertIn('commit=' + self.git('rev-parse', 'task/K-001').stdout.strip(), record)
        self.assertNotIn('ran', self.records())
        second = self.park(reason='review-fail')
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.tree_state(), before)
        self.assertEqual(self.git('rev-parse', '--verify', 'task/K-001-2').returncode, 0)
        self.assertIn('replaces=' + self.git('rev-parse', 'task/K-001').stdout.strip(), (self.home / '.local/state/claude-auto-runs/repo/.parked/K-001').read_text())

    def test_park_with_clean_tree_records_without_branch(self):
        result = self.park()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('commit=none', (self.home / '.local/state/claude-auto-runs/repo/.parked/K-001').read_text())
        self.assertEqual(self.git('branch', '--list', 'task/*').stdout, '')

    def test_park_refusals_change_nothing(self):
        self.card.write_text('card\nedit\n')
        outside = self.todo / 'K-003.md'; outside.write_text('not in scope\n')
        nonempty = self.root / 'baseline-dirty'; nonempty.write_text(' M foreign.txt\n')
        (self.repo / '.git/MERGE_HEAD').write_text(self.head() + '\n')
        cases = {
            'no scope id': dict(args=self.park_args(), extra_env={'SCHEDULE_SCOPE_ID': ''}),
            'bad scope id': dict(args=self.park_args(), extra_env={'SCHEDULE_SCOPE_ID': 'x' * 64}),
            'card outside scope': dict(args=self.park_args(card=outside)),
            'wrong base branch': dict(args=self.park_args(base='other')),
            'merge in progress': dict(args=self.park_args()),
            'non-empty baseline': dict(args=self.park_args(baseline=nonempty)),
            'bad reason': dict(args=self.park_args(reason='whatever')),
        }
        (self.repo / '.git/MERGE_HEAD').unlink()
        for label, case in cases.items():
            with self.subTest(label):
                if label == 'merge in progress':
                    (self.repo / '.git/MERGE_HEAD').write_text(self.head() + '\n')
                before = self.tree_state()
                kw = {'extra_env': case['extra_env']} if 'extra_env' in case else {}
                result = self.park(*case['args'], **kw)
                self.assertNotEqual(result.returncode, 0)
                self.assertRegex(result.stderr, r'refused|scope error')
                self.assertEqual(self.tree_state(), before)
                self.assertEqual(self.git('branch', '--list', 'task/*').stdout, '')
                self.assertFalse((self.home / '.local/state/claude-auto-runs/repo/.parked').exists())
                if label == 'merge in progress':
                    (self.repo / '.git/MERGE_HEAD').unlink()

    def test_runner_exposes_scope_to_agent_and_names_the_park_command(self):
        self.mock('claude', 'echo "scope=$SCHEDULE_SCOPE_ID" >> "$TEST_RECORD"; printf "%s\\n" "$@" >> "$TEST_RECORD"; exit 0')
        self.run_script('run-claude-task-inner.sh', str(self.card), self.scope)
        records = self.records()
        self.assertIn('scope=' + self.scope, records)
        self.assertIn('park-task.sh', records)
        self.assertIn('AUTO-RUN-RESULT: park', records)
        self.assertNotIn('git switch', records)

    def test_chain_rejects_any_dirty_state_without_enqueuing(self):
        self.foreign.write_text('dirty\n'); baseline=self.root/'baseline';baseline.write_text('')
        result=self.run_script('chain-next-task.sh',str(self.repo),str(self.root/'parked'),self.card.name,self.scope,str(baseline))
        self.assertIn('AUTO-RUN-NEXT: none',result.stdout);self.assertNotIn('at\n',self.records())

    def test_nested_and_outside_board_are_rejected(self):
        nested=self.todo/'sub';nested.mkdir();(nested/'K-003.md').write_text('nested\n')
        result=self.run_script('create-task-scope.sh','--repo',str(self.repo),'--approved','--approval-source','explicit-user','--card',str(nested/'K-003.md'))
        self.assertNotEqual(result.returncode,0)
        outside=self.root/'outside';outside.mkdir();(outside/'K-004.md').write_text('outside\n')
        moved=self.repo/'.agents/kanban/todo-old'; self.todo.rename(moved);self.todo.symlink_to(outside,target_is_directory=True)
        result=self.run_script('create-task-scope.sh','--repo',str(self.repo),'--approved','--approval-source','explicit-user','--card',str(outside/'K-004.md'))
        self.assertNotEqual(result.returncode,0)

    def test_usage_summary_read_only_never_writes_card(self):
        sid='1234'; encoded=str(self.repo).replace('/','-');jsondir=self.home/'.claude/projects'/encoded;jsondir.mkdir(parents=True);(jsondir/(sid+'.jsonl')).write_text('{}\n')
        before=self.card.read_bytes();result=self.run_script('summarize-task-usage.sh',sid,str(self.card),'1','0','ok',extra_env={'TASK_USAGE_READ_ONLY':'1'})
        self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(self.card.read_bytes(),before);self.assertIn('read-only mode',result.stderr)

if __name__ == '__main__': unittest.main()
