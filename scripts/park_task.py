#!/usr/bin/env python3
"""Checkpoint an unfinished scheduled card without touching the checkout.

The working-tree changes are committed to a new side branch `task/<card>` from a
throw-away index (`GIT_INDEX_FILE`) with plumbing only. The real index, the
current branch and every working-tree file stay exactly as they were: nothing is
switched, staged, stashed, reset or cleaned. A `.parked/<card>` record is written
only after the snapshot commit has been read back and verified. Because the
working tree stays dirty, the scheduler's clean-baseline checks stop the chain
until an authorized step has dealt with the preserved work (owner-run: park-task-clean.sh).

Args: <CARD> <BASE_BRANCH> <BASELINE_FILE> <SESSION_ID> <LOG_DIR> <REASON>
"""
from __future__ import annotations

import fcntl
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REASONS = ("qa-fail", "review-fail", "blocker", "question", "merge-conflict")
CARD_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*\.md")
SESSION_RE = re.compile(r"[A-Za-z0-9._-]{1,128}")
UNMERGED = {"DD", "AU", "UD", "UA", "DU", "AA", "UU"}
IN_PROGRESS = ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply")
MAX_PATHS = 5000


class Refused(Exception):
    """Parking was refused; nothing was changed."""


def git(repo: str, *args: str, env=None, data: bytes = None) -> bytes:
    done = subprocess.run(["git", "-C", repo, *args], input=data, capture_output=True,
                          env={**os.environ, **(env or {})})
    if done.returncode != 0:
        first = (done.stderr.decode("utf-8", "replace").strip().splitlines() or ["git failed"])[0][:200]
        raise Refused("git %s: %s" % (args[0], first))
    return done.stdout


def git_ok(repo: str, *args: str) -> bool:
    return subprocess.run(["git", "-C", repo, *args], capture_output=True).returncode == 0


def parse_status(raw: bytes):
    parts, i, entries = raw.split(b"\0"), 0, []
    while i < len(parts):
        item = parts[i]
        i += 1
        if not item:
            continue
        xy, paths = item[:2].decode("ascii", "replace"), [item[3:]]
        if "R" in xy or "C" in xy:
            paths.append(parts[i])
            i += 1
        entries.append((xy, paths))
    return entries


def create_branch(repo: str, commit: str, base_name: str, reason: str) -> str:
    zero = "0" * len(commit)
    for n in range(1, 50):
        name = "task/%s" % base_name if n == 1 else "task/%s-%d" % (base_name, n)
        if not git_ok(repo, "check-ref-format", "--branch", name):
            raise Refused("card name does not form a valid branch name")
        if git_ok(repo, "show-ref", "--verify", "--quiet", "refs/heads/" + name):
            continue
        try:  # creates only if the ref is still absent
            git(repo, "update-ref", "-m", "park-task: " + reason, "refs/heads/" + name, commit, zero)
            return name
        except Refused:
            continue
    raise Refused("no free task/ branch name for this card")


