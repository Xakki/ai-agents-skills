"""Static regression contracts for the governed EPIC workflow."""

from __future__ import annotations

import re
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
KANBAN = ROOT / "skills" / "kanban"
SKILL = ROOT / "skills" / "epic-lead" / "SKILL.md"
CANONICAL_AUTHORIZATION_FORMS = (
    "explicit user approval at hand-off",
    "recorded EPIC-scoped upfront autonomous authorization",
    "recorded profile/agent authorization",
)


def _skill_text() -> str:
    return SKILL.read_text(encoding="utf-8")


def _authorization_documents() -> dict[Path, str]:
    paths = (
        KANBAN / "SKILL.md",
        KANBAN / "reference.md",
        KANBAN / "scripts.md",
        KANBAN / "task-template.md",
        SKILL,
    )
    return {path: path.read_text(encoding="utf-8") for path in paths}


def _compact(text: str) -> str:
    return " ".join(text.split())


def test_epic_lead_has_valid_frontmatter_and_canonical_workflow_links() -> None:
    text = _skill_text()
    frontmatter = yaml.safe_load(text.split("---", 2)[1])

    assert frontmatter["name"] == "epic-lead"
    assert frontmatter["description"]
    for skill in ("kanban", "git-flow", "teamlead"):
        assert f"../{skill}/SKILL.md" in text


def test_authorization_forms_are_consistent_across_the_kanban_contract() -> None:
    documents = _authorization_documents()

    for path, text in documents.items():
        assert "***" not in text, path
        for form in CANONICAL_AUTHORIZATION_FORMS:
            assert form in _compact(text), (path, form)


def test_scripts_document_approved_as_caller_attestation_only() -> None:
    text = (KANBAN / "scripts.md").read_text(encoding="utf-8")
    compact = _compact(text)

    assert "`--approved`, which is a caller attestation" in compact
    assert "checks only that the flag is present" in compact
    assert "does not validate authorization evidence" in compact
    for form in CANONICAL_AUTHORIZATION_FORMS:
        assert form in compact


def test_epic_lead_preserves_per_action_authority_and_applicable_order() -> None:
    text = _compact(_skill_text()).lower()
    assert "each action's valid authorization" in text
    assert "parent-before-child" in text
    assert "if the user or project requires explicit confirmation for `done`" in text
    assert "branch merge, archive or deletion only when" in text
    assert "preserve unrelated work" in text


def test_epic_lead_uses_runtime_and_project_policy_without_forced_model_or_trailer() -> None:
    text = _compact(_skill_text()).lower()
    assert "runtime capabilities" in text
    assert "inherited defaults" in text
    assert "perform authorized implementation directly" in text
    assert "if a required role is unavailable" in text
    assert "do not assume a branch name, model, trailer or global clean worktree" in text
    assert "never add evidence as git trailers by default" in text
    assert "ask the user one question" not in text
    assert "the only commit trailer" not in text


def test_autonomous_authorization_remains_limited_to_its_epic_scope() -> None:
    documents = _authorization_documents()

    for path in (KANBAN / "SKILL.md", KANBAN / "reference.md", SKILL):
        text = _compact(documents[path])
        assert "push" in text, path
        assert re.search(r"later[- ]EPIC", text), path
        assert "scope expansion" in text, path
        assert re.search(r"tests?/review", text), path
    assert "recorded profile/agent authorization" in _compact(documents[SKILL])
    assert "A grant for one action does not imply another" in _compact(documents[SKILL])


def test_kanban_findings_and_grooming_respect_scope_and_runtime() -> None:
    body = (KANBAN / "SKILL.md").read_text(encoding="utf-8")
    reference = (KANBAN / "reference.md").read_text(encoding="utf-8")
    scripts = (KANBAN / "scripts.md").read_text(encoding="utf-8")
    text = _compact(body).lower()
    assert "small size or suitability for a subagent is not permission" in text
    assert "only when that write is in scope" in text
    assert "otherwise report the finding" in text
    assert "required authorization is missing" in text
    assert "record decisions" in text
    assert "askuserquestion" not in (body + reference + scripts).lower()
    done = text.split("### 6. done", 1)[1].split("### freeze", 1)[0]
    assert "authorization for `done` must be explicit" in done
    assert "must cover this card" in done
    assert "if `done` authorization is missing, retain `ready/`" in done
