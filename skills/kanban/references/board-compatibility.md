# Existing board compatibility

Use only when the project's board predates the current `.agents/kanban` convention. The helper also detects existing `.claude/kanban` boards for compatibility. Its `kanban.lock` is beside the resolved board root. Aliases resolving to one physical board are equivalent; distinct boards or conflicting counters cause the helper to fail closed. Do not create, remove or move a board merely to resolve ambiguity without the project's policy and appropriate authorization.
