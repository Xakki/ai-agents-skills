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
