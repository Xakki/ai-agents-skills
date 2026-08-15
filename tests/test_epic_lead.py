"""Static regression contracts for the governed EPIC workflow."""

from __future__ import annotations

import re
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "epic-lead" / "SKILL.md"


def _skill_text() -> str:
    return SKILL.read_text(encoding="utf-8")


def test_epic_lead_has_valid_frontmatter_and_canonical_workflow_links() -> None:
    text = _skill_text()
    frontmatter = yaml.safe_load(text.split("---", 2)[1])

    assert frontmatter["name"] == "epic-lead"
    assert frontmatter["description"]
    for skill in ("kanban", "git-flow", "teamlead"):
        assert f"`ai-agents-skills:{skill}`" in text


def test_epic_lead_keeps_the_archive_branch_and_uses_canonical_rename() -> None:
    text = _skill_text()

    assert "Rename the archive branch, do not delete it:" in text
    assert "`git branch -m epic/<ID> done/<ID>`." in text
    assert "branch deletion" in text


def test_epic_lead_uses_only_the_canonical_agent_commit_trailer() -> None:
    text = _skill_text()

    assert re.search(r"`Agent: <zone>` is\s+the only commit trailer", text)
    assert "never add that evidence as Git trailers" in text
    for trailer in ("`Epic:`", "`Card:`", "`Agent-Profile:`", "`Agent-Session:`", "`Prompt-SHA256:`"):
        assert trailer not in text


def test_epic_lead_limits_autonomous_authorization_to_the_approved_epic() -> None:
    text = _skill_text()

    assert "explicit, recorded, EPIC-scoped upfront autonomous authorization" in text
    assert "only to the named EPIC and approved children" in text
    for forbidden_power in (
        "push",
        "later-EPIC startup",
        "scope expansion",
        "test/review bypass",
    ):
        assert forbidden_power in text


def test_epic_lead_represents_one_canonical_finalization_lifecycle() -> None:
    text = _skill_text()
    ordered_steps = (
        "move the parent EPIC `ready → done`",
        "Verify `epic/<ID>` is clean.",
        "Only then perform one local squash merge",
        "Rename the archive branch, do not delete it:",
    )

    positions = [text.index(step) for step in ordered_steps]
    assert positions == sorted(positions)
    assert text.count("`ready → done`") == 1
    assert text.count("one local squash merge") == 1
    assert text.count("git branch -m epic/<ID> done/<ID>") == 1