def park(card_arg: str, base: str, baseline: str, session: str, log_dir: str, reason: str) -> str:
    if reason not in REASONS:
        raise Refused("reason must be one of: " + ", ".join(REASONS))
    if not SESSION_RE.fullmatch(session):
        raise Refused("session id has unsupported characters")
    card = Path(card_arg).resolve()
    if not card.is_file() or not CARD_RE.fullmatch(card.name):
        raise Refused("card must be an existing Kanban card file")
    name = card.name[:-3]
    repo = git(str(card.parent), "rev-parse", "--show-toplevel").decode().strip()
    if card.parent != Path(repo).resolve() and Path(repo).resolve() not in card.parents:
        raise Refused("card is outside its repository")
    if Path(baseline).read_text().strip():
        raise Refused("run baseline is not empty: pre-existing changes cannot be attributed to this run")
    branch = git(repo, "symbolic-ref", "--quiet", "--short", "HEAD").decode().strip() if git_ok(repo, "symbolic-ref", "--quiet", "HEAD") else ""
    if branch != base:
        raise Refused("current branch differs from the run's base branch; nothing parked")
    gitdir = Path(repo, git(repo, "rev-parse", "--git-dir").decode().strip())
    if any((gitdir / marker).exists() for marker in IN_PROGRESS):
        raise Refused("a merge, rebase, cherry-pick or revert is in progress; resolve or abort it through an authorized step")
    entries = parse_status(git(repo, "status", "--porcelain=v1", "-z", "--untracked-files=all"))
    if any(xy in UNMERGED for xy, _ in entries):
        raise Refused("unmerged paths exist; nothing parked")
    paths = sorted({p for _, group in entries for p in group})
    if len(paths) > MAX_PATHS:
        raise Refused("too many changed paths to snapshot (%d)" % len(paths))

    state = Path(log_dir)
    if state.is_symlink() or not state.is_dir():
        raise Refused("run-state directory is missing or a symlink")
    parked = state / ".parked"
    if parked.is_symlink():
        raise Refused(".parked must not be a symlink")
    parked.mkdir(mode=0o700, exist_ok=True)
    record = parked / name
    lock_fd = os.open(state / ".park.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os.close(lock_fd)
        raise Refused("another parking operation is running") from None
    try:
        head = git(repo, "rev-parse", "--verify", "HEAD").decode().strip()
        commit, snapshot_branch = "none", "none"
        if paths:
            with tempfile.TemporaryDirectory(prefix="park-index-") as tmp:
                env = {"GIT_INDEX_FILE": os.path.join(tmp, "index"), "GIT_LITERAL_PATHSPECS": "1"}
                git(repo, "read-tree", "HEAD", env=env)
                git(repo, "add", "-A", "--pathspec-from-file=-", "--pathspec-file-nul", env=env,
                    data=b"\0".join(paths) + b"\0")
                tree = git(repo, "write-tree", env=env).decode().strip()
            if tree != git(repo, "rev-parse", "HEAD^{tree}").decode().strip():
                commit = git(repo, "commit-tree", tree, "-p", head, "-m", "wip(park): %s (%s)" % (name, reason)).decode().strip()
                changed = {p for p in git(repo, "diff", "--no-renames", "--name-only", "-z", head, commit).split(b"\0") if p}
                if changed != set(paths):
                    raise Refused("snapshot content does not match the changed paths; nothing recorded")
                snapshot_branch = create_branch(repo, commit, name, reason)
                if git(repo, "rev-parse", "--verify", "refs/heads/%s^{commit}" % snapshot_branch).decode().strip() != commit:
                    raise Refused("snapshot branch read-back mismatch")
        previous = record.read_text().split("commit=", 1)[1].splitlines()[0] if record.is_file() and "commit=" in record.read_text() else "none"
        card_rel = os.path.relpath(card, repo)
        body = ("branch=%s\nbase=%s\nsession=%s\nreason=%s\ncard=%s\ncommit=%s\nreplaces=%s\n"
                % (snapshot_branch, base, session, reason, card_rel, commit, previous))
        tmp_record = parked / (".%s.tmp-%d" % (name, os.getpid()))
        fd = os.open(tmp_record, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as handle:
            handle.write(body)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_record, record)
    finally:
        os.close(lock_fd)
    if commit == "none":
        return "[park] recorded %s (reason=%s); no working-tree changes to snapshot" % (name, reason)
    return ("[park] snapshot of %d path(s) for %s on %s @ %s (reason=%s); branch, index and working tree are unchanged. "
            "Resolve the working tree through an authorized step before the next scheduled run "
            "(owner-run: park-task-clean.sh --branch %s, dry-run first)."
            % (len(paths), name, snapshot_branch, commit[:12], reason, snapshot_branch))


def main(argv) -> int:
    if len(argv) != 6:
        sys.stderr.write("Usage: park_task.py <card> <base-branch> <baseline> <session> <log-dir> <reason>\n")
        return 2
    try:
        print(park(*argv))
        return 0
    except Refused as exc:
        sys.stderr.write("ERROR: parking refused: %s\n" % exc)
        return 1
    except OSError as exc:
        sys.stderr.write("ERROR: parking failed: %s\n" % (exc.strerror or type(exc).__name__))
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
