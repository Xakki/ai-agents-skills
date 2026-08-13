"""Hermes Agent entrypoint for the shared ai-agents-skills plugin."""

from __future__ import annotations

import hashlib
import importlib
import json
import logging
import os
import subprocess
from pathlib import Path
from typing import Any

_ROOT = Path(__file__).resolve().parent
_HOOKS = _ROOT / "hooks"
_LOG = logging.getLogger(__name__)


def plugin_root() -> Path:
    """Return the installed plugin root (also useful to tests and adapters)."""
    return _ROOT


def _frontmatter_description(path: Path) -> str:
    """Read the one-line description without adding a YAML dependency."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return path.parent.name
    if not lines or lines[0].strip() != "---":
        return path.stem
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.startswith("description:"):
            return line.partition(":")[2].strip().strip('"').strip("'")
    return path.stem


def _resolve_cwd() -> Path:
    """Resolve the current Hermes session cwd, falling back outside Hermes."""
    try:
        runtime_cwd = importlib.import_module("agent.runtime_cwd")
        return runtime_cwd.resolve_agent_cwd()
    except (ImportError, OSError, RuntimeError):
        return Path.cwd()


def _safe_session_id(session_id: Any) -> str:
    """Encode an opaque runtime ID as a fixed safe filename component."""
    raw = session_id if isinstance(session_id, str) and session_id else "unknown"
    digest = hashlib.sha256(raw.encode("utf-8", errors="surrogatepass")).hexdigest()
    return f"sid-{digest}"


def _run_script(name: str, payload: dict[str, Any]) -> None:
    """Run a fixed bundled hook best-effort; lifecycle hooks must never block."""
    script = _HOOKS / name
    if not script.is_file():
        _LOG.warning("ai-agents-skills hook is missing: %s", script)
        return
    env = os.environ.copy()
    env["AI_AGENTS_SKILLS_ROOT"] = str(_ROOT)
    env["HERMES_PLUGIN_ROOT"] = str(_ROOT)
    try:
        subprocess.run(
            [str(script)],
            input=json.dumps(payload, ensure_ascii=False),
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        _LOG.debug("ai-agents-skills hook %s failed: %s", name, exc)


def _abbreviations_context() -> str:
    skill = _ROOT / "skills" / "abbreviations" / "SKILL.md"
    dictionary = _ROOT / "skills" / "abbreviations" / "dictionary.tsv"
    parts = ["## Abbreviations"]
    try:
        text = skill.read_text(encoding="utf-8")
        chunks = text.split("---", 2)
        if len(chunks) == 3:
            parts.append(chunks[2].strip())
    except OSError:
        pass
    try:
        entries = []
        for line in dictionary.read_text(encoding="utf-8").splitlines():
            if line.strip() and not line.lstrip().startswith("#"):
                entries.append(line.replace("\t", " = ", 1))
        if entries:
            parts.extend(("## Dictionary (abbr = full)", "\n".join(entries)))
    except OSError:
        pass
    local_path = Path(os.environ.get("ABBR_LOCAL", "~/.config/abbr/local.tsv")).expanduser()
    try:
        local_entries = [
            line.replace("\t", " = ", 1)
            for line in local_path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        if local_entries:
            parts.extend(("## Personal abbreviations", "\n".join(local_entries)))
    except OSError:
        pass
    parts.extend(
        (
            "## ai-agents-skills for Hermes",
            "Bundled workflows are available on demand as "
            '`skill_view("ai-agents-skills:<name>")`; specialist prompts use '
            '`skill_view("ai-agents-skills:agent-<name>")`.',
            "## Agent runtime",
            "runtime = hermes\n"
            "Hermes delegate_task inherits the active model; do not pass Claude/Codex "
            "model-tier aliases as per-call model arguments.",
        )
    )
    return "\n\n".join(part for part in parts if part)


def _on_pre_llm_call(
    session_id: str = "",
    user_message: str = "",
    is_first_turn: bool = False,
    platform: str = "",
    **_: Any,
) -> dict[str, str] | None:
    _run_script(
        "tg-prompt-start.sh",
        {
            "session_id": _safe_session_id(session_id),
            "prompt": user_message,
            "cwd": str(_resolve_cwd()),
            "platform": platform,
        },
    )
    if is_first_turn:
        return {"context": _abbreviations_context()}
    return None


def _on_post_llm_call(
    session_id: str = "",
    user_message: str = "",
    assistant_response: str = "",
    platform: str = "",
    **_: Any,
) -> None:
    _run_script(
        "tg-on-stop.sh",
        {
            "session_id": _safe_session_id(session_id),
            "prompt": user_message,
            "assistant_response": assistant_response,
            "transcript_path": "",
            "cwd": str(_resolve_cwd()),
            "platform": platform,
        },
    )


def _cancel(session_id: str = "", platform: str = "") -> None:
    _run_script(
        "tg-cancel-pending.sh",
        {"session_id": _safe_session_id(session_id), "platform": platform},
    )


def _on_session_finalize(session_id: str = "", platform: str = "", **_: Any) -> None:
    _cancel(session_id, platform)


def _on_session_reset(session_id: str = "", platform: str = "", **_: Any) -> None:
    _cancel(session_id, platform)


def register(ctx: Any) -> None:
    """Register shared skills, agent prompt adapters, and compatible hooks."""
    # The installed location is authoritative. An inherited value may point to
    # another checkout or an older plugin version and must not redirect bundled
    # skill commands away from the code Hermes actually loaded.
    os.environ["AI_AGENTS_SKILLS_ROOT"] = str(_ROOT)

    for skill_md in sorted((_ROOT / "skills").glob("*/SKILL.md")):
        name = skill_md.parent.name
        ctx.register_skill(
            name,
            skill_md,
            description=_frontmatter_description(skill_md),
            expose_as_command=True,
            command_name="ai-kanban" if name == "kanban" else name,
        )
    for agent_md in sorted((_ROOT / "agents").glob("*.md")):
        ctx.register_skill(
            f"agent-{agent_md.stem}",
            agent_md,
            description=_frontmatter_description(agent_md),
        )

    ctx.register_hook("pre_llm_call", _on_pre_llm_call)
    ctx.register_hook("post_llm_call", _on_post_llm_call)
    ctx.register_hook("on_session_finalize", _on_session_finalize)
    ctx.register_hook("on_session_reset", _on_session_reset)
