#!/usr/bin/env python3
"""Read-only ancestry and patch-equivalence evidence for local branch refs.

An explicit base commit is required. No fetch, network access, ref mutation,
worktree content inspection, or branch deletion is performed. A matching patch
is evidence about patch identity, not proof that the branch is safe to delete.
"""

import argparse
import json
import re
import subprocess
import sys


def git(*args, allowed=(0,)):
    result = subprocess.run(
        ["git", "--no-optional-locks", *args],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode not in allowed:
        raise RuntimeError("git " + " ".join(args[:2]) + " failed (exit " + str(result.returncode) + ")")
    return result


def commit_oid(ref):
    out = git("rev-parse", "--verify", "--end-of-options", ref + "^{commit}").stdout
    oid = out.decode("ascii").strip()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", oid):
        raise RuntimeError("Git returned an invalid commit identifier")
    return oid


def branch_snapshot():
    raw = git("for-each-ref", "--format=%(refname)%00%(objectname)", "refs/heads/").stdout
    result = {}
    for line in raw.splitlines():
        ref, sep, oid = line.partition(b"\0")
        if not sep or not re.fullmatch(rb"[0-9a-f]{40}|[0-9a-f]{64}", oid):
            raise RuntimeError("Git returned invalid branch data")
        result[ref.decode("utf-8", "surrogateescape")] = oid.decode("ascii")
    return result


def checked_out_refs():
    data = git("worktree", "list", "--porcelain", "-z").stdout
    return {
        part[7:].decode("utf-8", "surrogateescape")
        for part in data.split(b"\0") if part.startswith(b"branch ")
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, help="exact comparison base ref or commit")
    args = parser.parse_args()
    try:
        base = commit_oid(args.base)
        branches = branch_snapshot()
        checked_out = checked_out_refs()
        rows = []
        for ref, oid in sorted(branches.items()):
            if commit_oid(ref) != oid:
                raise RuntimeError("branch tip changed during audit: " + ref)
            ancestor = git("merge-base", "--is-ancestor", oid, base, allowed=(0, 1)).returncode == 0
            if ancestor:
                status = "ancestor"
            else:
                cherry = git("cherry", base, oid).stdout.splitlines()
                if not cherry or any(not re.fullmatch(rb"[+-] [0-9a-f]{40}|[+-] [0-9a-f]{64}", line) for line in cherry):
                    raise RuntimeError("git cherry returned empty or invalid evidence for " + ref)
                status = "patch-equivalent" if all(line.startswith(b"- ") for line in cherry) else "unique-patches"
            rows.append({"ref": ref, "tip": oid, "status": status, "checked_out": ref in checked_out})
        if commit_oid(args.base) != base or branch_snapshot() != branches or checked_out_refs() != checked_out:
            raise RuntimeError("base, branch tips or checked-out branches changed during audit; retry")
        print(json.dumps({"base": base, "branches": rows}, ensure_ascii=True, indent=2))
    except (RuntimeError, OSError, UnicodeError) as exc:
        print("branch audit failed: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
