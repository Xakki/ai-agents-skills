# Targeted lint and staging

Use the supported project validator and exact canonical card path or basename; inspect its resolver instead of assuming a short ID is accepted. Verify the actual nonzero checked-card count and errors/warnings, run board-wide checks separately where required, and report unrelated baseline failures without changing unrelated files. Examine untracked and ignored owned cards explicitly; an empty Git diff does not prove them valid.

For an authorized move, verify source and destination, any maintained embedded status, and the helper's actual index effects; rerun the applicable destination lint. A helper can stage a template or pre-edit rename while later work remains unstaged. When staging is authorized, refresh the final card and intended lock/parent paths, inspect cached path membership and full diff, and compare staged bytes with the reviewed candidate. A substantive rewrite may appear as delete/add rather than rename; verify the actual endpoints.

Commit only if authorized and follow the repository's message and trailer rules; never include secrets or full prompts. Supply real newlines and actual stdin when using a message file or `-F -`. Verify final commit message, path list, native exit and SHA, check the committed diff and relevant post-commit lint, and report unrelated dirty state accurately. Do not manufacture a clean whole-worktree claim.
