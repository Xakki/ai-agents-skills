#!/usr/bin/env bash
# Tests for hooks/cursor-adapter.sh — the Cursor payload normalizer that lets
# the shared tg-*.sh / abbr-inject.sh scripts run unmodified under Cursor.
# See docs/superpowers/specs/2026-07-31-cursor-plugin-design.md ("Hook
# adapter design") for the field-mapping contract this test enforces.
#
# Test isolation: any test that exercises tg-on-stop.sh (which schedules a
# real, detached `setsid` background job) MUST run through a *sandboxed*
# TG_SKILL_DIR, not just an exported TG_SENDER. skills/tg-notify/runtime.sh
# derives TG_SENDER from its OWN script location
# (`TG_SENDER="$TG_SKILL_DIR/tg-notify.sh"`, unconditional assignment, not
# `${TG_SENDER:-...}`) every time it is sourced, so an exported TG_SENDER is
# silently clobbered and the REAL tg-notify.sh's executable bit is what gets
# checked. Fix: invoke the target script through a throwaway directory tree
# that mirrors hooks/ + skills/tg-notify/ via symlinks, with tg-notify.sh
# itself replaced by a local stub — this changes no shared script (runtime.sh
# is off-limits per AGENTS.md/plan) and is a pure test-side injection.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HERE/.."
REPO_ROOT="$HOOKS_DIR/.."
ADAPTER="$HOOKS_DIR/cursor-adapter.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

[ -x "$ADAPTER" ] || fail "hooks/cursor-adapter.sh missing or not executable"

# ---------------------------------------------------------------------------
# 0. Regression: missing/empty workspace_roots must not collapse the whole
#    normalized object to zero jq output. jq's `a // b` operator falls back
#    to `b`'s *outputs*; if the final fallback is the `empty` generator (zero
#    outputs), the entire enclosing `{...}` object construction also
#    produces zero outputs — not a "cwd" key that's merely absent. That
#    empties the adapter's stdout entirely, which then fails open to the RAW
#    payload (`PAYLOAD="${NORMALIZED:-$INPUT}"`), silently losing session_id
#    derivation too (the raw Cursor payload has no `session_id` key, only
#    `conversation_id`, so the target script's own `.session_id // "unknown"`
#    default kicks in and state gets filed under the wrong key). The fix
#    must make the cwd fallback chain end in a literal "" instead.
# ---------------------------------------------------------------------------
export TG_NOTIFY_HOME="$TMP/home0"
mkdir -p "$TG_NOTIFY_HOME"

NO_ROOTS_KEY_PAYLOAD='{
  "conversation_id": "conv-no-roots",
  "hook_event_name": "beforeSubmitPrompt",
  "cursor_version": "1.7.2",
  "prompt": "no workspace_roots key at all"
}'
printf '%s' "$NO_ROOTS_KEY_PAYLOAD" | "$ADAPTER" tg-prompt-start.sh
[ -f "$TG_NOTIFY_HOME/state/conv-no-roots.start" ] || fail "missing workspace_roots key: expected state file conv-no-roots.start (got: $(ls "$TG_NOTIFY_HOME/state" 2>/dev/null || echo '<none>'))"

EMPTY_ROOTS_ARRAY_PAYLOAD='{
  "conversation_id": "conv-empty-roots",
  "hook_event_name": "beforeSubmitPrompt",
  "cursor_version": "1.7.2",
  "workspace_roots": [],
  "prompt": "empty workspace_roots array"
}'
printf '%s' "$EMPTY_ROOTS_ARRAY_PAYLOAD" | "$ADAPTER" tg-prompt-start.sh
[ -f "$TG_NOTIFY_HOME/state/conv-empty-roots.start" ] || fail "empty workspace_roots array: expected state file conv-empty-roots.start (got: $(ls "$TG_NOTIFY_HOME/state" 2>/dev/null || echo '<none>'))"

echo "PASS missing/empty workspace_roots does not collapse normalization to zero jq output"
unset TG_NOTIFY_HOME

# ---------------------------------------------------------------------------
# 0b. session_id vs conversation_id priority: conversation_id is present on
#     every agent-session hook per Cursor's common schema; session_id is only
#     present on sessionStart/sessionEnd and documented as "same as
#     conversation_id". Prefer conversation_id first for consistency across
#     all event types (see design doc's field-normalization table).
# ---------------------------------------------------------------------------
export TG_NOTIFY_HOME="$TMP/home0b"
mkdir -p "$TG_NOTIFY_HOME"

