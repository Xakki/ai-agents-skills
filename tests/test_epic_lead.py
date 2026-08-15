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
        assert f"`ai-agents-skills:{skill}`" in text


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


def test_epic_lead_keeps_the_archive_branch_and_canonical_finalization_order() -> None:
    text = _skill_text()
    archive_documents = (
        KANBAN / "SKILL.md",
        KANBAN / "reference.md",
        SKILL,
    )

    for path in archive_documents:
        document = path.read_text(encoding="utf-8").lower()
        assert "git branch -m epic/<id> done/<id>" in document
        assert "do not delete" in document or "never delete" in document

    ordered_steps = (
        "move the parent EPIC `ready → done`",
        "Verify `epic/<ID>` is clean.",
        "Only then perform one local squash merge",
        "Rename the archive branch, do not delete it:",
    )
    positions = [text.index(step) for step in ordered_steps]
    assert positions == sorted(positions)


def test_epic_lead_uses_only_the_canonical_agent_commit_trailer() -> None:
    text = _skill_text()

    assert re.search(r"`Agent: <zone>` is\s+the only commit trailer", text)
    assert "never add that evidence as Git trailers" in text
    for trailer in ("`Epic:`", "`Card:`", "`Agent-Profile:`", "`Agent-Session:`", "`Prompt-SHA256:`"):
        assert trailer not in text


def test_autonomous_authorization_remains_limited_to_its_epic_scope() -> None:
    documents = _authorization_documents()

    for path in (KANBAN / "SKILL.md", KANBAN / "reference.md", SKILL):
        text = _compact(documents[path])
        assert "push" in text, path
        assert re.search(r"later[- ]EPIC", text), path
        assert "scope expansion" in text, path
        assert re.search(r"tests?/review", text), path
    assert "named EPIC and approved children" in _compact(documents[SKILL])
