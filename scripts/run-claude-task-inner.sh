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
TS="$(date +%Y%m%d_%H%M%S)"
# Logs MUST live OUTSIDE the repo. The autonomous prompt previously ran
# `git stash push -u`, which stashed the open --debug-file mid-write and
# crashed claude with ENOENT (appendFileSync to a vanished file).
LOG_DIR="${HOME:-/home/coder}/.local/state/claude-auto-runs/${PROJECT_NAME}"
DEBUG_LOG="$LOG_DIR/${TS}_${TASK_NAME}.debug.log"
META_LOG="$LOG_DIR/${TS}_${TASK_NAME}.meta.log"
# Predetermined session ID so user can `claude --resume <id>` to inspect history.
SESSION_ID="$(cat /proc/sys/kernel/random/uuid)"

mkdir -p "$LOG_DIR"
cd "$REPO"

PROMPT=$(cat <<PROMPT_EOF
Выполни задачу из файла \`${TASK_FILE}\` полностью автономно (без вопросов пользователю — это запуск по таймеру).

Семантика kanban-стадий и переходов задана в \`.claude/skills/kanban/SKILL.md\`. Маршрутизация сабагентов — в разделе \`Сабагенты и делегирование\` корневого CLAUDE.md.

Алгоритм:

1. **Refuse on dirty.** \`git status --porcelain\`. Если есть ЛЮБЫЕ модификации (M/A/D/R/??) — НЕ стэшь, не очищай. Распечатай ровно:
   \`AUTO-RUN-RESULT: skip: ${TASK_NAME}: working tree dirty, manual intervention required\`
   и заверши работу немедленно.

2. **Sanity.** Убедись, что \`${TASK_FILE}\` существует И находится в \`.claude/kanban/todo/\`. Если нет (уже двигалась, удалена, в другом стейдже) — распечатай:
   \`AUTO-RUN-RESULT: skip: ${TASK_NAME}: not in todo/\`
   и заверши работу.

3. **todo → progress** (старт имплементации). Отдельным коммитом:
   \`git mv ${TASK_FILE} .claude/kanban/progress/\$(basename ${TASK_FILE})\`
   \`git commit -m "task: start ${TASK_NAME} (todo→progress)"\`
   Дальше работай с новым путём \`.claude/kanban/progress/\$(basename ${TASK_FILE})\`.

4. **Имплементация.** Прочитай карточку. Делегируй имплементационному сабагенту по правилам CLAUDE.md (\`python-backend\`, \`go-client\`, \`browser-extension\`, \`frontend-spa\`, \`infra-devops\`). Если задача требует анализа безопасности — также \`security-auditor\` (read-only).
   Каждое значимое подзадание — обновление секции **Execution Log** в файле карточки + git-коммит по соглашениям проекта (scope: \`api|goclient|ext|infra|db|docs\`). Сообщения — короткие, в стиле последних коммитов.

5. **qa-check.** Запусти skill **qa-check** (lint + test по затронутым модулям).
   - Если красный — НЕ переноси карточку. Оставь её в \`progress/\`. Зафиксируй проблему в Execution Log + коммит \`task: ${TASK_NAME} qa-check failed\`. Перейди к шагу 10 с \`AUTO-RUN-RESULT: fail\` (шаг 9 цепочки пропускается на fail/skip).

6. **progress → test** (передача тестеру). Отдельным коммитом:
   \`git mv .claude/kanban/progress/\$(basename ${TASK_FILE}) .claude/kanban/test/\$(basename ${TASK_FILE})\`
   \`git commit -m "task: review ${TASK_NAME} (progress→test)"\`

7. **Проверка тестером.** Делегируй \`test-engineer\`:
   - сверить реализацию с разделом **Acceptance Criteria** карточки;
   - запустить релевантные тесты (юнит / интеграционные / e2e — что применимо);
   - если есть e2e-сценарии — прогнать только те, что покрывают эту карточку (не весь suite, если он тяжёлый).
   В Execution Log — что именно проверял + результат.

8. **Финализация (test → ready).**
   - **Если test-engineer всё подтвердил:** отдельным коммитом
     \`git mv .claude/kanban/test/\$(basename ${TASK_FILE}) .claude/kanban/ready/\$(basename ${TASK_FILE})\`
     \`git commit -m "task: ready ${TASK_NAME} (test→ready)"\`
     Перейди к шагу 9 (цепочка), затем к шагу 10 с \`AUTO-RUN-RESULT: ok\`.
   - **Если test-engineer нашёл проблемы:** карточка остаётся в \`test/\`. В Execution Log — конкретные находки. Сделай коммит \`task: ${TASK_NAME} review found issues\`. Перейди к шагу 10 с \`AUTO-RUN-RESULT: fail\` (шаг 9 цепочки пропускается на fail/skip).

9. **Цепочка (только при результате \`ok\`).** ОБЯЗАТЕЛЬНО до шага 10. На fail/skip — пропусти шаг 9 целиком и сразу к шагу 10 (НЕ печатай \`AUTO-RUN-NEXT\` — он только для \`ok\`).

   Запусти ВЕСЬ блок ниже как **один** \`Bash\`-tool-вызов (чтобы переменная \`NEXT\` не потерялась между вызовами). Абсолютные пути уже подставлены:

   \`\`\`bash
   # NB: НЕ ставь \`set -u\`. Bash-snapshot Claude Code переопределяет grep()
   # и обращается внутри к \$ZSH_VERSION (не задано под bash); с set -u функция
   # роняется и весь пайплайн ls|grep|sort|head даёт пусто → ложное
   # "AUTO-RUN-NEXT: none". Поэтому используем чистый bash-glob (он сам
   # лекс-сортирует) и не зависим от утилит, которые snapshot мог подменить.
   if ! systemctl is-active --quiet atd; then
       echo "[chain] WARN: atd inactive — chain stops"
       echo "AUTO-RUN-NEXT: none"
       exit 0
   fi
   if [ -n "\$(git status --porcelain)" ]; then
       echo "[chain] WARN: dirty tree, chain stops"
       git status --short
       echo "AUTO-RUN-NEXT: none"
       exit 0
   fi
   shopt -s nullglob
   LC_COLLATE=C
   _todo=( ${REPO}/.claude/kanban/todo/*.md )
   shopt -u nullglob
   if [ \${#_todo[@]} -eq 0 ]; then
       echo "[chain] todo/ empty — chain ends"
       echo "AUTO-RUN-NEXT: none"
       exit 0
   fi
   NEXT="\${_todo[0]##*/}"
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

   После этого блока — сразу шаг 10 (финальный маркер). НЕ запускай \`at\` повторно.

10. **Завершение.**
    - НЕ пушить, НЕ создавать PR, НЕ мержить — все изменения остаются локально на текущей ветке.
    - Распечатай ровно одну итоговую строку (последняя строка ответа):
      \`AUTO-RUN-RESULT: <ok|fail|skip>: ${TASK_NAME}: <короткая причина>\`

Жёсткие запреты:
- Никакого \`git stash\`, \`git checkout -- .\`, \`git reset --hard\`, \`git clean\`.
- Никаких пропусков стадий (todo→test, progress→ready и т. п.).
- Один \`git mv\` = один отдельный коммит. Контент-правки и переезды карточки не смешивать.
- \`--no-verify\` не использовать.
- НИКОГДА не двигать карточку в \`.claude/kanban/done/\`. Финальная стадия автономного запуска — \`ready/\`; перенос \`ready→done\` делает пользователь вручную.
- НЕ ставить второй \`at\` для той же или другой карточки — ровно один \`at\` за один запуск, только на шаге 9 при \`ok\`.
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
    LAST_RESULT=$(grep -hoE 'AUTO-RUN-RESULT: (ok|fail|skip):' "$JSONL" | tail -1 | sed -E 's/.*: ([a-z]+):/\1/')
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

# If the appended task file is the only dirty change, commit it so the
# refuse-on-dirty contract holds for the next at-job.
cd "$REPO"
DIRTY=$(git status --porcelain)
if [ -n "$DIRTY" ]; then
    # commit only if EVERY dirty path is a kanban task .md (auto-stats append)
    SAFE=true
    while IFS= read -r line; do
        path="${line:3}"
        case "$path" in
            .claude/kanban/*/*.md) ;;
            *) SAFE=false; break ;;
        esac
    done <<< "$DIRTY"
    if [ "$SAFE" = true ]; then
        git add -A .claude/kanban/
        git commit -m "chore(auto-run): append usage stats for $TASK_NAME" \
                   -m "session: $SESSION_ID, result: $RESULT, wall: ${WALL_SEC}s, exit: $EXIT" \
            >> "$META_LOG" 2>&1 \
            && echo "[inner] committed usage-stats append" \
            || echo "[inner] WARN: could not commit usage-stats append (see meta.log)"
    else
        echo "[inner] WARN: working tree has non-kanban dirt — leaving as-is for manual review"
        git status --short
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
        ok:*)
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

echo
echo ">>> Window kept open. Press Enter to close."
read -r _
