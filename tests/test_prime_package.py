"""Contract checks for the Prime Agent capability-package adapter."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_prime_manifest_exposes_shared_resources() -> None:
    manifest = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))

    assert "pi-package" in manifest["keywords"]
    assert manifest["pi"] == {
        "extensions": ["./extensions/prime-adapter.ts"],
        "skills": ["./skills"],
        "prompts": ["./agents"],
    }


def test_prime_adapter_maps_only_supported_lifecycle_behavior() -> None:
    adapter = (ROOT / "extensions" / "prime-adapter.ts").read_text(encoding="utf-8")

    for event in (
        'pi.on("session_start"',
        'pi.on("before_agent_start"',
        'pi.on("tool_execution_start"',
        'pi.on("agent_end"',
        'pi.on("session_shutdown"',
    ):
        assert event in adapter

    for hook in (
        "abbr-inject.sh",
        "model-tiers-inject.sh",
        "tg-prompt-start.sh",
        "tg-cancel-pending.sh",
        "tg-on-stop.sh",
    ):
        assert hook in adapter

    assert "PRIME_AGENT_ROOT: root" in adapter
    assert "Notification/PermissionRequest" in adapter
