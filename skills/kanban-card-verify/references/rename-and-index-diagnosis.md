# Rename and index diagnosis

Use when a lifecycle mover stages a rename, a compatibility alias may resolve differently from the physical board, or the working card changed after staging.

Resolve the canonical physical paths. Inspect HEAD, the full index, working state and both endpoints independently: a staged rename with a modified destination has a separate unstaged body. Confirm exact index mode and object identity when claiming an unchanged rename; a lower similarity score or changed blob requires its own review. An absent old index entry is expected after a successful staged rename.

Before relying on a mover or wrapper that accepts aliases, qualify actual physical and indexed endpoints in a disposable authorized fixture, including refused transitions and collisions; an exit code alone does not prove the correct index entry. Preserve untracked data, permissions and unrelated staged entries. If a helper stages before the card's final evidence edit, verify and, only when authorized, stage the final destination body as well as required source removal.

Do not unstage or rewrite an existing staged rename merely to satisfy a preferred clean baseline. Any index-only recovery requires action-specific authority, an admitted receiving Git procedure, exact owned entries and preservation proof; do not touch working bytes or normalize foreign staging. Stop on native security or approval veto, unowned drift, partial recovery or ambiguous ownership. Index, worktree and commit verification are separate observations; a successful physical move is not a commit.
