# ai-agents-skills

A [Claude Code](https://code.claude.com/docs/en/plugins) plugin that bundles two
skills for running a lightweight kanban workflow — and driving it autonomously
on a timer.

| Skill | What it does |
|-------|--------------|
| **kanban** | Manage a `.claude/kanban/` board in your project: create, start, review, and complete task cards across `grooming → todo → progress → test → ready → done`. |
| **schedule-tasks** | Schedule autonomous `claude` runs of `todo/` cards via `at`/tmux. Each card opens in its own byobu window and self-chains the next card on success. |

## Install

As a marketplace from this repo:

```
/plugin marketplace add Xakki/ai-agents-skills
/plugin install ai-agents-skills@ai-agents-skills
```

Or from a local checkout:

```
/plugin marketplace add /home/xakki/ai-agents-skills
/plugin install ai-agents-skills@ai-agents-skills
```

Verify the manifest and skill frontmatter at any time:

```
claude plugin validate /home/xakki/ai-agents-skills
```

## Layout

```
.
├── .claude-plugin/
│   ├── plugin.json        # plugin manifest (only this file lives here)
│   └── marketplace.json   # marketplace entry → source "./"
├── skills/
│   ├── kanban/
│   └── schedule-tasks/
└── scripts/               # runners used by schedule-tasks (run from the plugin cache)
```

The skills are auto-discovered from `skills/` — no `skills` field in
`plugin.json` is needed.

## Usage

- **kanban** triggers on task-management requests ("create a task", "what's in
  progress", "mark done"). It operates on `.claude/kanban/` in your *current*
  project; the board is created on first use.
- **schedule-tasks** triggers on "schedule tasks" / "запланируй задачи". It needs
  `atd` active and a byobu/tmux session, and reads cards from
  `.claude/kanban/todo/` in your current project.

### schedule-tasks & the plugin cache

`schedule-tasks` invokes the runner scripts from `${CLAUDE_PLUGIN_ROOT}/scripts/`
(the installed plugin's cache), not from your repo. The scripts derive the
target repo from the task-file path they're given
(`<repo>/.claude/kanban/<stage>/<name>.md`), so they work from any project
without per-repo configuration. Your kanban board still lives in your project
under `.claude/kanban/`.

## Requirements

- `schedule-tasks`: `atd` running (`systemctl is-active atd`), `at`/`atq`/`atrm`,
  a tmux/byobu session, and `claude` on `PATH`.

## License

MIT — see [LICENSE](LICENSE).
