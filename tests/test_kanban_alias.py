"""Cross-runtime contract for the ``knbn`` Kanban skill alias."""

from __future__ import annotations

from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


def test_knbn_is_a_real_portable_skill_alias_not_a_symlink() -> None:
    """Every integration discovers skill directories, but not all follow links."""
    canonical = ROOT / "skills" / "kanban" / "SKILL.md"
    alias_dir = ROOT / "skills" / "knbn"
    alias = alias_dir / "SKILL.md"

    assert canonical.is_file()
    assert alias_dir.is_dir()
    assert not alias_dir.is_symlink()
    assert alias.is_file()
    assert not alias.is_symlink()

    frontmatter = yaml.safe_load(alias.read_text(encoding="utf-8").split("---", 2)[1])
    assert frontmatter["name"] == "knbn"
    assert "alias" in frontmatter["description"].lower()
    assert "kanban" in alias.read_text(encoding="utf-8").lower()


def test_knbn_alias_instructions_cover_all_plugin_integrations() -> None:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")

    assert "`knbn`" in readme
    for runtime in ("Claude", "Codex", "Cursor", "Hermes", "Prime"):
        assert runtime in readme


def test_ready_handoff_requires_verified_local_commit_without_permission_gate() -> None:
    text = (ROOT / "skills" / "kanban" / "SKILL.md").read_text(encoding="utf-8")
    ready = text.split("### 5. Ready (test → ready)", 1)[1].split("### 6. Done", 1)[0]
    commits = text.split("## Git Commits", 1)[1].split("## Stop Conditions", 1)[0]

    assert "without a\nseparate permission request" in ready
    assert "Verify the commit SHA, message, committed paths and\nreviewed bytes" in ready
    assert "does not authorize\n`done`, merge, push, or deployment" in ready
    assert "Commit coherent, validated progress proactively" in commits
    assert "Do not create an empty or redundant commit" in commits


def test_knbn_alias_delegates_commit_policy_to_canonical_kanban() -> None:
    alias = (ROOT / "skills" / "knbn" / "SKILL.md").read_text(encoding="utf-8")

    assert "Load and follow the canonical [kanban skill]" in alias
    assert "adds no behavior" in alias