DIVERGENT_IDS_PAYLOAD='{
  "conversation_id": "conv-priority-wins",
  "session_id": "should-not-be-used",
  "hook_event_name": "beforeSubmitPrompt",
  "workspace_roots": ["/tmp/fake-project"],
  "prompt": "priority check"
}'
printf '%s' "$DIVERGENT_IDS_PAYLOAD" | "$ADAPTER" tg-prompt-start.sh
[ -f "$TG_NOTIFY_HOME/state/conv-priority-wins.start" ] || fail "expected conversation_id to be preferred over session_id (state file conv-priority-wins.start missing)"
[ -f "$TG_NOTIFY_HOME/state/should-not-be-used.start" ] && fail "session_id must not win over conversation_id"
echo "PASS conversation_id preferred over session_id"
unset TG_NOTIFY_HOME

# ---------------------------------------------------------------------------
# 1. sessionStart -> abbr-inject.sh output reshaping
# ---------------------------------------------------------------------------
SESSION_START_PAYLOAD='{
  "conversation_id": "conv-abc123",
  "session_id": "conv-abc123",
  "hook_event_name": "sessionStart",
  "cursor_version": "1.7.2",
  "workspace_roots": ["/tmp/fake-project"],
  "is_background_agent": false
}'

OUT=$(printf '%s' "$SESSION_START_PAYLOAD" | "$ADAPTER" abbr-inject.sh)
printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 || fail "sessionStart output is not valid JSON: $OUT"
printf '%s' "$OUT" | jq -e 'has("additional_context")' >/dev/null 2>&1 || fail "sessionStart output missing additional_context key: $OUT"
printf '%s' "$OUT" | jq -e 'has("hookSpecificOutput") | not' >/dev/null 2>&1 || fail "sessionStart output still has hookSpecificOutput wrapper: $OUT"
LEN=$(printf '%s' "$OUT" | jq -r '.additional_context | length')
[ "$LEN" -gt 0 ] || fail "sessionStart additional_context is empty"
echo "PASS sessionStart -> abbr-inject.sh reshaping"

# ---------------------------------------------------------------------------
# 1b. sessionStart -> model-tiers-inject.sh output reshaping
# ---------------------------------------------------------------------------
export CURSOR_PLUGIN_ROOT="$REPO_ROOT"
OUT_MT=$(printf '%s' "$SESSION_START_PAYLOAD" | "$ADAPTER" model-tiers-inject.sh)
printf '%s' "$OUT_MT" | jq -e . >/dev/null 2>&1 || fail "model-tiers sessionStart output is not valid JSON: $OUT_MT"
printf '%s' "$OUT_MT" | jq -e 'has("additional_context")' >/dev/null 2>&1 || fail "model-tiers sessionStart output missing additional_context key: $OUT_MT"
CTX_MT=$(printf '%s' "$OUT_MT" | jq -r '.additional_context')
printf '%s' "$CTX_MT" | grep -q 'cheap = haiku' || fail "model-tiers inject missing cheap = haiku: $CTX_MT"
printf '%s' "$CTX_MT" | grep -q 'standard = sonnet' || fail "model-tiers inject missing standard = sonnet: $CTX_MT"
printf '%s' "$CTX_MT" | grep -q 'judgment = opus' || fail "model-tiers inject missing judgment = opus: $CTX_MT"
printf '%s' "$CTX_MT" | grep -q 'runtime = cursor' || fail "model-tiers inject missing runtime = cursor: $CTX_MT"
unset CURSOR_PLUGIN_ROOT
echo "PASS sessionStart -> model-tiers-inject.sh reshaping"

# ---------------------------------------------------------------------------
# 2. beforeSubmitPrompt -> tg-prompt-start.sh session-id mapping
# ---------------------------------------------------------------------------
export TG_NOTIFY_HOME="$TMP/home1"
mkdir -p "$TG_NOTIFY_HOME"

PROMPT_PAYLOAD='{
  "conversation_id": "conv-abc123",
  "hook_event_name": "beforeSubmitPrompt",
  "cursor_version": "1.7.2",
  "workspace_roots": ["/tmp/fake-project"],
  "prompt": "hello",
  "attachments": []
}'

printf '%s' "$PROMPT_PAYLOAD" | "$ADAPTER" tg-prompt-start.sh

START_FILE="$TG_NOTIFY_HOME/state/conv-abc123.start"
[ -f "$START_FILE" ] || fail "expected $START_FILE to exist (conversation_id should become session_id)"
PROMPT_VAL=$(jq -r '.prompt // ""' "$START_FILE")
[ "$PROMPT_VAL" = "hello" ] || fail "expected prompt=hello in $START_FILE, got '$PROMPT_VAL'"
echo "PASS beforeSubmitPrompt -> tg-prompt-start.sh session-id mapping"
unset TG_NOTIFY_HOME

