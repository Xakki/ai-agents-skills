# Claude Code scheduler prototype

The existing scripts `scripts/run-claude-task.sh` and `scripts/run-claude-task-inner.sh` launch Claude Code in a tmux window after checking the supplied scope. This is a Claude-specific adapter, not a generic agent launcher. The runner uses normal Claude permission behavior; a scheduled run may stop pending a permission decision. Do not add an approval-bypass flag.

The canonical scheduler board for this adapter is `.agents/kanban/todo` inside the repository. The physical resolved board must stay inside the repository and selected cards must be direct children. Project-defined board helpers and instructions remain authoritative. The plugin installation root comes from the runtime's supported root interface; do not assume an environment-specific absolute path.

The tmux session defaults to `ai-agents-scheduler`; an operator may set `SCHEDULE_TMUX_SESSION` and optionally `SCHEDULE_TMUX_SOCKET`. The runner records logs below the current user's home. Its inner script acquires a repository-wide lock shared by updated runner instances. Existing older runners and manual writers are not covered by that lock.

The packaged scope manifest currently fixes execute, QA, review, merge-at-ready and within-scope chain permissions. An `--approved` flag records the caller's assertion, not cryptographic proof. Only create or enqueue a scope when the owner actually authorized every fixed effect for those exact cards. When a narrower authorization is required, do not use the current manifest format.

The runner uses Claude session telemetry and a read-only usage summary; it does not stage or commit the summary. It does not automatically cancel ambiguous queued jobs. Parking is a verified side-branch snapshot (`park-task.sh`, see reference.md); it never switches branches or cleans the tree (restoring the checkout afterwards is the owner-run `park-task-clean.sh`, see reference.md), and the runner exports `SCHEDULE_SCOPE_ID` so only an approved run can use it. If any required capability is absent, stop and report; do not silently substitute another agent or bypass its native permissions.
