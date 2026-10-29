#!/usr/bin/env python3
"""Owner-run: restore the working tree after `park-task.sh` has preserved its changes.

`park-task.sh` snapshots unfinished work to the side branch `task/<card>` and leaves
the checkout dirty on purpose. This command removes exactly those parked changes
from the checkout, but only after proving that the branch holds them:

* the branch is a single-parent `wip(park):` snapshot whose parent is the current HEAD;
* the working-tree content of every snapshotted path equals the snapshot byte for byte
  (same mode and blob, compared through a throw-away index);
* each such path is either unstaged or staged exactly as snapshotted.

Dry-run (default) prints the plan and `plan_sha256`. `--apply --plan-sha256 <hash>`
recomputes the plan under a lock and changes nothing unless it matches. Paths that
are not part of the snapshot are never touched. Nothing is deleted that the branch
does not hold, and the branch itself is never changed. Not available inside a
scheduled run (`SCHEDULE_SCOPE_ID` set).

Usage: park_task_clean.py [--repo DIR] (--branch task/<card> | --record FILE)
                          [--apply --plan-sha256 HASH]
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

_spec = importlib.util.spec_from_file_location("park_task", Path(__file__).with_name("park_task.py"))
park_task = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(park_task)
Refused, git, git_ok, parse_status = park_task.Refused, park_task.git, park_task.git_ok, park_task.parse_status

BRANCH_RE = re.compile(r"task/[A-Za-z0-9][A-Za-z0-9._-]*")
HASH_RE = re.compile(r"[0-9a-f]{64}")
SUBJECT_PREFIX = "wip(park): "
GITLINK = b"160000"
LIST_CAP = 50


def lit(path: bytes) -> str:
    return os.fsdecode(path)


def nul_list(paths) -> bytes:
    return b"\0".join(paths) + b"\0"


def read_record(path: str):
    p = Path(path)
    if p.is_symlink() or not p.is_file() or p.stat().st_size > 4096:
        raise Refused("park record must be a small regular file")
    fields = dict(line.split("=", 1) for line in p.read_text().splitlines() if "=" in line)
    branch, commit = fields.get("branch", ""), fields.get("commit", "")
    if commit == "none" or branch == "none":
        raise Refused("the park record has no snapshot; there is nothing to clean")
    if not re.fullmatch(r"[0-9a-f]{40,64}", commit):
        raise Refused("park record has no valid commit")
    return branch, commit


def snapshot_changes(repo: str, parent: str, tip: str):
    tokens = git(repo, "diff-tree", "-r", "--no-renames", "-z", "--raw", "--no-abbrev", parent, tip).split(b"\0")
    changes, i = {}, 0
    while i + 1 < len(tokens):
        meta, path = tokens[i], tokens[i + 1]
        i += 2
        if not meta.startswith(b":"):
            raise Refused("unexpected diff output")
        old_mode, new_mode, old_oid, new_oid, _status = meta[1:].split(b" ")
        old = None if not old_oid.strip(b"0") else (old_mode, old_oid)
        new = None if not new_oid.strip(b"0") else (new_mode, new_oid)
        if GITLINK in (old_mode, new_mode):
            raise Refused("the snapshot contains a submodule path; clean it by hand")
        changes[path] = (old, new)
    if not changes:
        raise Refused("the snapshot holds no changes")
    if len(changes) > park_task.MAX_PATHS:
        raise Refused("too many snapshotted paths (%d)" % len(changes))
    return changes


def index_entries(repo: str):
    entries = {}
    for record in git(repo, "ls-files", "-s", "-z").split(b"\0"):
        if not record:
            continue
        meta, path = record.split(b"\t", 1)
        mode, oid, stage = meta.split(b" ")
        entries.setdefault(path, []).append((mode, oid, stage))
    return entries


def worktree_tree(repo: str, head: str, paths) -> str:
    with tempfile.TemporaryDirectory(prefix="park-clean-index-") as tmp:
        env = {"GIT_INDEX_FILE": os.path.join(tmp, "index"), "GIT_LITERAL_PATHSPECS": "1"}
        git(repo, "read-tree", head, env=env)
        git(repo, "add", "-A", "--pathspec-from-file=-", "--pathspec-file-nul", env=env, data=nul_list(paths))
        return git(repo, "write-tree", env=env).decode().strip()


def check_removable(root: str, path: bytes):
    """An added path may be unlinked only as a plain file or symlink below real directories."""
    parts = os.fsdecode(path).split("/")
    current = root
    for part in parts[:-1]:
        current = os.path.join(current, part)
        mode = os.lstat(current).st_mode
        if not stat.S_ISDIR(mode):
            raise Refused("a parent of %s is not a real directory" % lit(path))
    mode = os.lstat(os.path.join(root, *parts)).st_mode
    if not (stat.S_ISREG(mode) or stat.S_ISLNK(mode)):
        raise Refused("%s is not a plain file or symlink" % lit(path))


def build_plan(repo: str, branch: str, record_commit):
    if not BRANCH_RE.fullmatch(branch) or not git_ok(repo, "check-ref-format", "--branch", branch):
        raise Refused("branch must be a task/<card> snapshot branch")
    tip = git(repo, "rev-parse", "--verify", "refs/heads/%s^{commit}" % branch).decode().strip()
    if record_commit and record_commit != tip:
        raise Refused("the branch no longer points at the commit in the park record")
    commits = git(repo, "rev-list", "--parents", "-n", "1", tip).decode().split()
    if len(commits) != 2:
        raise Refused("the branch tip is not a single-parent park snapshot")
    parent = commits[1]
    if not git(repo, "log", "-1", "--format=%s", tip).decode().startswith(SUBJECT_PREFIX):
        raise Refused("the branch tip is not a park snapshot (subject must start with 'wip(park): ')")
    head = git(repo, "rev-parse", "--verify", "HEAD^{commit}").decode().strip()
    if head != parent:
        raise Refused("HEAD is not the commit this snapshot was taken from; the checkout is no longer the parked state")
    gitdir = Path(repo, git(repo, "rev-parse", "--git-dir").decode().strip())
    if any((gitdir / marker).exists() for marker in park_task.IN_PROGRESS):
        raise Refused("a merge, rebase, cherry-pick or revert is in progress")
    status = parse_status(git(repo, "status", "--porcelain=v1", "-z", "--untracked-files=all"))
    if any(xy in park_task.UNMERGED for xy, _ in status):
        raise Refused("unmerged paths exist")

    changes = snapshot_changes(repo, parent, tip)
    paths = sorted(changes)
    snapshot_tree = git(repo, "rev-parse", tip + "^{tree}").decode().strip()
    try:
        current = worktree_tree(repo, head, paths)
    except Refused as exc:
        raise Refused("the working tree differs from the snapshot (already cleaned or edited since: %s); nothing changed"
                      % exc) from None
    if current != snapshot_tree:
        diff = git(repo, "diff-tree", "-r", "--no-renames", "--name-only", "-z", current, snapshot_tree).split(b"\0")
        diff = [lit(p) for p in diff if p][:20]
        raise Refused("the working tree differs from the snapshot (already cleaned or edited since): %s; nothing changed"
                      % ", ".join(diff))

    index = index_entries(repo)
    restore, remove, index_reset = [], [], []
    root = str(Path(repo).resolve())
    for path in paths:
        old, new = changes[path]
        staged = index.get(path)
        if staged and any(stage != b"0" for _, _, stage in staged):
            raise Refused("%s has unmerged index entries" % lit(path))
        entry = (staged[0][0], staged[0][1]) if staged else None
        if entry not in (old, new):
            raise Refused("the index holds a third version of %s; resolve it before cleaning" % lit(path))
        if entry != old:
            index_reset.append(path)
        if old is None:
            check_removable(root, path)
            remove.append(path)
        else:
            restore.append(path)

    touched = set(paths)
    untouched = sorted({p for _, group in status for p in group if p not in touched})
    plan = {
        "repo": root, "branch": branch, "commit": tip, "head": head, "tree": snapshot_tree,
        "restore": [lit(p) for p in restore], "remove": [lit(p) for p in remove],
        "index_reset": [lit(p) for p in index_reset],
    }
    digest = hashlib.sha256(json.dumps(plan, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    shown = dict(plan, plan_sha256=digest, left_untouched=[lit(p) for p in untouched[:LIST_CAP]],
                 left_untouched_total=len(untouched))
    return shown, (restore, remove, index_reset, paths, root)


def remove_added(root: str, path: bytes):
    os.unlink(os.path.join(root, os.fsdecode(path)))
    parent = os.path.dirname(os.path.join(root, os.fsdecode(path)))
    while parent != root and parent.startswith(root + os.sep):
        try:
            os.rmdir(parent)
        except OSError:
            break
        parent = os.path.dirname(parent)


def run(repo_arg, branch, record, apply, plan_hash):
    if os.environ.get("SCHEDULE_SCOPE_ID"):
        raise Refused("owner-run command: not available inside a scheduled run")
    repo = git(repo_arg, "rev-parse", "--show-toplevel").decode().strip()
    if git(repo, "rev-parse", "--is-bare-repository").decode().strip() != "false":
        raise Refused("a working tree is required")
    record_branch = record_commit = None
    if record:
        record_branch, record_commit = read_record(record)
    if branch and record_branch and branch != record_branch:
        raise Refused("--branch disagrees with the park record")
    branch = branch or record_branch
    if not branch:
        raise Refused("give --branch task/<card> or --record <.parked/card>")
    if apply and not (plan_hash and HASH_RE.fullmatch(plan_hash)):
        raise Refused("--apply needs --plan-sha256 from a reviewed dry-run; nothing changed")

    gitdir = Path(repo, git(repo, "rev-parse", "--git-dir").decode().strip())
    fd = os.open(gitdir / "park-clean.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise Refused("another cleanup is running") from None
        shown, (restore, remove, index_reset, paths, root) = build_plan(repo, branch, record_commit)
        if not apply:
            shown["applied"] = False
            return shown
        if plan_hash != shown["plan_sha256"]:
            raise Refused("the checkout or the branch differs from the reviewed plan; nothing changed — rerun the dry-run")

        env = {"GIT_LITERAL_PATHSPECS": "1"}
        if index_reset:
            git(repo, "reset", "-q", shown["head"], "--pathspec-from-file=-", "--pathspec-file-nul", env=env,
                data=nul_list(index_reset))
        if restore:
            git(repo, "restore", "--source", shown["head"], "--worktree", "--pathspec-from-file=-",
                "--pathspec-file-nul", env=env, data=nul_list(restore))
        for path in remove:
            remove_added(root, path)

        left = parse_status(git(repo, "status", "--porcelain=v1", "-z", "--untracked-files=all"))
        touched = set(paths)
        still = sorted(lit(p) for _, group in left for p in group if p in touched)
        tip_now = git(repo, "rev-parse", "--verify", "refs/heads/%s^{commit}" % branch).decode().strip()
        if still or tip_now != shown["commit"]:
            raise Refused("verification failed after cleaning (still dirty: %s); the parked content is safe on %s"
                          % (", ".join(still[:20]) or "none", branch))
        untouched = sorted({lit(p) for _, group in left for p in group})
        shown["applied"] = True
        shown["left_untouched"], shown["left_untouched_total"] = untouched[:LIST_CAP], len(untouched)
        return shown
    finally:
        os.close(fd)


def main(argv) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--repo", default=".")
    parser.add_argument("--branch")
    parser.add_argument("--record")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--plan-sha256")
    options = parser.parse_args(argv)
    try:
        result = run(options.repo, options.branch, options.record, options.apply, options.plan_sha256)
    except Refused as exc:
        sys.stderr.write("ERROR: cleanup refused: %s\n" % exc)
        return 1
    except OSError as exc:
        sys.stderr.write("ERROR: cleanup failed: %s\n" % (exc.strerror or type(exc).__name__))
        return 1
    print(json.dumps(result, sort_keys=True, indent=2))
    if result["applied"]:
        sys.stderr.write("[park-clean] checkout restored for %d path(s); the changes remain on %s (git diff HEAD %s)\n"
                         % (len(result["restore"]) + len(result["remove"]), result["branch"], result["branch"]))
    else:
        sys.stderr.write("[park-clean] dry-run only; review the plan, then rerun with --apply --plan-sha256 %s\n"
                         % result["plan_sha256"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
