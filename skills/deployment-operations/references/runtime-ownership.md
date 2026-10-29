# Runtime ownership and access diagnosis

Identify the exact runtime process identity, effective access path, source and destination mount or resource, current metadata and task authorization. Distinguish the identity presented by a process from filesystem ownership or namespace mappings; an owner ID alone does not prove which process created a file. Check effective access through a bounded supported interface without printing file contents or secrets.

Compare the actual owner, group, permissions, parent traversal and mount mapping with the application's required read/write contract. Resolve the creating and consuming identities and namespace translation where relevant. Do not assume rootless or host user mappings from a numeric ID alone.

Choose an appropriately scoped change only if explicitly authorized and supported by the project. Preserve pre-existing file contents and ownership outside the admitted scope. Do not infer that a path-limited inspection makes a subsequent recursive ownership change safe; establish nested mounts, symlink behavior and affected descendants before any such operation. Verify the effective service identity and post-change access, not merely the source configuration.
