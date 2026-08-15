# Status line

Two drop-in status-line renderers for Claude Code:

| Script | Setting | Renders |
|---|---|---|
| `statusline-command.sh` | `statusLine` | Main (team-lead) session: `model · launch dir · git branch · dirty · ctx% · session tokens · pwd` |
| `subagent-statusline-command.sh` | `subagentStatusLine` | One row per teammate in the agent panel: `name · model · ctx% · tokens` (no dirs/git) |

Both are pure `bash` + `jq`, read the harness payload on stdin, and never fail
hard: every lookup degrades to empty and every `git` call is capped with
`timeout 2`, so a slow or locked repo can't hang the prompt render.

## Behavior worth knowing

- **`pwd` is printed only when it differs from the launch dir.** The launch dir
  (`workspace.project_dir`) is shown in full on the left; the live
  `workspace.current_dir` is appended as `pwd …/a/b` only when the two differ
  (trailing slashes normalized). Same dir → no duplicate segment.
- **Session tokens** are summed from the transcript across every assistant turn
  and include `cache_read`/`cache_creation`, so the number is real API spend,
  not just context fill.
- **Teammate payloads** (`.agent.name` / `.agent_type` present) fall through to
  the compact form inside `statusline-command.sh` too — that path is the
  fallback for harnesses that route subagent rows through `statusLine`.
- The two scripts share one palette, so lead and teammate rows read the same.

## Install

1. Copy the scripts somewhere stable outside the plugin cache (a plugin update
   replaces its versioned dir):

   ```bash
   mkdir -p ~/.claude/bin
   cp statusline/statusline-command.sh          ~/.claude/bin/
   cp statusline/subagent-statusline-command.sh ~/.claude/bin/
   chmod +x ~/.claude/bin/*statusline-command.sh
   ```

2. Wire them into `~/.claude/settings.json` (project-scoped works too, in
   `<project>/.claude/settings.json`) — use an **absolute path**, `settings.json`
   does not expand `~` or plugin root variables:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash /home/<user>/.claude/bin/statusline-command.sh"
     },
     "subagentStatusLine": {
       "type": "command",
       "command": "bash /home/<user>/.claude/bin/subagent-statusline-command.sh"
     }
   }
   ```

   Wiring the plugin copy directly (`bash /home/<user>/.claude/plugins/cache/ai-agents-skills/ai-agents-skills/<version>/statusline/statusline-command.sh`)
   also works, but the path carries the plugin version and breaks on update —
   prefer step 1.

3. The status line is re-rendered on every turn — no restart needed. Only
   editing `settings.json` itself needs a new session to be picked up.

## Verify without a session

```bash
# lead form, pwd == launch dir → no "pwd" segment
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/repo","project_dir":"/repo"}}' \
  | bash statusline/statusline-command.sh; echo

# lead form, pwd != launch dir → trailing "pwd …/repo/sub"
echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/repo/sub","project_dir":"/repo"}}' \
  | bash statusline/statusline-command.sh; echo

# teammate panel → one {"id","content"} JSON line per row
echo '{"tasks":[{"id":"t1","name":"impl","model":"Sonnet","tokenCount":12000,"contextWindowSize":200000}]}' \
  | bash statusline/subagent-statusline-command.sh
```

## Requirements

`jq`, `awk`, `git`, `timeout` (coreutils) on `PATH`.
