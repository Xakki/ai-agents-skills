#!/bin/bash
# Claude Code SUBAGENT status line: one row per teammate in the agent panel
# (name · model · ctx% · tokens). No cwd/git segments — a teammate row is about
# the agent, not its checkout, and this keeps the panel free of per-row git calls.
# Batched invocation: stdin carries tasks[] for the whole panel at once; emit one
# {"id","content"} JSON line per row we override (omit a row → keep its default).
# Must never error/hang; every lookup degrades to empty. Shares the palette with
# statusline-command.sh so lead + teammate rows read the same.

input=$(cat)

C_RESET=$'\033[00m'
C_NAME=$'\033[01;37m'
C_MODEL=$'\033[01;36m'
C_GIT=$'\033[01;33m'
C_CTX=$'\033[01;35m'
C_TOK=$'\033[01;32m'

# One record per task, US-separated (0x1F). Tab is IFS-whitespace, so empty
# name/model/cwd fields would collapse and shift columns — a non-whitespace
# separator preserves empty fields. model/ctxsize absent → "" / 0.
echo "$input" | jq -r '
  .tasks[]? | [.id, (.name // ""), (.model // ""), (.cwd // ""),
               (.tokenCount // 0 | tostring), (.contextWindowSize // 0 | tostring)]
  | join("")' 2>/dev/null |
while IFS=$'\037' read -r id name model cwd tok ctxsize; do
  [ -z "$id" ] && continue

  # Per-agent context fill from tokenCount/contextWindowSize (no pre-calc field here).
  ctx_str=""
  if [ -n "$ctxsize" ] && [ "$ctxsize" != "0" ]; then
    ctx_str=$(awk -v t="$tok" -v s="$ctxsize" 'BEGIN{ if (s>0) printf "ctx %.0f%%", (t/s)*100 }')
  fi

  tok_h=""
  if [ -n "$tok" ] && [ "$tok" != "0" ]; then
    tok_h=$(awk -v n="$tok" 'BEGIN{
      if (n>=1000000) printf "%.1fM", n/1000000;
      else if (n>=1000) printf "%.1fk", n/1000;
      else printf "%d", n;
    }')
  fi

  content="${C_NAME}${name}${C_RESET}"
  [ -n "$model" ]   && content="$content  ${C_MODEL}${model}${C_RESET}"
  [ -n "$ctx_str" ] && content="$content  ${C_CTX}${ctx_str}${C_RESET}"
  [ -n "$tok_h" ]   && content="$content  ${C_TOK}${tok_h} tok${C_RESET}"

  # jq encodes the embedded ESC bytes safely into the JSON string.
  jq -cn --arg id "$id" --arg content "$content" '{id:$id, content:$content}'
done
