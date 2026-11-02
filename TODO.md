# TODO

## Groom: improve the kanban linter using net-watcher's `verify_kanban.py`

**Status:** grooming — needs a design decision before implementation.

**Context.** The net-watcher project carried its own stdlib board verifier
(`tools/verify_kanban.py`, wired into `make kanban-lint`). On 2026-09-22 the
owner removed it from the project: board linting belongs in this plugin, not in
each repo. Its ideas should be evaluated for `skills/kanban-card-run/scripts/kanban-lint.sh`.
The verifier's tests (`tests/test_verify_kanban.py`) remain in net-watcher's git
history at commit `796fbad`.

**Worth porting (evaluate):**
- Leak scan of card text: foreign tracker IDs (`EPIC|TASK|TICKET-<n>`), absolute
  internal paths (`/home/`, `/users/`, `/workspace/`), 40-hex commit hashes.
  Matters for public boards. `kanban-lint.sh` skips `done/`, but in a public repo
  `done/` cards are published too — consider an opt-in mode that still leak-scans
  `done/` (structure checks stay active-only).
- Stage rule: `**Open questions:**` required in `grooming/`, forbidden elsewhere
  (mirrors the "never start a card from grooming/" stop condition).
- All stage directories must exist; duplicate IDs across stages are an error;
  a card must start with a `### ` title.

**Do NOT port (anti-patterns found in use):** a hardcoded per-card stage map
(`EXPECTED_STAGES`), an exact counter pin in `kanban.lock` (`NW=8`), a fixed ID
range regex (`NW-[1-8]`), a fixed dependency ceiling, a fixed printed card count.
Every card add/move needed a code edit (three times in one session). Replace
with: stage = directory, lock counter >= max existing ID, dependency references
must point to existing cards.

**Pitfall.** A repo-level disclosure scanner that forbids literal card IDs in code
forced an f-string workaround (`f"NW-{n}"`) inside the verifier — undocumented
tribal knowledge. A plugin-side linter avoids shipping card IDs in repo code.

**Open questions:**
- Opt-in flag or per-project config (e.g. in `kanban.lock`) for the public-board
  leak scan, including `done/`?
- How does a standalone public repo run the plugin linter in CI without a
  machine-specific path (vendored copy, pinned download, none)?

### Source: net-watcher `tools/verify_kanban.py` (as removed, commit `796fbad`)

```python
#!/usr/bin/env python3
import re
import sys
from pathlib import Path

try:
    from tools.verify_site import read_bounded
except ModuleNotFoundError:
    from verify_site import read_bounded

STAGES = ("grooming", "todo", "progress", "test", "ready", "done")
REQUIRED_SECTIONS = (
    "**Criticality:**",
    "**TAGS:**",
    "**Description:**",
    "**Problem:**",
    "**Impact:**",
    "**Recommendation:**",
    "**Acceptance Criteria:**",
)
EXPECTED_STAGES = {
    **{f"NW-{number}": "done" for number in (1, 2, 3, 4, 5, 7, 8)},
    **{f"NW-{number}": "grooming" for number in (6,)},
}


class KanbanError(ValueError):
    pass


def verify_board(root: Path) -> None:
    board = root / ".claude" / "kanban"
    missing_dirs = [stage for stage in STAGES if not (board / stage).is_dir()]
    if missing_dirs:
        raise KanbanError(f"missing stages: {missing_dirs}")
    lock_lines = (root / ".claude" / "kanban.lock").read_text(encoding="utf-8").splitlines()
    if lock_lines != ["prefix=NW", "NW=8"]:
        raise KanbanError("prefix or counter drift")
    seen: dict[str, str] = {}
    errors: list[str] = []
    cards = []
    for stage in STAGES:
        cards.extend((stage, path) for path in sorted((board / stage).glob("*.md")))
    for stage, path in cards:
        match = re.fullmatch(r"(NW-[1-8])-[a-z0-9]+(?:-[a-z0-9]+)*\.md", path.name)
        if not match:
            errors.append(f"invalid filename: {path.name}")
            continue
        card_id = match.group(1)
        if card_id in seen:
            errors.append(f"duplicate identifier: {card_id}")
        seen[card_id] = stage
        if EXPECTED_STAGES[card_id] != stage:
            errors.append(f"wrong stage for {card_id}")
        text = read_bounded(path)
        if not text.startswith("### "):
            errors.append(f"missing title: {card_id}")
        for section in REQUIRED_SECTIONS:
            if section not in text:
                errors.append(f"missing required section in {card_id}: {section}")
        if stage == "grooming" and "**Open questions:**" not in text:
            errors.append(f"missing open questions: {card_id}")
        if stage != "grooming" and "**Open questions:**" in text:
            errors.append(f"open questions outside grooming: {card_id}")
        foreign = re.search(r"\b(?:EPIC|TASK|TICKET|MYIP|ARIN)[-_ ]?\d+\b", text, re.IGNORECASE)
        if foreign:
            errors.append(f"foreign identifier in {card_id}")
        if re.search(r"/(?:home|users|workspace)/", text, re.IGNORECASE):
            errors.append(f"internal path in {card_id}")
        if re.search(r"\b[0-9a-f]{40}\b", text, re.IGNORECASE):
            errors.append(f"commit identifier in {card_id}")
        for dependency in re.findall(r"\bNW-(\d+)\b", text, re.IGNORECASE):
            if not 1 <= int(dependency) <= 8:
                errors.append(f"invalid dependency in {card_id}")
    if set(seen) != set(EXPECTED_STAGES):
        errors.append(f"card set mismatch: {sorted(seen)}")
    if errors:
        raise KanbanError("; ".join(errors))


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    try:
        verify_board(root)
    except (KanbanError, ValueError) as error:
        print(f"kanban verification failed: {error}", file=sys.stderr)
        return 1
    print("kanban verification passed: 8 cards")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```
