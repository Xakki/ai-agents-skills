#!/usr/bin/env bash
# Aggregate token usage + approximate cost from a claude session JSONL,
# print to stdout and append an "Auto-run usage" block to the task file.
#
# Universal: derives PROJECT_DIR / CLAUDE_PROJECT_PATH from the task-file
# argument (card lives at <repo>/.claude/kanban/<stage>/<name>.md → repo is
# three levels up). Script itself runs from the plugin cache.
#
# Usage: summarize-task-usage.sh <session-id> <task-file> [<wall-seconds>] [<exit-code>] [<result>]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SESSION_ID="${1:?session id required}"
TASK_FILE_HINT="${2:?task file path required}"
PROJECT_DIR="$(cd "$(dirname "$TASK_FILE_HINT")/../../.." && pwd)"
CLAUDE_PROJECT_PATH="$(printf '%s' "$PROJECT_DIR" | tr '/' '-')"
WALL_SEC="${3:-?}"
EXIT_CODE="${4:-?}"
RESULT="${5:-unknown}"

PROJ_DIR="${HOME:-/home/coder}/.claude/projects/${CLAUDE_PROJECT_PATH}"
JSONL="$PROJ_DIR/$SESSION_ID.jsonl"

if [ ! -f "$JSONL" ]; then
    echo "ERROR: session JSONL not found: $JSONL" >&2
    exit 1
fi

# Resolve current task-file location (claude may have moved it to progress/)
TASK_FILE=""
if [ -f "$TASK_FILE_HINT" ]; then
    TASK_FILE="$TASK_FILE_HINT"
else
    BASE="$(basename "$TASK_FILE_HINT")"
    for d in done test progress todo; do
        cand="${PROJECT_DIR}/.claude/kanban/$d/$BASE"
        if [ -f "$cand" ]; then TASK_FILE="$cand"; break; fi
    done
fi

python3 - "$JSONL" "${TASK_FILE:-}" "$SESSION_ID" "$WALL_SEC" "$EXIT_CODE" "$RESULT" <<'PY'
import json, sys, os
from datetime import datetime

jsonl, task_file, sid, wall_sec, exit_code, result = sys.argv[1:7]

# Approximate pricing per 1M tokens (USD). Adjust as Anthropic publishes updates.
# Cache write split: 5m default vs 1h ephemeral.
PRICE = {
    # opus 4.x family
    "opus": {"in": 15.00, "out": 75.00, "cw5": 18.75, "cw1h": 30.00, "cr": 1.50},
    # sonnet 4.x family
    "sonnet": {"in": 3.00, "out": 15.00, "cw5": 3.75, "cw1h": 6.00, "cr": 0.30},
    # haiku 4.x family
    "haiku": {"in": 1.00, "out": 5.00, "cw5": 1.25, "cw1h": 2.00, "cr": 0.10},
}

def family(model):
    m = (model or "").lower()
    if "opus" in m: return "opus"
    if "sonnet" in m: return "sonnet"
    if "haiku" in m: return "haiku"
    return None

# Aggregate per model
agg = {}  # model -> dict
for line in open(jsonl):
    try:
        obj = json.loads(line)
    except Exception:
        continue
    msg = obj.get("message", {})
    u = msg.get("usage")
    m = msg.get("model")
    if not u or not m:
        continue
    a = agg.setdefault(m, {
        "messages": 0, "in": 0, "out": 0,
        "cache_read": 0, "cache_write_5m": 0, "cache_write_1h": 0,
    })
    a["messages"] += 1
    a["in"] += int(u.get("input_tokens", 0) or 0)
    a["out"] += int(u.get("output_tokens", 0) or 0)
    a["cache_read"] += int(u.get("cache_read_input_tokens", 0) or 0)
    cc = u.get("cache_creation") or {}
    a["cache_write_5m"] += int(cc.get("ephemeral_5m_input_tokens", 0) or 0)
    a["cache_write_1h"] += int(cc.get("ephemeral_1h_input_tokens", 0) or 0)

# Cost per model
def cost(model, a):
    fam = family(model)
    if not fam:
        return None, None
    p = PRICE[fam]
    c = (a["in"] * p["in"]
       + a["out"] * p["out"]
       + a["cache_read"] * p["cr"]
       + a["cache_write_5m"] * p["cw5"]
       + a["cache_write_1h"] * p["cw1h"]) / 1_000_000.0
    return fam, c

def fmt_int(n):
    return f"{n:,}".replace(",", " ")

# Build markdown block
total_cost = 0.0
total_in = total_out = total_cr = total_cw = 0
rows = []
for model in sorted(agg):
    a = agg[model]
    fam, c = cost(model, a)
    cw_total = a["cache_write_5m"] + a["cache_write_1h"]
    if c is not None:
        total_cost += c
    total_in += a["in"]; total_out += a["out"]
    total_cr += a["cache_read"]; total_cw += cw_total
    rows.append({
        "model": model, "fam": fam, "msgs": a["messages"],
        "in": a["in"], "out": a["out"],
        "cr": a["cache_read"], "cw": cw_total,
        "cost": c,
    })

block = []
block.append("")
block.append("---")
block.append("")
block.append("## Auto-run usage")
block.append("")
block.append(f"- **Session**: `{sid}`")
block.append(f"- **Result**: `{result}` (exit={exit_code})")
if wall_sec not in ("?", "", None):
    try:
        s = int(wall_sec); m, s = divmod(s, 60); h, m = divmod(m, 60)
        block.append(f"- **Wall**: {h:d}h {m:02d}m {s:02d}s ({wall_sec}s)")
    except Exception:
        block.append(f"- **Wall**: {wall_sec}s")
block.append(f"- **Finished**: {datetime.now().isoformat(timespec='seconds')}")
block.append("")
block.append("| Model | Msgs | Input | Output | Cache read | Cache write | Cost (≈USD) |")
block.append("|---|--:|--:|--:|--:|--:|--:|")
for r in rows:
    cost_s = f"${r['cost']:.4f}" if r['cost'] is not None else "n/a"
    block.append(f"| `{r['model']}` | {r['msgs']} | {fmt_int(r['in'])} | {fmt_int(r['out'])} | {fmt_int(r['cr'])} | {fmt_int(r['cw'])} | {cost_s} |")
block.append(f"| **Σ total** | — | **{fmt_int(total_in)}** | **{fmt_int(total_out)}** | **{fmt_int(total_cr)}** | **{fmt_int(total_cw)}** | **${total_cost:.4f}** |")
block.append("")
block.append(f"_Prices approximate — see `summarize-task-usage.sh` PRICE table._")
block.append("")

text = "\n".join(block)
print(text)

# Append to task file (if found and not already appended for this session)
if task_file and os.path.isfile(task_file):
    existing = open(task_file, encoding="utf-8").read()
    marker = f"**Session**: `{sid}`"
    if marker in existing:
        print(f"\n[summarize] task file already contains this session's stats — skipping append: {task_file}", file=sys.stderr)
    else:
        with open(task_file, "a", encoding="utf-8") as f:
            f.write(text)
        print(f"\n[summarize] appended to: {task_file}", file=sys.stderr)
else:
    print(f"\n[summarize] task file not found, skipping append (hint was: {sys.argv[2]})", file=sys.stderr)
PY
