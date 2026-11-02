#!/usr/bin/env python3
"""Build a local Codex marketplace/plugin snapshot from the working tree.

Usage from the project root: python3 scripts/build-codex-package.py DESTINATION
DESTINATION must not exist. Inspect scripts/codex-package-extra-files.json when
adding new, not-yet-tracked distribution files. Never point Codex at the source
tree: the installer copies the entire marketplace source, including ignored
files. This build does not write Git state or Codex settings.
"""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys

if len(sys.argv) != 2:
    raise SystemExit(__doc__)
root = Path(__file__).resolve().parent.parent
destination = Path(sys.argv[1]).absolute()
extra_path = root / 'scripts/codex-package-extra-files.json'
build_only = {'scripts/build-codex-package.py', 'scripts/codex-package-extra-files.json', 'scripts/skills_registry.py'}
# Pre-existing user material outside the reviewed plugin runtime.
excluded = set()
removed_skills = {'agent-telegram-notify', 'research-knowledge-build', 'quality-risk-triage',
                  'security-ipc-verify', 'research-claims-verify', 'personal-resume-build'}
extras = json.loads(extra_path.read_text())
if not isinstance(extras, list) or not all(isinstance(x, str) for x in extras) or len(extras) != len(set(extras)):
    raise SystemExit('extra file list must contain unique strings')

index = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--stage', '-z'])
tracked = []
for entry in index.split(b'\0'):
    if not entry:
        continue
    metadata, raw = entry.split(b'\t', 1)
    mode, _, stage = metadata.decode('ascii').split()
    if stage != '0':
        raise SystemExit('unmerged Git index; resolve it before packaging')
    path = os.fsdecode(raw)
    if path in build_only or path in excluded:
        continue
    parts = PurePosixPath(path).parts
    if len(parts) >= 2 and parts[0] == 'skills' and parts[1] in removed_skills:
        continue
    if path.split('/')[0] in {'skills', 'hooks', 'scripts', 'agents'} or path in {
        '.agents/plugins/marketplace.json', '.codex-plugin/plugin.json', 'LICENSE'
    }:
        if mode not in {'100644', '100755'}:
            raise SystemExit('tracked symlink or gitlink refused: ' + path)
        tracked.append(path)
if build_only.intersection(extras):
    raise SystemExit('build-only files must not be included in the runtime package')
if excluded.intersection(extras):
    raise SystemExit('user-owned excluded files must not be included in the runtime package')
paths = sorted(set(tracked) | set(extras))
# A concurrent migration can add reference files after the explicit list was
# reviewed. Refuse an incomplete selected skill instead of silently shipping it.
selected_new_skills = {PurePosixPath(p).parts[1] for p in extras
                       if len(PurePosixPath(p).parts) >= 3 and PurePosixPath(p).parts[0] == 'skills'}
untracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--others',
                                     '--exclude-standard', '-z', '--', 'skills'])
for raw in untracked.split(b'\0'):
    if not raw:
        continue
    item = os.fsdecode(raw)
    parts = PurePosixPath(item).parts
    if item in excluded:
        continue
    if len(parts) >= 3 and parts[1] in selected_new_skills and item not in extras:
        raise SystemExit('review and list new skill file before packaging: ' + item)
    if len(parts) == 3 and parts[0] == 'skills' and parts[2] == 'SKILL.md' and item not in extras:
        raise SystemExit('review and list new skill package before packaging: ' + item)
required = {'.agents/plugins/marketplace.json', '.codex-plugin/plugin.json', 'hooks/codex-hooks.json'}
if not required.issubset(paths):
    raise SystemExit('required files missing')
if destination.exists() or destination.is_symlink():
    raise SystemExit('destination must not exist; choose a fresh path')
allowed_roots = {'skills', 'hooks', 'scripts', 'agents'}
exact = required | {'LICENSE'}
for item in paths:
    p = PurePosixPath(item)
    if p.is_absolute() or '..' in p.parts or '.' in p.parts or not p.parts:
        raise SystemExit('unsafe path: ' + item)
    if item not in exact and p.parts[0] not in allowed_roots:
        raise SystemExit('path outside distribution: ' + item)
    if any(part in {'.git', '.claude', 'tmp', '__pycache__', 'node_modules'} for part in p.parts):
        raise SystemExit('private or generated path refused: ' + item)
    if (p.name.startswith('.env') and p.name != '.env.example') or p.suffix.lower() in {'.key', '.pem', '.p12', '.pfx', '.db', '.sqlite'}:
        raise SystemExit('potential credential file refused: ' + item)
    for n in range(1, len(p.parts) + 1):
        if root.joinpath(*p.parts[:n]).is_symlink():
            raise SystemExit('symlink refused: ' + item)
    if not (root / item).is_file():
        raise SystemExit('missing or non-regular file: ' + item)

destination.mkdir(mode=0o700, parents=True)
digests = {}
try:
    for item in paths:
        src, dst = root / item, destination / item
        dst.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd = os.open(src, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, 'rb') as file:
            before = os.fstat(file.fileno())
            if not stat.S_ISREG(before.st_mode):
                raise RuntimeError('not regular: ' + item)
            data = file.read()
            after = os.fstat(file.fileno())
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise RuntimeError('file changed during read: ' + item)
        dst.write_bytes(data)
        dst.chmod(0o700 if before.st_mode & 0o111 else 0o600)
        digests[item] = hashlib.sha256(data).hexdigest()
    plugin = json.loads((destination / '.codex-plugin/plugin.json').read_text())
    marketplace = json.loads((destination / '.agents/plugins/marketplace.json').read_text())
    if plugin.get('skills') != './skills/' or plugin.get('hooks') != './hooks/codex-hooks.json':
        raise RuntimeError('unexpected plugin paths; update the package builder')
    entries = marketplace.get('plugins', [])
    if len(entries) != 1 or entries[0].get('source') != {'source': 'local', 'path': './'}:
        raise RuntimeError('unexpected marketplace source')
    print(json.dumps({'files': len(paths), 'sha256': digests}, sort_keys=True))
except BaseException:
    shutil.rmtree(destination)
    raise