# ---------------------------------------------------------------------------
# 3. stop -> tg-on-stop.sh cwd derivation + scheduling
#
# Runs through a SANDBOXED TG_SKILL_DIR (see header comment) so the delayed
# job invokes a local stub instead of the real skills/tg-notify/tg-notify.sh,
# and uses a short, explicit TG_NOTIFY_STOP_DELAY so the background job
# finishes (and we can positively confirm it exited) in well under a second
# — no shared script is modified, only a parallel symlink tree in $TMP.
# ---------------------------------------------------------------------------
SANDBOX="$TMP/sandbox"
mkdir -p "$SANDBOX/hooks" "$SANDBOX/skills/tg-notify"
ln -s "$HOOKS_DIR/cursor-adapter.sh" "$SANDBOX/hooks/cursor-adapter.sh"
ln -s "$HOOKS_DIR/tg-on-stop.sh" "$SANDBOX/hooks/tg-on-stop.sh"
ln -s "$REPO_ROOT/skills/tg-notify/context-header.sh" "$SANDBOX/skills/tg-notify/context-header.sh"
ln -s "$REPO_ROOT/skills/tg-notify/runtime.sh" "$SANDBOX/skills/tg-notify/runtime.sh"

STUB_CALL_LOG="$TMP/stub-tg-sender.calls"
cat > "$SANDBOX/skills/tg-notify/tg-notify.sh" <<EOF
#!/usr/bin/env bash
printf '%s\t%s\n' "\$(date -Iseconds)" "\$*" >> "$STUB_CALL_LOG"
exit 0
EOF
chmod +x "$SANDBOX/skills/tg-notify/tg-notify.sh"

export TG_NOTIFY_HOME="$TMP/home2"
mkdir -p "$TG_NOTIFY_HOME/state"
export TG_NOTIFY_STOP_THRESHOLD=0
export TG_NOTIFY_STOP_DEBOUNCE=0
export TG_NOTIFY_STOP_DELAY=2

# started_at far in the past so DUR clears the (now zeroed) threshold
PAST_TS=$(( $(date +%s) - 100000 ))
jq -n --argjson ts "$PAST_TS" --arg p "test prompt" '{started_at:$ts, prompt:$p}' \
    > "$TG_NOTIFY_HOME/state/conv-abc123.start"

STOP_PAYLOAD='{
  "conversation_id": "conv-abc123",
  "hook_event_name": "stop",
  "cursor_version": "1.7.2",
  "workspace_roots": ["/tmp/fake-project"],
  "status": "completed",
  "loop_count": 0
}'

printf '%s' "$STOP_PAYLOAD" | "$SANDBOX/hooks/cursor-adapter.sh" tg-on-stop.sh

PAYLOAD_GLOB="$TG_NOTIFY_HOME/pending/conv-abc123/*.payload"
compgen -G "$PAYLOAD_GLOB" >/dev/null 2>&1 || fail "expected a pending payload under $TG_NOTIFY_HOME/pending/conv-abc123/"
echo "PASS stop -> tg-on-stop.sh cwd derivation + scheduling"

# The background job sleeps TG_NOTIFY_STOP_DELAY=2s, then delivers via the
# sandboxed stub and removes the payload file itself — wait for that natural
# completion (never kill it) and confirm the stub (not the real sender) ran.
DONE=""
for _ in $(seq 1 40); do
    if ! compgen -G "$PAYLOAD_GLOB" >/dev/null 2>&1; then
        DONE=1
        break
    fi
    sleep 0.25
done
[ -n "$DONE" ] || fail "background stop job did not clean up its payload within ~10s — would linger"
[ -f "$STUB_CALL_LOG" ] || fail "expected the sandboxed stub sender to have been invoked (real tg-notify.sh must never run in tests)"
echo "PASS delayed stop job completed via sandboxed stub sender, no real sender invoked"

# Final proof of no lingering process: nothing on the system should still
# reference this test run's unique pending-payload path.
sleep 0.3
if pgrep -f "$TG_NOTIFY_HOME/pending/conv-abc123" >/dev/null 2>&1; then
    fail "a background process still references $TG_NOTIFY_HOME/pending/conv-abc123 — would linger"
fi
echo "PASS no lingering setsid/sleep process after the stop test"

unset TG_NOTIFY_HOME TG_NOTIFY_STOP_THRESHOLD TG_NOTIFY_STOP_DEBOUNCE TG_NOTIFY_STOP_DELAY

# ---------------------------------------------------------------------------
# 4. preToolUse / sessionEnd -> tg-cancel-pending.sh
# ---------------------------------------------------------------------------
export TG_NOTIFY_HOME="$TMP/home3"
mkdir -p "$TG_NOTIFY_HOME/pending/conv-abc123"
touch "$TG_NOTIFY_HOME/pending/conv-abc123/fake.payload"

