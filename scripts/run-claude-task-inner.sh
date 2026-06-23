#!/usr/bin/env bash
# Runs INSIDE the spawned tmux window. Launches interactive claude with an
# autonomous prompt. Window stays open after claude exits.
#
# Universal: SCRIPT_DIR locates sibling scripts (works from the plugin cache
# too). PROJECT_DIR is derived from the task-file argument, not from this
# script's location — the card always lives at
# <repo>/.claude/kanban/<stage>/<name>.md, so the repo is three levels up.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TASK_FILE="$1"
TASK_NAME="$(basename "$TASK_FILE" .md)"
PROJECT_DIR="$(cd "$(dirname "$TASK_FILE")/../../.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
# Claude Code stores session JSONL under ~/.claude/projects/<encoded-path>/,
# where <encoded-path> = absolute project dir with every '/' replaced by '-'.
CLAUDE_PROJECT_PATH="$(printf '%s' "$PROJECT_DIR" | tr '/' '-')"
REPO="$PROJECT_DIR"
BASE_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
case "$BASE_BRANCH" in
    task/*)
        echo "ERROR: auto-run started on a task/* branch ($BASE_BRANCH) — refusing; check out the base branch first" >&2
        exit 1
        ;;
esac
TS="$(date +%Y%m%d_%H%M%S)"
# Logs MUST live OUTSIDE the repo. The autonomous prompt previously ran
# `git stash push -u`, which stashed the open --debug-file mid-write and
# crashed claude with ENOENT (appendFileSync to a vanished file).
LOG_DIR="${HOME:-/home/coder}/.local/state/claude-auto-runs/${PROJECT_NAME}"
DEBUG_LOG="$LOG_DIR/${TS}_${TASK_NAME}.debug.log"
META_LOG="$LOG_DIR/${TS}_${TASK_NAME}.meta.log"
# Baseline dirty-set captured before claude runs; read by chain step 9 + end-of-run
# auto-commit to distinguish pre-existing dirt from uncommitted task work.
BASELINE_FILE="$LOG_DIR/.baseline-dirty-${TS}"
# Predetermined session ID so user can `claude --resume <id>` to inspect history.
SESSION_ID="$(cat /proc/sys/kernel/random/uuid)"

mkdir -p "$LOG_DIR"
cd "$REPO"
git status --porcelain > "$BASELINE_FILE" 2>/dev/null || true

PROMPT=$(cat <<PROMPT_EOF
Выполни задачу из файла \`${TASK_FILE}\`. Автономный запуск — мелкие вопросы решай сам; останавливайся только через парковку (триггеры ниже).

Сабагенты и kanban-правила → CLAUDE.md + \`.claude/skills/kanban/SKILL.md\`.

**Парковка (вместо любой остановки).** Триггеры: (а) проблема-блокер (нет credentials, неразрешимый конфликт, потенциально разрушительная операция, дорогая неоднозначность); (б) решение, меняющее архитектуру/контракт/публичное поведение; (в) qa-check красный (reason=\`qa-fail\`), ревью нашло проблемы (reason=\`review-fail\`), конфликт при мерже (reason=\`merge-conflict\`).

Процедура парковки (reason ∈ qa-fail|review-fail|blocker|question|merge-conflict):
  1. Если на базовой ветке (только merge-conflict): \`git switch "task/${TASK_NAME}"\`.
  2. Аннотируй карточку (в текущей стадии — progress/|test/|ready/): добавь \`## ⏸ Parked — <reason>\` с веткой \`task/${TASK_NAME}\`, описанием проблемы и вариантами.
  3. Один Bash-вызов: \`"${SCRIPT_DIR}/park-task.sh" ".claude/kanban/<stage>/${TASK_NAME}.md" "${BASE_BRANCH}" "${BASELINE_FILE}" "${SESSION_ID}" "${LOG_DIR}" <reason>\` (подставь реальную стадию: \`progress\`, \`test\` или \`ready\` для merge-conflict).
  4. tg-notify (только главный поток, навык tg-notify): заголовок \`auto-run ${TASK_NAME}: parked (<reason>)\`, тело — проблема + варианты + \`claude --resume ${SESSION_ID}\`.
  5. → **шаг 9**, затем **шаг 10** с \`AUTO-RUN-RESULT: park: ${TASK_NAME}: parked (<reason>)\`.

**tg-notify:** только главный поток; только при park (шаг 4 выше). ok и skip — не слать.

Алгоритм:

1. **Dirty tree — не повод останавливаться.** НЕ стэшь, не сбрасывай. Стейдж ТОЛЬКО явными путями: \`git add <пути>\` → \`git commit\`. НИКОГДА \`git add -A\`, \`git add .\`, \`git add -u\`, \`git commit -a\`.

2. **Sanity.** Если \`${TASK_FILE}\` не существует или не в \`todo/\` → сразу **шаг 9**, затем **шаг 10** с \`AUTO-RUN-RESULT: skip: ${TASK_NAME}: not in todo/\`.

3. **Start** (на базовой ветке):
   \`git mv ${TASK_FILE} .claude/kanban/progress/\$(basename ${TASK_FILE})\`
   \`git commit -m "task: start ${TASK_NAME} (todo→progress)"\`
   \`git switch -c "task/${TASK_NAME}"\`
   Далее вся работа — на ветке \`task/${TASK_NAME}\`.

4. **Имплементация.** Делегируй сабагенту по CLAUDE.md (\`python-backend\`, \`go-client\`, \`browser-extension\`, \`frontend-spa\`, \`infra-devops\`; безопасность — \`security-auditor\` read-only). Каждое подзадание → Execution Log + path-scoped коммит: \`git add <явные пути>\` → \`git commit -m "<scope>: …"\` (scope: \`api|goclient|ext|infra|db|docs\`).

5. **qa-check** (skill qa-check). Красный → Execution Log + коммит \`task: ${TASK_NAME} qa-check failed\` → **парковка (qa-fail)**.

6. **progress → test:**
   \`git mv .claude/kanban/progress/\$(basename ${TASK_FILE}) .claude/kanban/test/\$(basename ${TASK_FILE})\`
   \`git commit -m "task: review ${TASK_NAME} (progress→test)"\`

7. **Test** (делегируй \`test-engineer\`: AC + релевантные тесты). Execution Log — что проверял + результат. Нашёл проблемы → **парковка (review-fail)**.

8. **Финализация (test → ready + merge):**
   \`git mv .claude/kanban/test/\$(basename ${TASK_FILE}) .claude/kanban/ready/\$(basename ${TASK_FILE})\`
   \`git commit -m "task: ready ${TASK_NAME} (test→ready)"\`
   \`git switch ${BASE_BRANCH}\`
   \`git merge --no-ff --no-edit "task/${TASK_NAME}"\` — при неудаче: если \`MERGE_HEAD\` существует (конфликт, мерж начался) → \`git merge --abort\` → **парковка (merge-conflict)**; если \`MERGE_HEAD\` отсутствует (мерж отклонён до старта) → **парковка (merge-conflict)** напрямую без \`--abort\`.
   \`git branch -d "task/${TASK_NAME}"\`
   → **шаг 9**, затем **шаг 10** с \`AUTO-RUN-RESULT: ok: ${TASK_NAME}: completed\`.

9. **Цепочка (при ЛЮБОМ результате: ok/park/skip).** ОБЯЗАТЕЛЬНО до шага 10. Один Bash-вызов:

   \`\`\`bash
   # НЕ ставь set -u (snapshot-caveat: Claude Code патчит grep(), обращаясь к $ZSH_VERSION).
   if ! systemctl is-active --quiet atd; then
       echo "[chain] WARN: atd inactive — chain stops"
       echo "AUTO-RUN-NEXT: none"
       exit 0
   fi
   _cur_paths=\$(git status --porcelain 2>/dev/null | cut -c4- | sort -u)
   _base_paths=\$(cut -c4- "${BASELINE_FILE}" 2>/dev/null | sort -u)
   if [ -n "\$_cur_paths" ]; then
       _new_dirt=\$(comm -23 <(printf '%s\n' "\$_cur_paths") <([ -n "\$_base_paths" ] && printf '%s\n' "\$_base_paths" || true))
       if [ -n "\$_new_dirt" ]; then
           echo "[chain] WARN: uncommitted task changes beyond baseline — chain stops"
           printf '%s\n' "\$_new_dirt"
           echo "AUTO-RUN-NEXT: none"
           exit 0
       fi
   fi
   NEXT=\$("${SCRIPT_DIR}/select-next-task.sh" "${REPO}" "${LOG_DIR}/.parked" "${TASK_NAME}")
   if [ "\$NEXT" = "none" ]; then
       echo "[chain] no eligible next card — chain ends"
       echo "AUTO-RUN-NEXT: none"
       exit 0
   fi
   AT_OUT=\$(echo "${SCRIPT_DIR}/run-claude-task.sh ${REPO}/.claude/kanban/todo/\$NEXT" \\
       | at -t \$(date -d '+20 minutes' +%Y%m%d%H%M) 2>&1)
   AT_RC=\$?
   echo "\$AT_OUT"
   if [ \$AT_RC -ne 0 ]; then
       echo "[chain] WARN: at failed (rc=\$AT_RC) for \$NEXT"
       echo "AUTO-RUN-NEXT: none"
   else
       echo "[chain] enqueued next at +20min: \$NEXT"
       echo "AUTO-RUN-NEXT: \$NEXT"
   fi
   \`\`\`
   Сразу к шагу 10. НЕ запускай \`at\` повторно.

10. **Завершение.** НЕ пушить, НЕ PR, НЕ мержить вне шага 8. Последняя строка ответа:
    \`AUTO-RUN-RESULT: <ok|park|skip>: ${TASK_NAME}: <причина>\`

Жёсткие запреты:
- \`git add -A\`, \`git add .\`, \`git add -u\`, \`git commit -a\` — только явные пути.
- \`git stash\`, \`git checkout -- .\`, \`git reset --hard\`, \`git clean\`.
- Пропуски стадий (todo→test и т. п.).
- Один \`git mv\` = один коммит (не смешивать с контент-правками, кроме fail-коммитов).
- \`--no-verify\`.
- Карточку в \`done/\` — только пользователь.
- Второй \`at\` за один запуск.
- \`wip(park)\` коммит на базовой ветке — только через park-task.sh на \`task/*\`.
- \`AskUserQuestion\` в автономном потоке.
PROMPT_EOF
)

{
    echo "================================================================"
    echo "=== AUTO RUN START $(date)"
    echo "=== TASK   : $TASK_NAME"
    echo "=== FILE   : $TASK_FILE"
    echo "=== HEAD   : $(git rev-parse --short HEAD 2>/dev/null) on $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    echo "=== SESSION: $SESSION_ID"
    echo "=== RESUME : claude --resume $SESSION_ID"
    echo "=== VIEW   : $SCRIPT_DIR/view-task-history.sh $SESSION_ID"
    echo "=== DEBUG  : $DEBUG_LOG"
    echo "================================================================"
} | tee -a "$META_LOG"

START_EPOCH=$(date +%s)
claude --dangerously-skip-permissions \
    --session-id "$SESSION_ID" \
    --debug-file "$DEBUG_LOG" \
    "$PROMPT"
EXIT=$?
WALL_SEC=$(( $(date +%s) - START_EPOCH ))

# Detect run result by grepping the JSONL for the final AUTO-RUN-RESULT marker.
# Agent often wraps the marker in backticks (`AUTO-RUN-RESULT: ok: ...`); accept
# any preceding char, anchor on canonical "AUTO-RUN-RESULT: <verdict>:" shape.
RESULT="unknown"
JSONL="${HOME:-/home/coder}/.claude/projects/${CLAUDE_PROJECT_PATH}/${SESSION_ID}.jsonl"
if [ -f "$JSONL" ]; then
    LAST_RESULT=$(grep -hoE 'AUTO-RUN-RESULT: (ok|skip|park):' "$JSONL" | tail -1 | sed -E 's/.*: ([a-z]+):/\1/')
    [ -n "$LAST_RESULT" ] && RESULT="$LAST_RESULT"
fi

{
    echo
    echo "================================================================"
    echo "=== AUTO RUN END $(date), claude exit=$EXIT, result=$RESULT, wall=${WALL_SEC}s"
    echo "================================================================"
} | tee -a "$META_LOG"

# Token/cost summary → stdout + appended to task file.
echo
echo "================================================================"
echo "=== USAGE SUMMARY"
echo "================================================================"
"$SCRIPT_DIR/summarize-task-usage.sh" "$SESSION_ID" "$TASK_FILE" "$WALL_SEC" "$EXIT" "$RESULT" 2>&1 | tee -a "$META_LOG"

# Commit only the usage-stats append (new kanban .md changes not in baseline).
# Never bulk-stage: only paths that (a) weren't dirty before this run and
# (b) are kanban .md files get staged and committed.
cd "$REPO"
DIRTY_PATHS=$(git status --porcelain 2>/dev/null | cut -c4- | sort -u)
if [ -n "$DIRTY_PATHS" ]; then
    BASE_PATHS=$(cut -c4- "$BASELINE_FILE" 2>/dev/null | sort -u)
    EXTRA_PATHS=$(comm -23 \
        <(printf '%s\n' "$DIRTY_PATHS") \
        <([ -n "$BASE_PATHS" ] && printf '%s\n' "$BASE_PATHS" || true))
    if [ -z "$EXTRA_PATHS" ]; then
        echo "[inner] all dirty paths pre-existed at task start — no auto-commit needed"
    else
        SAFE=true
        KANBAN_PATHS=()
        while IFS= read -r path; do
            [ -z "$path" ] && continue
            case "$path" in
                .claude/kanban/*/*.md) KANBAN_PATHS+=("$path") ;;
                *) SAFE=false; break ;;
            esac
        done <<< "$EXTRA_PATHS"
        if [ "$SAFE" = true ]; then
            for path in "${KANBAN_PATHS[@]}"; do
                git add -- "$path"
            done
            git commit -m "chore(auto-run): append usage stats for $TASK_NAME" \
                       -m "session: $SESSION_ID, result: $RESULT, wall: ${WALL_SEC}s, exit: $EXIT" \
                >> "$META_LOG" 2>&1 \
                && echo "[inner] committed usage-stats append" \
                || echo "[inner] WARN: could not commit usage-stats append (see meta.log)"
        else
            echo "[inner] WARN: working tree has non-kanban task changes — leaving as-is for manual review"
            git status --short
        fi
    fi
