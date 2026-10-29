# Bounded local worker service

Establish the actual authorized caller, exposed interface, input limits, process identity and command contract. Prefer the least exposed supported transport; do not infer that a loopback address alone provides authentication or prevents all local access. Validate allowed operations and arguments without turning an API request into an arbitrary shell command.

Apply task-appropriate limits to concurrency, queue depth, runtime and output size. Track each owned child process and preserve timeout, cancellation and completion separately. A client disconnect or an outer timeout does not automatically prove all descendants stopped. Inspect the real operating-system and supervisor behavior before claiming cleanup.

When a hard wall-clock limit is required, include startup, request, cleanup and reaping in the measured deadline. Cooperative task cancellation alone does not establish that deadline if cleanup can block or suppress it. Bound result pipes and waits, signal only processes whose ownership is established, and verify actual termination without affecting unrelated processes.

Avoid putting credentials or private input in command arguments or diagnostic output. Test actual service and process boundaries with safe fixtures when authorized, and distinguish a local synthetic client from live deployment acceptance. Do not modify existing privileged endpoints or expose a new listener without the applicable task authority.