PRETOOLUSE_PAYLOAD='{
  "conversation_id": "conv-abc123",
  "hook_event_name": "preToolUse",
  "cursor_version": "1.7.2",
  "workspace_roots": ["/tmp/fake-project"],
  "tool_name": "Shell",
  "tool_input": {"command": "ls"},
  "tool_use_id": "tc-1",
  "cwd": "/tmp/fake-project"
}'

printf '%s' "$PRETOOLUSE_PAYLOAD" | "$ADAPTER" tg-cancel-pending.sh

[ -f "$TG_NOTIFY_HOME/pending/conv-abc123/fake.payload" ] && fail "expected pending payload to be removed by tg-cancel-pending.sh via preToolUse"
echo "PASS preToolUse -> tg-cancel-pending.sh"
unset TG_NOTIFY_HOME

# ---------------------------------------------------------------------------
# 5. Adapter target allowlist: unknown/deliberately-excluded target names
#    must never be invoked at all — not just have their stdout discarded
#    (defense-in-depth; the only real caller is hooks/cursor-hooks.json,
#    which only ever names the 5 wired scripts). Stdout is already discarded
#    for every non-abbr-inject.sh target, so an emptiness check on the
#    adapter's own stdout can't distinguish "blocked" from "ran but silent";
#    use a real side effect (a marker file) instead.
# ---------------------------------------------------------------------------
ALLOWLIST_SANDBOX="$TMP/allowlist_sandbox/hooks"
mkdir -p "$ALLOWLIST_SANDBOX"
ln -s "$HOOKS_DIR/cursor-adapter.sh" "$ALLOWLIST_SANDBOX/cursor-adapter.sh"

MARKER="$TMP/allowlist-marker"
make_probe() {
    cat > "$ALLOWLIST_SANDBOX/$1" <<EOF
#!/usr/bin/env bash
cat >/dev/null
echo "invoked:$1" >> "$MARKER"
exit 0
EOF
    chmod +x "$ALLOWLIST_SANDBOX/$1"
}
make_probe "tg-prompt-start.sh"     # allowlisted name -> must still run
make_probe "model-tiers-inject.sh"  # allowlisted name -> must still run
make_probe "tg-on-notification.sh"  # deliberately NOT wired -> must be blocked

rm -f "$MARKER"
printf '%s' '{"conversation_id":"x"}' | "$ALLOWLIST_SANDBOX/cursor-adapter.sh" tg-on-notification.sh
[ -f "$MARKER" ] && fail "adapter must not invoke a non-allowlisted target (tg-on-notification.sh ran): $(cat "$MARKER")"

printf '%s' '{"conversation_id":"x","prompt":"p"}' | "$ALLOWLIST_SANDBOX/cursor-adapter.sh" tg-prompt-start.sh
grep -q '^invoked:tg-prompt-start.sh$' "$MARKER" 2>/dev/null || fail "sanity check failed: allowlisted target tg-prompt-start.sh did not run via the sandbox harness"

rm -f "$MARKER"
printf '%s' '{"conversation_id":"x"}' | "$ALLOWLIST_SANDBOX/cursor-adapter.sh" "../evil.sh" 2>/dev/null || true
[ -f "$MARKER" ] && fail "adapter must reject path-traversal target names"

echo "PASS adapter target allowlist blocks non-allowlisted/unsafe targets while still running allowlisted ones"

# ---------------------------------------------------------------------------
# 6. Regression guard: no Notification/PermissionRequest-equivalent binding
# ---------------------------------------------------------------------------
CURSOR_HOOKS_JSON="$HOOKS_DIR/cursor-hooks.json"
[ -f "$CURSOR_HOOKS_JSON" ] || fail "hooks/cursor-hooks.json missing"
if grep -qi 'notification\|permission' "$CURSOR_HOOKS_JSON"; then
    fail "hooks/cursor-hooks.json must not wire Notification/PermissionRequest"
fi
echo "PASS regression guard: no Notification/PermissionRequest binding"

# ---------------------------------------------------------------------------
# 7. No drift in shared hooks not intentionally extended by another runtime
#    adapter (staged AND unstaged, i.e.
#    the full working-tree diff against HEAD — not just the unstaged diff
#    against the index, which would miss a `git add`-ed regression).
# ---------------------------------------------------------------------------
cd "$REPO_ROOT"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    DIFF=$(git diff HEAD --stat -- \
        hooks/abbr-inject.sh \
        hooks/tg-prompt-start.sh \
        hooks/tg-on-notification.sh \
        hooks/tg-cancel-pending.sh \
        skills/agents 2>/dev/null || true)
    [ -z "$DIFF" ] || fail "pre-existing hook files/skills/agents must not change:
$DIFF"
    echo "PASS no drift in shared hook files, skills, agents (staged + unstaged)"
else
    echo "SKIP no-drift check (not a git work tree)"
fi

echo "ALL PASS cursor-adapter"
