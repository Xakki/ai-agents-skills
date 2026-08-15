from __future__ import annotations

import hashlib
import importlib.util
import os
import subprocess
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


class FakeContext:
    def __init__(self):
        self.skills = {}
        self.hooks = {}

    def register_skill(self, name, path, description="", frontmatter=None):
        self.skills[name] = {
            "path": Path(path),
            "description": description,
            "frontmatter": dict(frontmatter or {}),
        }

    def register_hook(self, name, callback):
        self.hooks[name] = callback


def _load_plugin_module():
    init_py = ROOT / "__init__.py"
    assert init_py.is_file(), "Hermes plugin entrypoint is missing"
    spec = importlib.util.spec_from_file_location("ai_agents_skills_hermes", init_py)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_hermes_manifest_matches_shared_plugin_version():
    manifest = yaml.safe_load((ROOT / "plugin.yaml").read_text())
    json_module = __import__("json")
    shared_manifests = [
        json_module.loads((ROOT / directory / "plugin.json").read_text())
        for directory in (".claude-plugin", ".codex-plugin", ".cursor-plugin")
    ]

    assert manifest["name"] == "ai-agents-skills"
    assert len({manifest["version"], *(item["version"] for item in shared_manifests)}) == 1
    assert manifest["provides_hooks"] == [
        "pre_llm_call",
        "post_llm_call",
        "on_session_finalize",
        "on_session_reset",
    ]


def test_register_exposes_all_shared_skills_and_agent_adapters(monkeypatch):
    module = _load_plugin_module()
    ctx = FakeContext()
    monkeypatch.setenv("AI_AGENTS_SKILLS_ROOT", "/stale/plugin/root")

    module.register(ctx)

    expected_skills = {path.parent.name for path in (ROOT / "skills").glob("*/SKILL.md")}
    expected_agents = {f"agent-{path.stem}" for path in (ROOT / "agents").glob("*.md")}
    assert set(ctx.skills) == expected_skills | expected_agents
    assert all(item["path"].is_file() for item in ctx.skills.values())
    assert all(item["description"] for item in ctx.skills.values())
    assert "epic-lead" in ctx.skills
    assert "expose_as_command" not in ctx.skills["kanban"]["frontmatter"]
    assert "command_name" not in ctx.skills["kanban"]["frontmatter"]
    assert set(ctx.hooks) == {
        "pre_llm_call",
        "post_llm_call",
        "on_session_finalize",
        "on_session_reset",
    }
    assert module.plugin_root() == ROOT
    assert os.environ["AI_AGENTS_SKILLS_ROOT"] == str(ROOT)


def test_model_tier_runtime_prefers_specific_runtime_markers():
    script = ROOT / "hooks" / "model-tiers-inject.sh"
    markers = {
        "CLAUDE_PLUGIN_ROOT": "claude",
        "PLUGIN_ROOT": "codex",
        "CURSOR_PLUGIN_ROOT": "cursor",
        "HERMES_PLUGIN_ROOT": "hermes",
    }
    for marker, expected in markers.items():
        env = {
            key: value
            for key, value in os.environ.items()
            if key
            not in {
                "CLAUDE_PLUGIN_ROOT",
                "PLUGIN_ROOT",
                "CURSOR_PLUGIN_ROOT",
                "HERMES_PLUGIN_ROOT",
                "AI_AGENTS_SKILLS_ROOT",
            }
        }
        env[marker] = str(ROOT)
        env["AI_AGENTS_SKILLS_ROOT"] = "/portable/root/override"
        output = subprocess.run(
            [str(script)],
            input="{}",
            text=True,
            capture_output=True,
            env=env,
            check=True,
        ).stdout
        context = yaml.safe_load(output)["hookSpecificOutput"]["additionalContext"]
        assert f"runtime = {expected}" in context


def test_kanban_linked_docs_use_portable_plugin_root():
    scripts_doc = (ROOT / "skills" / "kanban" / "scripts.md").read_text()
    assert "${CLAUDE_PLUGIN_ROOT}" not in scripts_doc
    assert "AI_AGENTS_SKILLS_ROOT" in scripts_doc


def test_pre_llm_hook_records_prompt_and_injects_first_turn_context(monkeypatch):
    module = _load_plugin_module()
    calls = []
    monkeypatch.setattr(module, "_run_script", lambda name, payload: calls.append((name, payload)))
    monkeypatch.setattr(module, "_resolve_cwd", lambda: Path("/tmp/project"))

    result = module._on_pre_llm_call(
        session_id="session-1",
        user_message="build it",
        is_first_turn=True,
        model="test-model",
        platform="cli",
    )

    safe_id = "sid-" + hashlib.sha256(b"session-1").hexdigest()
    assert calls == [
        (
            "tg-prompt-start.sh",
            {
                "session_id": safe_id,
                "prompt": "build it",
                "cwd": "/tmp/project",
                "platform": "cli",
            },
        )
    ]
    assert result is not None
    assert "Abbreviations" in result["context"]
    assert "runtime = hermes" in result["context"]


def test_post_llm_hook_passes_response_without_transcript(monkeypatch):
    module = _load_plugin_module()
    calls = []
    monkeypatch.setattr(module, "_run_script", lambda name, payload: calls.append((name, payload)))
    monkeypatch.setattr(module, "_resolve_cwd", lambda: Path("/tmp/project"))

    module._on_post_llm_call(
        session_id="session-1",
        user_message="build it",
        assistant_response="done",
        model="test-model",
        platform="telegram",
    )

    safe_id = "sid-" + hashlib.sha256(b"session-1").hexdigest()
    assert calls == [
        (
            "tg-on-stop.sh",
            {
                "session_id": safe_id,
                "prompt": "build it",
                "assistant_response": "done",
                "transcript_path": "",
                "cwd": "/tmp/project",
                "platform": "telegram",
            },
        )
    ]


def test_finalize_and_reset_cancel_pending_notification(monkeypatch):
    module = _load_plugin_module()
    calls = []
    monkeypatch.setattr(module, "_run_script", lambda name, payload: calls.append((name, payload)))

    module._on_session_finalize(session_id="one", platform="cli")
    module._on_session_reset(session_id="two", platform="telegram")

    assert calls == [
        (
            "tg-cancel-pending.sh",
            {
                "session_id": "sid-" + hashlib.sha256(b"one").hexdigest(),
                "platform": "cli",
            },
        ),
        (
            "tg-cancel-pending.sh",
            {
                "session_id": "sid-" + hashlib.sha256(b"two").hexdigest(),
                "platform": "telegram",
            },
        ),
    ]


def test_unsafe_session_ids_are_encoded_before_real_shell_hook(monkeypatch, tmp_path):
    module = _load_plugin_module()
    state_home = tmp_path / "tg-state"
    monkeypatch.setenv("TG_NOTIFY_HOME", str(state_home))

    unsafe_ids = ["../../escape", "quote'break", "has spaces", "line\nbreak", "ctrl\x01"]
    encoded = []
    for raw in unsafe_ids:
        safe = module._safe_session_id(raw)
        encoded.append(safe)
        assert safe == "sid-" + hashlib.sha256(raw.encode("utf-8")).hexdigest()
        module._on_pre_llm_call(
            session_id=raw,
            user_message="verify",
            is_first_turn=False,
            platform="cli",
        )
        assert (state_home / "state" / f"{safe}.start").is_file()

    assert len(set(encoded)) == len(unsafe_ids)
    assert not (tmp_path / "escape.start").exists()
