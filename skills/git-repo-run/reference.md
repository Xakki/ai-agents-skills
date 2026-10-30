# Git message and staging guidance

Use this reference for exact commit messages, staged-state preservation and branch or publication decisions.

## Exact messages

Build the requested subject and body using separate `git commit -m` arguments, or write the exact intended message to a private temporary file and use `git commit -F <file>`. Ordinary quoted strings containing literal `\n` do not become newline characters. When Bash is the chosen shell, ANSI-C `$'...'` quoting can express newlines; avoid accidental indentation. Preserve user-provided trailers and add no new trailer unless authorized by the task or applicable project policy.

After committing, inspect `git show -s --format=%B HEAD` and, when trailers matter, `git show -s --format='%(trailers:only,unfold)' HEAD`. Verify the message and actual commit ID rather than inferring the result from the command. A message amendment changes the commit ID and requires authorization.

## Existing index and dirty worktree

Record the admitted scope and pre-existing staged state before changes. Explicit `git add -- <path>` is not sufficient if unrelated entries are already staged; inspect the complete staged set and preserve unrelated entries. Use project-supported hunk selection when only part of a file belongs to the task. Do not force-stage ignored content or inspect private material solely to make a commit pass. A checkpoint records work and does not by itself prove acceptance.

## Branches and remote effects

Use the branch and naming policy supplied by the task or repository. Inspect exact source/target refs and ancestry; avoid destructive history changes without explicit authorization. Normal hooks and any configured signing must run. A failed native security or approval boundary is not a reason to bypass it. Report local commit, remote update, review and deployment as separate outcomes.
