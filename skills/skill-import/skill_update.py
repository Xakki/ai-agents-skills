#!/usr/bin/env python3
"""Receipts and reviewed updates for imported skills.

`write-receipt` is called by import-skill.sh: it records, inside the new skill
directory, where it came from and the SHA-256 of every file. `update` compares
three trees (the receipt baseline, the local directory and the upstream
`HEAD` of a clean, origin-verified local cache) and prints a plan with a
`plan_sha256`. `update --apply --plan-sha256 <hash>` replaces the directory only
if the plan still has that hash. Local modifications, added or hidden files
block the replacement unless `--discard-local` is also given; either way the old
directory is moved, whole, to a backup directory and never deleted. The Git
index, the manifest and every other path stay untouched.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path, PurePosixPath

RECEIPT = ".skill-import.json"
FORMAT = "skill-import-receipt-v1"
NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
LOC_RE = re.compile(r"[A-Za-z0-9._/-]+")
MAX_FILES = 5000
MAX_BYTES = 50 * 1024 * 1024


class Refused(Exception):
    """The operation was refused; nothing was changed."""


def digest_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def scan_tree(root: Path, skip_receipt: bool = True) -> dict:
    """{relative posix path: [sha256, exec-bit]} for every file; symlinks are refused."""
    files, total = {}, 0
    for dirpath, dirnames, filenames in os.walk(root):
        for name in list(dirnames) + filenames:
            if os.path.islink(os.path.join(dirpath, name)):
                raise Refused("symlink inside the skill directory: %s" % name)
        for name in filenames:
            path = Path(dirpath, name)
            rel = path.relative_to(root).as_posix()
            if skip_receipt and rel == RECEIPT:
                continue
            info = path.lstat()
            if not stat.S_ISREG(info.st_mode):
                raise Refused("non-regular file inside the skill directory: %s" % rel)
            total += info.st_size
            if len(files) >= MAX_FILES or total > MAX_BYTES:
                raise Refused("skill directory exceeds the size limits")
            files[rel] = [digest_file(path), 1 if info.st_mode & 0o111 else 0]
    return files


def write_receipt(args) -> int:
    payload = Path(args.directory)
    receipt = {
        "format": FORMAT, "source": args.source, "skill": args.skill, "location": args.location,
        "origin": args.origin, "commit": args.commit, "imported_at": int(time.time()),
        "files": scan_tree(payload),
    }
    target = payload / RECEIPT
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    with os.fdopen(fd, "w") as handle:
        json.dump(receipt, handle, indent=1, sort_keys=True)
        handle.write("\n")
    return 0


def git(clone: Path, *args: str, data: bytes = None) -> bytes:
    done = subprocess.run(["git", "-C", str(clone), *args], input=data, capture_output=True)
    if done.returncode != 0:
        raise Refused("git %s failed" % args[0])
    return done.stdout


def tsv_rows(path: Path):
    for line in path.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            yield line.split("\t")


def no_symlinks(path: Path) -> None:
    for part in (path, *path.parents):
        if part.is_symlink():
            raise Refused("path contains a symlink: %s" % part)


def resolve_inputs(args):
    if not (NAME_RE.fullmatch(args.source) and NAME_RE.fullmatch(args.skill)) or ".." in args.source + args.skill:
        raise Refused("invalid source or skill name")
    project = Path(args.project).resolve()
    dest_root = Path(os.path.abspath(Path(args.dest) if Path(args.dest).is_absolute() else project / args.dest))
    try:
        rel = dest_root.relative_to(project)
    except ValueError:
        raise Refused("destination is outside the project") from None
    if not rel.parts:
        raise Refused("destination cannot be the project root")
    current = project
    for part in rel.parts:
        current = current / part
        if current.is_symlink():
            raise Refused("destination path contains a symlink")
    cache = Path(args.cache)
    no_symlinks(cache.absolute())
    catalog = Path(args.catalog) if args.catalog else cache / "catalog.tsv"
    for f in (catalog, Path(args.sources)):
        if not f.is_file() or f.is_symlink():
            raise Refused("catalog or sources file unavailable or symlinked")
    rows = [r for r in tsv_rows(catalog) if len(r) >= 4 and r[0] == args.source and r[1] == args.skill]
    if len(rows) != 1:
        raise Refused("catalog entry missing or ambiguous")
    kind, loc = rows[0][2], rows[0][3]
    if kind != "local":
        raise Refused("external catalog entries are not updated; prepare a verified local cache first")
    if not LOC_RE.fullmatch(loc) or loc.startswith("/") or ".." in loc:
        raise Refused("unsafe source location")
    origins = [r[1] for r in tsv_rows(Path(args.sources)) if len(r) >= 2 and r[0] == args.source]
    if len(origins) != 1:
        raise Refused("source configuration missing or ambiguous")
    clone = cache / "repos" / args.source
    if clone.is_symlink() or (clone / ".git").is_symlink() or not (clone / ".git").is_dir():
        raise Refused("source cache missing or symlinked")
    actual = git(clone, "config", "--get-all", "remote.origin.url").decode().strip()
    if actual != origins[0]:
        raise Refused("source origin does not match the configured provenance")
    sha = git(clone, "rev-parse", "--verify", "HEAD^{commit}").decode().strip()
    if subprocess.run(["git", "-C", str(clone), "diff", "--quiet", "HEAD", "--", loc]).returncode != 0:
        raise Refused("source cache has modified tracked files")
    return project, dest_root, dest_root / args.skill, clone, sha, loc, origins[0]


def extract_upstream(clone: Path, sha: str, loc: str, skill: str, target: Path) -> dict:
    raw = git(clone, "ls-tree", "-rz", sha, "--", loc)
    if not raw:
        raise Refused("no tracked files at the source location")
    prefix = "" if loc == "." else loc.rstrip("/") + "/"
    for item in filter(None, raw.split(b"\0")):
        meta, name = item.split(b"\t", 1)
        parts = PurePosixPath(name.decode("utf-8")).parts
        if meta.split(b" ", 1)[0] not in (b"100644", b"100755") or not parts or ".git" in parts or ".." in parts \
                or any(ord(c) < 32 for c in name.decode()):
            raise Refused("unsafe or unsupported source entry")
    archive = git(clone, "archive", sha, "--", loc)
    target.mkdir(parents=True)
    files, total = {}, 0
    with tarfile.open(fileobj=io.BytesIO(archive)) as tf:
        for member in tf:
            if not member.isfile():
                continue
            rel = member.name[len(prefix):] if prefix and member.name.startswith(prefix) else member.name
            if prefix and not member.name.startswith(prefix):
                continue
            pure = PurePosixPath(rel)
            if pure.is_absolute() or ".." in pure.parts or rel == RECEIPT:
                raise Refused("unsafe archive member")
            total += member.size
            if len(files) >= MAX_FILES or total > MAX_BYTES:
                raise Refused("source exceeds the size limits")
            out = target / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(tf.extractfile(member).read())
            out.chmod(0o755 if member.mode & 0o111 else 0o644)
            files[rel] = [digest_file(out), 1 if member.mode & 0o111 else 0]
    skill_md = target / "SKILL.md"
    if not skill_md.is_file():
        raise Refused("source has no regular SKILL.md")
    match = re.match(r"^---\s*\n(.*?)\n---(?:\s*\n|$)", skill_md.read_text(encoding="utf-8"), re.S)
    names = re.findall(r"^name:\s*([^\n]+)\s*$", match.group(1), re.M) if match else []
    if len(names) != 1 or names[0].strip().strip("\"'") != skill:
        raise Refused("declared skill name does not match the selected catalog entry")
    return files


def make_plan(args, workdir: Path):
    project, dest_root, dest, clone, sha, loc, origin = resolve_inputs(args)
    if not dest.is_dir() or dest.is_symlink():
        raise Refused("destination skill directory is missing; use import-skill.sh for a new import")
    upstream_dir = workdir / "upstream"
    upstream = extract_upstream(clone, sha, loc, args.skill, upstream_dir)
    local = scan_tree(dest)
    receipt_path = dest / RECEIPT
    base, receipt_commit = {}, None
    if receipt_path.is_file():
        try:
            receipt = json.loads(receipt_path.read_text())
            assert receipt["format"] == FORMAT and receipt["skill"] == args.skill and receipt["source"] == args.source
            base, receipt_commit = receipt["files"], receipt["commit"]
        except (ValueError, KeyError, AssertionError):
            raise Refused("receipt is unreadable or belongs to another skill; treat the copy as unreceipted by moving it aside") from None
    local_modified = sorted(p for p in local if p in base and local[p] != base[p])
    local_added = sorted(p for p in local if p not in base)
    local_deleted = sorted(p for p in base if p not in local)
    up_add = sorted(p for p in upstream if p not in local)
    up_change = sorted(p for p in upstream if p in local and upstream[p] != local[p])
    up_remove = sorted(p for p in local if p not in upstream)
    has_local_changes = bool(local_modified or local_added or local_deleted)
    nothing = not (up_add or up_change or up_remove)
    plan = {
        "skill": args.skill, "source": args.source, "origin": origin, "location": loc,
        "receipt_commit": receipt_commit, "upstream_commit": sha, "has_receipt": receipt_path.is_file(),
        "up_to_date": nothing and not has_local_changes,
        "upstream_changes": {"add": up_add, "change": up_change, "remove": up_remove},
        "local_changes": {"modified": local_modified, "added": local_added, "deleted": local_deleted},
        "discard_local_required": has_local_changes or not receipt_path.is_file(),
    }
    plan["plan_sha256"] = hashlib.sha256(json.dumps(
        {**plan, "base": base, "local": local, "upstream": upstream}, sort_keys=True).encode()).hexdigest()
    return plan, upstream, upstream_dir, dest_root, dest, project, sha, loc, origin


def backup_root(dest_root: Path) -> Path:
    return dest_root.parent / ".skill-import-backups"


def apply_plan(args) -> dict:
    project, dest_root, dest, *_ = resolve_inputs(args)
    dest_root.mkdir(parents=True, exist_ok=True)
    lock_fd = os.open(dest_root / ".skill-import.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    stage = None
    try:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise Refused("another skill-import operation holds the lock") from None
        stage = Path(tempfile.mkdtemp(prefix=".skill-import.", dir=dest_root))
        plan, upstream, upstream_dir, dest_root, dest, project, sha, loc, origin = make_plan(args, stage)
        if plan["plan_sha256"] != args.plan_sha256:
            raise Refused("state differs from the reviewed plan; run the plan again and review it")
        if plan["up_to_date"]:
            raise Refused("nothing to apply: the copy already matches the cache")
        if plan["discard_local_required"] and not args.discard_local:
            raise Refused("local modifications or an unreceipted copy would be replaced; add --discard-local only if that is authorized")
        payload = stage / "payload"
        upstream_dir.rename(payload)
        # the receipt for the new copy
        ns = argparse.Namespace(directory=str(payload), source=args.source, skill=args.skill, location=loc, origin=origin, commit=sha)
        write_receipt(ns)
        if scan_tree(payload) != upstream:
            raise Refused("staged copy does not match the upstream tree")
        backups = backup_root(dest_root)
        backups.mkdir(parents=True, exist_ok=True, mode=0o700)
        old_commit = plan["receipt_commit"] or "unreceipted"
        stem = "%s-%s-%s" % (args.skill, time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), old_commit[:12])
        backup, n = backups / stem, 1
        while backup.exists():
            n += 1
            backup = backups / ("%s-%d" % (stem, n))
        os.rename(dest, backup)  # atomic, same filesystem; nothing is deleted
        try:
            os.rename(payload, dest)
        except OSError:
            os.rename(backup, dest)
            raise Refused("could not place the new copy; the original was restored") from None
        return {"applied": True, "skill": args.skill, "commit": sha, "backup": str(backup),
                "discarded_local": plan["local_changes"] if plan["discard_local_required"] else None}
    finally:
        if stage is not None:
            shutil.rmtree(stage, ignore_errors=True)  # our own staging directory only
        os.close(lock_fd)


def cmd_update(args) -> int:
    if args.apply:
        if not args.plan_sha256:
            raise Refused("--apply requires --plan-sha256 from a reviewed plan")
        print(json.dumps(apply_plan(args), indent=2, sort_keys=True))
        return 0
    with tempfile.TemporaryDirectory(prefix="skill-import-plan.") as tmp:
        plan = make_plan(args, Path(tmp))[0]
    print(json.dumps(plan, indent=2, sort_keys=True))
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    receipt = sub.add_parser("write-receipt")
    receipt.add_argument("directory")
    for name in ("source", "skill", "location", "origin", "commit"):
        receipt.add_argument("--" + name, required=True)
    update = sub.add_parser("update")
    update.add_argument("source")
    update.add_argument("skill")
    update.add_argument("--project", default=os.getcwd())
    update.add_argument("--dest", default=os.environ.get("SKILL_IMPORT_DEST", ".agents/skills"))
    update.add_argument("--cache", default=os.environ.get("SKILL_IMPORT_CACHE", str(Path.home() / ".cache/skill-import")))
    update.add_argument("--catalog", default="")
    update.add_argument("--sources", required=True)
    update.add_argument("--apply", action="store_true")
    update.add_argument("--plan-sha256")
    update.add_argument("--discard-local", action="store_true")
    args = parser.parse_args(argv)
    try:
        return write_receipt(args) if args.command == "write-receipt" else cmd_update(args)
    except Refused as exc:
        sys.stderr.write("skill-import: refused: %s\n" % exc)
        return 3
    except (OSError, UnicodeDecodeError, tarfile.TarError) as exc:
        sys.stderr.write("skill-import: failed: %s\n" % type(exc).__name__)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