fi

# === Chain verification (agent enqueues at-job in step 9 of the prompt) ===
# Runs AFTER claude exits (i.e. after the user closes the interactive window).
# Does NOT enqueue — chain ownership lives in the prompt (avoids double-booking).
{
    echo
    echo "================================================================"
    echo "=== CHAIN (verify)"
    echo "================================================================"
    NEXT_MARK=""
    if [ -f "$JSONL" ]; then
        # Tight: basename = [A-Za-z0-9._-]+ OR exact literal "none".
        # Without this the agent's prose ('AUTO-RUN-NEXT: none`') leaks the
        # trailing backtick into NEXT_MARK and we go down the ok:* enqueue
        # branch trying to verify a job for "none`".
        NEXT_MARK=$(grep -hoE 'AUTO-RUN-NEXT: ([A-Za-z0-9._-]+|none)' "$JSONL" | tail -1 | sed -E 's/^AUTO-RUN-NEXT: //')
    fi
    case "$RESULT:$NEXT_MARK" in
        ok:none|ok:)
            if [ "$NEXT_MARK" = "none" ]; then
                echo "[chain] result=ok, AUTO-RUN-NEXT=none — chain ended cleanly (no next card or atd off)"
            else
                echo "[chain] WARN: result=ok but no AUTO-RUN-NEXT marker — agent skipped step 9 of the prompt"
            fi
            ;;
        park:none|park:)
            if [ "$NEXT_MARK" = "none" ]; then
                echo "[chain] result=park, AUTO-RUN-NEXT=none — parked last card; no eligible next (clean end)"
            else
                echo "[chain] ERROR: result=park but no AUTO-RUN-NEXT marker — agent skipped step 9; chain was NOT advanced"
                echo "[chain]   re-arm manually:"
                echo "[chain]     /schedule-tasks  (or: echo \"$SCRIPT_DIR/run-claude-task.sh $REPO/.claude/kanban/todo/<NEXT>.md\" | at -t \$(date -d '+20 minutes' +%Y%m%d%H%M))"
            fi
            ;;
        skip:none|skip:)
            if [ "$NEXT_MARK" = "none" ]; then
                echo "[chain] result=skip, AUTO-RUN-NEXT=none — chain ended cleanly (no next card or atd off)"
            else
                echo "[chain] WARN: result=skip but no AUTO-RUN-NEXT marker — agent skipped step 9 of the prompt"
            fi
            ;;
        ok:*|park:*|skip:*)
            # Agent claims it enqueued <NEXT_MARK>. Verify against atq.
            FOUND=""
            for j in $(atq 2>/dev/null | awk '{print $1}'); do
                if at -c "$j" 2>/dev/null | grep -qF "$NEXT_MARK"; then
                    FOUND="$j"
                    break
                fi
            done
            if [ -n "$FOUND" ]; then
                echo "[chain] verified at-job #$FOUND for next card: $NEXT_MARK"
                atq | sort -k 2
            else
                echo "[chain] WARN: agent printed AUTO-RUN-NEXT=$NEXT_MARK but no matching at-job in queue"
                echo "[chain]       re-arm manually:"
                echo "[chain]         echo \"$SCRIPT_DIR/run-claude-task.sh $REPO/.claude/kanban/todo/$NEXT_MARK\" | at -t \$(date -d '+20 minutes' +%Y%m%d%H%M)"
                atq
            fi
            ;;
        *)
            echo "[chain] result=$RESULT — chain stops (no enqueue expected)"
            ;;
    esac
} | tee -a "$META_LOG"

rm -f "$BASELINE_FILE"

echo
echo ">>> Window kept open. Press Enter to close."
read -r _
