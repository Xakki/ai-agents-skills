"""Offline behavioral checks for Telegram lifecycle hooks; no network or real credentials."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
HOOKS = ("tg-prompt-start.sh", "tg-on-stop.sh", "tg-on-notification.sh", "tg-cancel-pending.sh")


class TelegramHooks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tg-hook-test-")
        self.root = Path(self.temp.name)
        self.hooks = self.root / "hooks"
        self.skill = self.root / "hooks" / "telegram"
        self.hooks.mkdir()
        self.skill.mkdir(parents=True)
        for name in HOOKS:
            shutil.copy2(ROOT / "hooks" / name, self.hooks / name)
        shutil.copy2(ROOT / "hooks" / "cursor-adapter.sh", self.hooks / "cursor-adapter.sh")
        for name in ("runtime.sh", "context-header.sh"):
            shutil.copy2(ROOT / "hooks" / "telegram" / name, self.skill / name)
        fake_sender = self.skill / "agent-telegram-notify.sh"
        fake_sender.write_text('#!/usr/bin/env bash\ncat > "$TEST_RESULT"\n', encoding="utf-8")
        fake_sender.chmod(0o700)
        self.state = self.root / "state-home"
        self.result = self.root / "fake-sender-output"
        self.env = {
            "PATH": "/usr/bin:/bin",
            "HOME": str(self.root),
            "LANG": "C.UTF-8",
            "TG_NOTIFY_HOME": str(self.state),
            "TG_NOTIFY_STOP_THRESHOLD": "1",
            "TG_NOTIFY_STOP_DELAY": "0",
            "TG_NOTIFY_STOP_DEBOUNCE": "1",
            "TEST_RESULT": str(self.result),
        }

    def tearDown(self):
        self.temp.cleanup()

    def call(self, name, payload, *, env=None):
        result = subprocess.run(
            ["bash", str(self.hooks / name)], input=json.dumps(payload),
            text=True, capture_output=True, cwd=self.root,
            env={**self.env, **(env or {})}, timeout=8,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_disabled_hooks_do_not_read_input_or_modify_state(self):
        existing = self.state / "pending" / "session" / "existing.payload"
        existing.parent.mkdir(parents=True)
        existing.write_text("synthetic pending", encoding="utf-8")
        for value in ("0", "false", "FALSE", "no", "off"):
            for name in HOOKS:
                with self.subTest(value=value, hook=name):
                    self.call(name, {"session_id": "session", "prompt": "synthetic"}, env={"TG_NOTIFY_ENABLED": value})
                    self.assertEqual(existing.read_text(encoding="utf-8"), "synthetic pending")
                    self.assertFalse(self.result.exists())
                    self.assertEqual(sorted(p.relative_to(self.state) for p in self.state.rglob("*")), [Path("pending"), Path("pending/session"), Path("pending/session/existing.payload")])

    def test_disabled_hooks_do_not_create_state(self):
        for name in HOOKS:
            self.call(name, {"session_id": "session"}, env={"TG_NOTIFY_ENABLED": "false"})
            self.assertFalse(self.state.exists())

    def test_cursor_adapter_respects_disabled_hooks(self):
        result = subprocess.run(["bash", str(self.hooks / "cursor-adapter.sh"), "tg-prompt-start.sh"],
                                input=json.dumps({"conversation_id": "session", "prompt": "synthetic"}),
                                text=True, capture_output=True, cwd=self.root,
                                env={**self.env, "TG_NOTIFY_ENABLED": "false"}, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.state.exists())

    def test_start_preserves_empty_and_truncated_unicode_prompts(self):
        self.call("tg-prompt-start.sh", {"session_id": "empty", "prompt": ""})
        empty = json.loads((self.state / "state" / "empty.start").read_text(encoding="utf-8"))
        self.assertEqual(empty["prompt"], "")
        self.call("tg-prompt-start.sh", {"session_id": "unicode", "prompt": "ё" * 510 + "\n" + "я" * 10})
        data = json.loads((self.state / "state" / "unicode.start").read_text(encoding="utf-8"))
        self.assertEqual(data["prompt"], "ё" * 510 + " " + "я")

    def test_synthetic_prompt_and_answer_are_not_in_parser_argv(self):
        wrappers = self.root / "bin"
        wrappers.mkdir()
        argv_log = self.root / "argv.log"
        for name in ("python3", "jq"):
            wrapper = wrappers / name
            wrapper.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$@" >> "$TEST_ARGV"\nexec /usr/bin/' + name + ' "$@"\n', encoding="utf-8")
            wrapper.chmod(0o700)
        self.env["PATH"] = str(wrappers) + ":/usr/bin:/bin"
        self.env["TEST_ARGV"] = str(argv_log)
        self.call("tg-prompt-start.sh", {"session_id": "session", "prompt": "synthetic-prompt-sentinel"})
        start = self.state / "state" / "session.start"
        saved = json.loads(start.read_text(encoding="utf-8"))
        saved["started_at"] = int(time.time()) - 10
        start.write_text(json.dumps(saved), encoding="utf-8")
        self.call("tg-on-stop.sh", {"session_id": "session", "cwd": str(self.root), "last_assistant_message": "synthetic-answer-sentinel"})
        deadline = time.monotonic() + 6
        while not self.result.exists() and time.monotonic() < deadline:
            time.sleep(0.025)
        self.assertTrue(self.result.exists())
        recorded = argv_log.read_text(encoding="utf-8")
        self.assertNotIn("synthetic-prompt-sentinel", recorded)
        self.assertNotIn("synthetic-answer-sentinel", recorded)

    def run_stop(self, data):
        self.call("tg-prompt-start.sh", {"session_id": "session", "prompt": "synthetic prompt"})
        start = self.state / "state" / "session.start"
        saved = json.loads(start.read_text(encoding="utf-8"))
        saved["started_at"] = int(time.time()) - 10
        start.write_text(json.dumps(saved), encoding="utf-8")
        self.call("tg-on-stop.sh", {"session_id": "session", "cwd": str(self.root), **data})
        deadline = time.monotonic() + 6
        while not self.result.exists() and time.monotonic() < deadline:
            time.sleep(0.025)
        self.assertTrue(self.result.exists(), "fake sender was not invoked")
        return self.result.read_text(encoding="utf-8")

    def test_codex_event_prefers_last_assistant_message_over_transcript(self):
        transcript = self.root / "synthetic.jsonl"
        transcript.write_text(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "old transcript"}]}}) + "\n", encoding="utf-8")
        result = self.run_stop({"last_assistant_message": "codex result", "assistant_response": "other response", "transcript_path": str(transcript)})
        self.assertIn("synthetic prompt", result)
        self.assertIn("codex result", result)
        self.assertNotIn("old transcript", result)
        self.assertNotIn("other response", result)

    def test_hermes_direct_response_without_codex_field(self):
        self.assertIn("hermes result", self.run_stop({"assistant_response": "hermes result"}))

    def test_claude_transcript_without_codex_field(self):
        transcript = self.root / "synthetic.jsonl"
        transcript.write_text(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "claude result"}]}}) + "\n", encoding="utf-8")
        self.assertIn("claude result", self.run_stop({"transcript_path": str(transcript)}))


if __name__ == "__main__":
    unittest.main()
