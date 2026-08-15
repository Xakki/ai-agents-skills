# Hook events — stdin fields, matchers, exit codes

Source: `code.claude.com/docs/en/hooks`. Verify against it before relying on a
row; on drift, fix this file in the same change and report it.

Every event receives these common fields on stdin as one JSON object:
`session_id`, `transcript_path`, `cwd`, `hook_event_name`. Most tool- and
prompt-scoped events add `prompt_id`, `permission_mode`, `effort`; agent-scoped
events add `agent_id`, `agent_type`.

## Events you are most likely to test

| Event | Matcher | Event-specific stdin | exit 2 means |
|---|---|---|---|
| `PreToolUse` | tool name regex (`Bash`, `Edit\|Write`, `mcp__.*`) | `tool_name`, `tool_input`, `tool_use_id` | **blocks the tool call** |
| `PostToolUse` | tool name | `tool_name`, `tool_input`, `tool_output`, `tool_use_id` | stderr to the agent; tool already ran |
| `PostToolUseFailure` | tool name | `tool_name`, `tool_input`, `error_message` | stderr to the agent; tool already failed |
| `PermissionRequest` | tool name | `tool_name`, `tool_input`, `tool_use_id` | **not honored** — use JSON `decision` |
| `PermissionDenied` | tool name | `tool_name`, `tool_input`, `denial_reason`, `has_classifier_verdict` | **not honored** — use `hookSpecificOutput.retry` |
| `UserPromptSubmit` | **none** | `prompt_text` | blocks the prompt and erases it |
| `SessionStart` | `startup` `resume` `clear` `compact` `fork` | `model` (not guaranteed) | stderr to user only; session proceeds |
| `Setup` | `init` `maintenance` | `trigger` | stderr to user only |
| `SessionEnd` | `clear` `resume` `logout` `prompt_input_exit` `bypass_permissions_disabled` `other` | `end_reason` | stderr to user only |
| `Stop` | **none** | `last_assistant_message`, `stop_reason` | **prevents stopping** |
| `SubagentStop` | agent type | `last_assistant_message`, `stop_reason` | prevents the subagent stopping |
| `SubagentStart` | agent type | subagent config | stderr to user only |
| `TaskCreated` | **none** | `task_id`, `task_subject`, optional `task_description`/`teammate_name`/`team_name` | **rolls back the task creation** |
| `TaskCompleted` | **none** | `task_id`, `task_subject`, optional `task_description`/`teammate_name`/`team_name` | **prevents marking the task completed** |
| `TeammateIdle` | **none** | `teammate_name`, `team_name` | **prevents the teammate going idle** |
| `PreCompact` | `manual` `auto` | compaction details | **blocks compaction** |
| `PostCompact` | `manual` `auto` | compaction results | stderr to user only |
| `PostToolBatch` | **none** | `tool_calls[]` | stops the agentic loop |
| `ConfigChange` | `user_settings` `project_settings` `local_settings` `policy_settings` `skills` | `config_source`, `changed_keys` | blocks the change (except policy) |
| `InstructionsLoaded` | `session_start` `nested_traversal` `path_glob_match` `include` `compact` | `file_path`, `load_reason` | **exit code ignored** |
| `Notification` | `permission_prompt` `idle_prompt` `auth_success` `elicitation_dialog` `elicitation_url_dialog` `elicitation_complete` `elicitation_response` `agent_needs_input` `agent_completed` | `message`, optional `title`, `notification_type` | **exit code ignored** |
| `MessageDisplay` | **none** | `turn_id`, `message_id`, `index`, `final`, `delta` | ignored — original text is displayed |
| `FileChanged` | literal filenames (`.envrc\|.env`) | `file_path`, `change_type` | stderr to user only |
| `CwdChanged` | **none** | `old_cwd`, `new_cwd` | stderr to user only |
| `DirectoryAdded` | `slash_command` `register_repo_root` | `directory`, `source` | stderr to debug log only; directory already added |
| `StopFailure` | `rate_limit` `overloaded` `authentication_failed` `oauth_org_not_allowed` `billing_error` `invalid_request` `model_not_found` `server_error` `max_output_tokens` `unknown` | `error`, optional `error_details`/`last_assistant_message` | **output and exit code ignored entirely** (not honored by the standard model at all) |
| `WorktreeCreate` | **none** | worktree config | **any non-zero fails creation** |
| `WorktreeRemove` | **none** | `worktree_path` | failures logged in debug mode only |

`notification_type`, `error` (StopFailure), and `source` (DirectoryAdded) are
the matcher fields for those three events — confirmed 2026-08-15 against the
doc's raw HTML; the previous `notification_type`+`notification_message` pair
for `Notification` was wrong (no `notification_message` field exists; the
real field is `message`).

## "Matcher present but invalid" is silent

There is no error, no warning, no debug line in normal operation — the hook
simply never runs. Two hooks registered under `"matcher": "*"` on `SessionStart`
and `Stop` were dead for weeks before anyone noticed. `lint-settings.sh` exists
mainly for this failure mode. When a hook does not fire and the matcher is
clean, `claude --debug` at startup is the next diagnostic — not more edits.

## JSON output (instead of exit codes)

Universal fields accepted by all hooks:

```json
{ "continue": true, "stopReason": "", "suppressOutput": false,
  "systemMessage": "", "terminalSequence": "" }
```

Event-specific, under `hookSpecificOutput`:

- `PreToolUse`, `PermissionRequest` — `permissionDecision`: `allow` | `deny` |
  `escalate`, plus `permissionDecisionReason`
- `PermissionDenied` — `retry: true` (ignored for no-verdict denials)
- `Elicitation` — `decision`: `allow` | `deny` | `escalate`
- Blocking events (`UserPromptSubmit`, `PreToolUse`, `PostToolBatch`, …) —
  top-level `decision` and `reason`

A hook returning `permissionDecision: "allow"` **bypasses the permission system
entirely**, including `ask` rules. Prefer exit 0 (defer to the normal rules)
unless you specifically intend to auto-approve.

## Settings precedence

Highest wins; `deny` beats everything at every level.

1. enterprise policy
2. command line
3. `<project>/.claude/settings.local.json`
4. `<project>/.claude/settings.json`
5. `~/.claude/settings.json`

`~/.claude/settings.local.json` sits at user scope alongside (5). Because (3)
outranks (4), a stale local list silently masks the tracked project intent —
keep the two in sync or drop the local one.

Hooks do **not** override each other by precedence: every registered hook for an
event runs, from every source. Registering the same script at two scopes runs it
twice.
