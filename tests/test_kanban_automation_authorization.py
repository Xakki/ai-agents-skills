"""Offline contracts for scoped Kanban automation authorization."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


PROMPT_START = b"PROMPT=$(cat <<PROMPT_EOF\n"
PROMPT_END = b"\nPROMPT_EOF\n)"
BASELINE_OUTSIDE_PROMPT_SHA256 = "74d10cab658b01d04e3fdcd09726ce020d278fe118059cac858efa09720d06b0"


def _prompt_bounds(source: bytes) -> tuple[int, int]:
    start = source.index(PROMPT_START) + len(PROMPT_START)
    end = source.index(PROMPT_END, start)
    return start, end


def _prompt(source: bytes) -> bytes:
    start, end = _prompt_bounds(source)
    return source[start:end]


def _outside_prompt_sha256(source: bytes) -> str:
    start, end = _prompt_bounds(source)
    outside = source[:start] + b"\0<PROMPT>\0" + source[end + len(PROMPT_END) :]
    return hashlib.sha256(outside).hexdigest()


def test_all_action_scopes_allow_automation_on_valid_profile_authorization() -> None:
    docs = [
        _read(ROOT / "skills/kanban/SKILL.md"),
        _read(ROOT / "skills/kanban/reference.md"),
        _read(ROOT / "skills/epic-lead/SKILL.md"),
        _read(ROOT / "skills/schedule-tasks/SKILL.md"),
        _read(ROOT / "skills/schedule-tasks/lifecycle.md"),
    ]
    docs.append(_read(ROOT / "skills/qa-check/SKILL.md"))
    docs.append(_prompt((ROOT / "scripts/run-claude-task-inner.sh").read_bytes()).decode())
    policy = " ".join(docs)
    for action in ("done", "merge", "push", "deploy"):
        assert re.search(rf"{action}.{{0,180}}(?:automatically|automation)", policy, re.I)
    assert "each action independently" in policy.lower()
    assert "profile/agent authorization" in policy.lower()
    assert "explicit user approval" in policy.lower()
    assert "recorded upfront" in policy.lower()
    assert "do not request another user confirmation" in " ".join(policy.split()).lower()


def test_ready_is_checkpoint_not_automatic_stop_and_authority_is_action_scoped() -> None:
    policy_docs = [
        ROOT / "skills/kanban/SKILL.md",
        ROOT / "skills/kanban/reference.md",
        ROOT / "skills/epic-lead/SKILL.md",
        ROOT / "skills/schedule-tasks/SKILL.md",
        ROOT / "skills/schedule-tasks/lifecycle.md",
    ]
    policy = " ".join(_read(path) for path in policy_docs).lower()
    prompt = _prompt((ROOT / "scripts/run-claude-task-inner.sh").read_bytes()).decode().lower()
    combined = policy + prompt

    assert "not a compulsory human stop" in combined
    assert "profile name" in combined and "credentials" in combined
    assert "stage transition alone" in combined
    assert "action-specific" in combined
    assert "record its source" in combined
    assert "valid authorization" in combined or "valid grant" in combined
    for obsolete in (
        "never advance past `ready`",
        "final hop `ready → done` is the user's manual step",
        "do not push without separate user approval",
        "ready→done` is **user-only**",
        "card in `done/` — only the user",
    ):
        assert obsolete not in combined


def test_authorization_forms_and_gates_are_consistent() -> None:
    docs = [
        ROOT / "skills/kanban/SKILL.md",
        ROOT / "skills/kanban/reference.md",
        ROOT / "skills/kanban/scripts.md",
        ROOT / "skills/kanban/task-template.md",
        ROOT / "skills/epic-lead/SKILL.md",
    ]
    for path in docs:
        text = _read(path).lower()
        assert "profile/agent authorization" in text, path
    kanban = _read(docs[0]).lower()
    reference = _read(docs[1]).lower()
    scripts = _read(docs[2]).lower()
    epic = _read(docs[4]).lower()
    git_flow = _read(ROOT / "skills/git-flow/SKILL.md").lower()
    assert "profile name" in kanban and "green tests" in kanban
    assert "not a grant" in kanban
    assert "checks only that the flag is present" in scripts
    assert "does not validate authorization evidence" in " ".join(scripts.split())
    assert "it is not an\n    authorization grant" in scripts
    assert "parent `ready → done`, eligible subtasks to `done`, verify `epic/<id>` clean" in reference
    assert "never force-push" in git_flow
    assert "review" in epic and "full project quality gate" in epic
    assert "read back the exact target" in kanban


def test_helper_diagnostic_lists_all_authorization_sources_without_changing_gates() -> None:
    helper = _read(ROOT / "skills/kanban/scripts/kanban-move.sh").lower()
    normalized = " ".join(helper.split())

    assert "requires --approved" in normalized
    assert "explicit current user approval" in normalized
    assert "recorded upfront task/epic/workflow authorization" in normalized
    assert "recorded profile/agent authorization" in normalized
    assert 'kanban::die "kanban-move.sh: moving to done/' in normalized
    assert "if [ \"$to_stage\" = done ] && [ \"$approved\" -ne 1 ]; then" in normalized
    assert 'if [ "$to_stage" = done ] && [ "$is_subtask" -eq 1 ]; then' in normalized
    assert 'all mandatory gates remain binding)" 2' in normalized


def test_scheduler_prompt_keeps_execution_outside_prompt_unchanged_by_contract() -> None:
    source = (ROOT / "scripts/run-claude-task-inner.sh").read_bytes()
    prompt = _prompt(source).decode()
    assert _outside_prompt_sha256(source) == BASELINE_OUTSIDE_PROMPT_SHA256

    assert "AUTO-RUN-RESULT: <ok|park|skip>" in prompt
    assert "--approved" in prompt
    assert "MERGE_HEAD" in prompt
    assert "git merge --abort" in prompt
    assert "does not exist, the merge did not start: do not run abort" in prompt.lower()
    assert "git diff --cached --check" in prompt
    assert "only after this successful verified authorized merge" in prompt
    assert "safely run" in prompt and "before step 9" in prompt
    assert "ready/done" in prompt and "canonical base still has its pre-merge state" in prompt
    assert "whenever merge cannot proceed because" in prompt.lower()
    assert "retain" in prompt.lower() and "do not archive it" in prompt.lower()
    assert r'kanban_move="\${kanban_root}/skills/kanban/scripts/kanban-move.sh"' in prompt.lower()
    assert r'"\${kanban_move}"' in prompt.lower()
    for root_var in ("AI_AGENTS_SKILLS_ROOT", "CLAUDE_PLUGIN_ROOT", "PLUGIN_ROOT", "CURSOR_PLUGIN_ROOT"):
        assert root_var in prompt
    assert "never use a bare" in prompt.lower() and "kanban-move.sh" in prompt
    assert "not a compulsory human stop" in prompt
    assert "after any actual authorized push, read back the exact remote target/ref" in prompt.lower()
    assert "after any actual authorized deploy, read back the exact deployment target" in prompt.lower()
