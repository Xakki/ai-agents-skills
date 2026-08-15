#!/bin/bash
# Claude Code status line: model, launch dir, git branch, uncommitted work,
# context window usage, session token spend, and the current PWD last.
# The same hook also renders TEAMMATE sessions (Agent/teammate tasks): those get
# the compact subagent form (name · model · ctx · tok, no dirs/git) - a teammate
# row is about the agent, not its checkout. Discriminator: only teammate payloads
# carry .agent_type / .agent.name; a missing signal falls through to the lead form.
# Must never error out or hang the prompt render - every lookup degrades to
# empty on failure; every git invocation is capped with `timeout 2`.

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
launch_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
agent_name=$(echo "$input" | jq -r '.agent.name // .agent_type // empty')

C_RESET="\033[00m"
C_NAME="\033[01;37m"
C_MODEL="\033[01;36m"
C_CWD="\033[01;34m"
C_GIT="\033[01;33m"
C_DIRTY="\033[01;31m"
C_CTX="\033[01;35m"
C_TOK="\033[01;32m"

# Current context window fill (pre-calculated by Claude Code).
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')

ctx_str=""
if [ -n "$used_pct" ]; then
  ctx_str=$(printf "ctx %.0f%%" "$used_pct")
  if [ -n "$total_in" ] && [ -n "$ctx_size" ] && [ "$ctx_size" != "0" ]; then
    ctx_str="$ctx_str ($total_in/$ctx_size)"
  fi
fi

# Total tokens spent this session: sum usage across every assistant turn in the transcript
# (includes cache_read/cache_creation, so it reflects real API token spend, not just context fill).
session_tokens=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  session_tokens=$(jq -s '
    [.[] | select(.message.usage != null) |
      (.message.usage.input_tokens // 0) +
      (.message.usage.output_tokens // 0) +
      (.message.usage.cache_creation_input_tokens // 0) +
      (.message.usage.cache_read_input_tokens // 0)
    ] | add // 0
  ' "$transcript" 2>/dev/null)
fi

tok_h=""
if [ -n "$session_tokens" ] && [ "$session_tokens" != "0" ]; then
  tok_h=$(awk -v n="$session_tokens" 'BEGIN{
    if (n>=1000000) printf "%.1fM", n/1000000;
    else if (n>=1000) printf "%.1fk", n/1000;
    else printf "%d", n;
  }')
fi

# Teammate/subagent session: compact form, and skip the git calls entirely.
if [ -n "$agent_name" ]; then
  out="${C_NAME}${agent_name}${C_RESET}"
  [ -n "$model" ]   && out="$out  ${C_MODEL}${model}${C_RESET}"
  [ -n "$ctx_str" ] && out="$out  ${C_CTX}${ctx_str}${C_RESET}"
  [ -n "$tok_h" ]   && out="$out  ${C_TOK}${tok_h} tok${C_RESET}"
  printf '%b' "$out"
  exit 0
fi

# Shorten a path for display: $HOME -> ~, then if more than 2 path segments
# remain, keep only the last 2, prefixed with "…". Root "/" stays "/".
shorten_path() {
  local p="$1" disp s n
  local -a segs parts
  [ -z "$p" ] && return
  disp="$p"
  if [ -n "$HOME" ]; then
    if [ "$p" = "$HOME" ]; then
      disp="~"
    elif [[ "$p" == "$HOME"/* ]]; then
      disp="~${p#"$HOME"}"
    fi
  fi
  segs=()
  IFS='/' read -ra parts <<< "$disp"
  for s in "${parts[@]}"; do
    [ -n "$s" ] && segs+=("$s")
  done
  n=${#segs[@]}
  if [ "$n" -eq 0 ]; then
    printf '/'
  elif [ "$n" -gt 2 ]; then
    printf '…/%s/%s' "${segs[$((n-2))]}" "${segs[$((n-1))]}"
  else
    printf '%s' "$disp"
  fi
}

# Launch dir shown in full (that is where the session was started); the live PWD
# goes last, shortened - and only when it actually differs from the launch dir,
# otherwise it just repeats what is already on the left. Trailing slashes are
# stripped before comparing so "/x" and "/x/" count as the same dir.
launch_str="$launch_dir"
pwd_str=""
if [ -n "$cwd" ] && [ -n "$launch_dir" ] && [ "${cwd%/}" != "${launch_dir%/}" ]; then
  pwd_str="pwd $(shorten_path "$cwd")"
fi
[ -z "$launch_str" ] && launch_str=$(shorten_path "$cwd")

# Git branch + uncommitted-work summary for cwd; --no-optional-locks and
# `timeout 2` on every invocation so this never contends with or hangs behind
# a running git command (even on a large repo).
branch=""
dirty_str=""
if [ -n "$cwd" ] && timeout 2 git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(timeout 2 git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(timeout 2 git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)

  file_count=$(timeout 2 git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  case "$file_count" in ''|*[!0-9]*) file_count=0 ;; esac

  if timeout 2 git -C "$cwd" --no-optional-locks rev-parse HEAD >/dev/null 2>&1; then
    numstat=$(timeout 2 git -C "$cwd" --no-optional-locks diff HEAD --numstat 2>/dev/null)
  else
    numstat=$(timeout 2 git -C "$cwd" --no-optional-locks diff --numstat 2>/dev/null)
  fi

  added=0
  removed=0
  if [ -n "$numstat" ]; then
    while IFS=$'\t' read -r a r _; do
      case "$a" in ''|*[!0-9]*) continue ;; esac
      case "$r" in ''|*[!0-9]*) continue ;; esac
      added=$((added + a))
      removed=$((removed + r))
    done <<< "$numstat"
  fi

  if [ "$file_count" -gt 0 ]; then
    dirty_str="${file_count}f"
    if [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; then
      dirty_str="$dirty_str +${added}/-${removed}"
    fi
  fi
fi

out="${C_MODEL}${model}${C_RESET}"
[ -n "$launch_str" ] && out="$out  ${C_CWD}${launch_str}${C_RESET}"
[ -n "$branch" ] && out="$out  ${C_GIT}${branch}${C_RESET}"
[ -n "$dirty_str" ] && out="$out  ${C_DIRTY}${dirty_str}${C_RESET}"
[ -n "$ctx_str" ] && out="$out  ${C_CTX}${ctx_str}${C_RESET}"
[ -n "$tok_h" ] && out="$out  ${C_TOK}${tok_h} tok${C_RESET}"
[ -n "$pwd_str" ] && out="$out  ${C_CWD}${pwd_str}${C_RESET}"

printf '%b' "$out"
