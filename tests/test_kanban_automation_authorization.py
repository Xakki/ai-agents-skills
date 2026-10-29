"""Offline contracts for scoped Kanban automation authorization."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


PROMPT_START = b"PROMPT=$(cat <<PROMPT_EOF\n"
PROMPT_END = b"\nPROMPT_EOF\n)"


def _prompt_bounds(source: bytes) -> tuple[int, int]:
    start = source.index(PROMPT_START) + len(PROMPT_START)
    end = source.index(PROMPT_END, start)
    return start, end


def _prompt(source: bytes) -> bytes:
    start, end = _prompt_bounds(source)
    return source[start:end]


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
    assert "do not amend or rewrite history without the necessary authorization" in git_flow
    assert "authorization for each effect" in git_flow
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


def test_scheduler_prompt_requires_action_scoped_authorization_and_preservation() -> None:
    source = (ROOT / "scripts/run-claude-task-inner.sh").read_bytes()
    prompt = _prompt(source).decode().lower()
    assert "manifest is an integrity-checked record" in prompt
    assert "not independent proof of user consent" in prompt
    assert "explicit user approval for" in prompt and "done" in prompt
    assert "merge, push, deploy" in prompt
    assert "inspect the entire index" in prompt
    assert "do not commit unrelated staged content" in prompt
    assert "native security/approval refusal is not consent" in prompt
    assert "do not send notifications unless specifically authorized" in prompt
    assert "--dangerously-skip-permissions" not in source.decode()


def test_scheduler_scope_is_validated_and_automatic_git_actions_are_disabled() -> None:
    source_bytes = (ROOT / "scripts/run-claude-task-inner.sh").read_bytes()
    source = source_bytes.decode().lower()
    prompt = _prompt(source_bytes).decode().lower()
    assert 'task_scope_load "$repo" "$log_dir" "$scope_id"' in source
    assert 'task_scope_contains "$task_basename"' in source
    assert 'task_scope_card_is_todo "$repo" "$task_file"' in source
    assert 'automatic staging and commit disabled' in source
    assert 'task_usage_read_only=1' in source
    assert 'atrm ' not in source
    assert 'git commit -m' not in source
    assert 'do not enqueue further tasks directly' in prompt
    park = (ROOT / 'scripts/park-task.sh').read_text().lower()
    assert 'schedule_scope_id' in park and 'task_scope_contains' in park
    assert 'git switch' not in park and 'git add' not in park and 'git commit' not in park
    assert 'never run park-task-clean.sh' in prompt
    clean = (ROOT / 'scripts/park_task_clean.py').read_text()
    assert 'SCHEDULE_SCOPE_ID' in clean and '--plan-sha256' in clean
    impl = (ROOT / 'scripts/park_task.py').read_text().lower()
    assert 'git_index_file' in impl and 'commit-tree' in impl
    for forbidden in ('"switch"', '"checkout"', '"stash"', '"reset"', '"clean"', '"commit"', '"restore"', '"rm"'):
        assert forbidden not in impl


def test_scheduler_resolves_board_via_scope_interface() -> None:
    source_bytes = (ROOT / "scripts/run-claude-task-inner.sh").read_bytes()
    source = source_bytes.decode().lower()
    prompt = _prompt(source_bytes).decode().lower()
    assert 'task_scope_todo_dir "$repo"' in source
    assert '${board_dir}' in prompt
    assert '.claude/kanban' not in prompt
    assert 'the actual board helper' in prompt
