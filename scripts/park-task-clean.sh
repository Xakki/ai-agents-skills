#!/usr/bin/env bash
# Owner-run: restore the working tree after park-task.sh has preserved its changes
# on the side branch task/<card>. Dry-run by default; --apply needs the
# --plan-sha256 printed by that dry-run. Refused inside a scheduled run.
#
# Usage: park-task-clean.sh [--repo DIR] (--branch task/<card> | --record FILE) [--apply --plan-sha256 HASH]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -I "$SCRIPT_DIR/park_task_clean.py" "$@"
