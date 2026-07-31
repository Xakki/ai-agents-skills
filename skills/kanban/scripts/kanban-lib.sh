# kanban-lib.sh — shared helpers for the kanban skill's automation scripts.
# Sourced only, NOT executable standalone (no shebang, no `set -euo pipefail`
# of its own — the sourcing script owns that).

KANBAN_STAGES=(grooming todo progress test ready done)

kanban::die() { echo "$1" >&2; exit "${2:-1}"; }

# --- arg / repo resolution --------------------------------------------------

# kanban::strip_repo_flag <out_array_name> <args...>
# Pulls a leading `--repo <path>` off the args (if present) into the global
# KANBAN_REPO_ARG, leaves the rest in the named out array.
kanban::strip_repo_flag() {
  local -n _out="$1"; shift
  KANBAN_REPO_ARG=""
  if [ "${1:-}" = "--repo" ]; then
    [ $# -ge 2 ] || kanban::die "kanban: --repo requires a path argument" 1
    KANBAN_REPO_ARG="$2"
    shift 2
  fi
  _out=("$@")
}

kanban::repo_root() {
  if [ -n "${KANBAN_REPO_ARG:-}" ]; then
    (cd "$KANBAN_REPO_ARG" 2>/dev/null && pwd) || kanban::die "kanban: --repo path not found: $KANBAN_REPO_ARG" 2
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

kanban::board_dir() { printf '%s/.claude/kanban' "$1"; }
kanban::lock_file()  { printf '%s/.claude/kanban.lock' "$1"; }

kanban::stage_index() {
  local s="$1" i
  for i in "${!KANBAN_STAGES[@]}"; do
    if [ "${KANBAN_STAGES[$i]}" = "$s" ]; then
      echo "$i"
      return 0
    fi
  done
  echo -1
  return 1
}

# --- card id parsing ---------------------------------------------------------

# kanban::extract_id <basename-without-.md> -> the card's ID token
# (PREFIX-NUM, or PREFIX-NUM-SUB for a subtask); falls back to the whole
# basename if it doesn't look like a card at all.
kanban::extract_id() {
  local base="$1"
  if [[ "$base" =~ ^([A-Za-z][A-Za-z0-9]*-[0-9]+(-[0-9]{2})?) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$base"
  fi
}

# kanban::card_prefix <basename-without-.md> -> the leading PREFIX, or "" if none
kanban::card_prefix() {
  local base="$1"
  if [[ "$base" =~ ^([A-Za-z][A-Za-z0-9]*)- ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# kanban::max_card_num <repo> <prefix> -> highest existing card number for
# that prefix across the whole board (0 if none).
kanban::max_card_num() {
  local repo="$1" prefix="$2" board f base rest num max=0 n
  board="$(kanban::board_dir "$repo")"
  shopt -s nullglob
  for f in "$board"/*/*.md; do
    base="$(basename "$f" .md)"
    case "$base" in
      "$prefix"-[0-9]*)
        rest="${base#"$prefix"-}"
        num="${rest%%[!0-9]*}"
        [ -n "$num" ] || continue
        n=$((10#$num))
        [ "$n" -gt "$max" ] && max=$n
        ;;
    esac
  done
  shopt -u nullglob
  echo "$max"
}

# kanban::prefix_width <repo> <prefix> -> digit width of the highest-numbered
# existing card for that prefix; 3 if no cards exist for it yet.
kanban::prefix_width() {
  local repo="$1" prefix="$2" board f base rest num maxn=-1 maxw=3 ni
  board="$(kanban::board_dir "$repo")"
  shopt -s nullglob
  for f in "$board"/*/*.md; do
    base="$(basename "$f" .md)"
    case "$base" in
      "$prefix"-[0-9]*)
        rest="${base#"$prefix"-}"
        num="${rest%%[!0-9]*}"
        [ -n "$num" ] || continue
        ni=$((10#$num))
        if [ "$ni" -gt "$maxn" ]; then maxn=$ni; maxw=${#num}; fi
        ;;
    esac
  done
  shopt -u nullglob
  echo "$maxw"
}

# kanban::epic_exists <repo> <epic-id> -> 0 if some card's filename starts
# with "<epic-id>-" (the epic itself or one of its subtasks).
kanban::epic_exists() {
  local repo="$1" epic="$2" board f base
  board="$(kanban::board_dir "$repo")"
  shopt -s nullglob
  for f in "$board"/*/*.md; do
    base="$(basename "$f" .md)"
    case "$base" in
      "$epic"-*) shopt -u nullglob; return 0 ;;
    esac
  done
  shopt -u nullglob
  return 1
}

# kanban::next_sub <repo> <epic-id> -> highest existing subtask number (0 if none)
kanban::next_sub() {
  local repo="$1" epic="$2" board f base rest num max=0 n
  board="$(kanban::board_dir "$repo")"
  shopt -s nullglob
  for f in "$board"/*/*.md; do
    base="$(basename "$f" .md)"
    case "$base" in
      "$epic"-[0-9][0-9]-*)
        rest="${base#"$epic"-}"
        num="${rest%%-*}"
        case "$num" in *[!0-9]*) continue ;; esac
        [ "${#num}" -eq 2 ] || continue
        n=$((10#$num))
        [ "$n" -gt "$max" ] && max=$n
        ;;
    esac
  done
  shopt -u nullglob
  echo "$max"
}

# --- lock file (per-repo, committed) ----------------------------------------

kanban::lock_ensure() {
  local lockfile="$1"
  if [ ! -f "$lockfile" ]; then
    mkdir -p "$(dirname "$lockfile")"
    cat > "$lockfile" <<'EOF'
# kanban ID counters — managed by kanban-id.sh. Commit this file.
EOF
  fi
}

kanban::lock_get_prefix() {
  local lockfile="$1"
  [ -f "$lockfile" ] || return 0
  awk -F'=' '/^prefix=/{sub(/^prefix=/,""); print; exit}' "$lockfile"
}

kanban::lock_get_counter() {
  local lockfile="$1" prefix="$2" v
  [ -f "$lockfile" ] || { echo 0; return 0; }
  v="$(awk -F'=' -v k="$prefix" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$lockfile")"
  if [ -n "$v" ]; then echo "$v"; else echo 0; fi
}

# kanban::lock_upsert <lockfile> <key> <value> — set key=value, preserving
# comments and other keys; appends the key if it isn't present yet.
kanban::lock_upsert() {
  local lockfile="$1" key="$2" value="$3" tmp
  tmp="$(mktemp "${lockfile}.tmp.XXXXXX")"
  if [ -f "$lockfile" ] && grep -q "^${key}=" "$lockfile" 2>/dev/null; then
    awk -F'=' -v k="$key" -v v="$value" 'BEGIN{OFS="="} $1==k{$0=k"="v} {print}' "$lockfile" > "$tmp"
  else
    [ -f "$lockfile" ] && cat "$lockfile" > "$tmp"
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  mv "$tmp" "$lockfile"
}

# --- concurrency: flock on the lock file, mkdir-spinlock fallback -----------

KANBAN_LOCK_MODE=""
KANBAN_LOCK_SPIN=""

# Lock wait budget, seconds. Overridable (tests use a short value so a
# contention case doesn't have to burn the full default wait).
KANBAN_LOCK_TIMEOUT_SEC="${KANBAN_LOCK_TIMEOUT_SEC:-10}"

# kanban::ensure_lock_gitignore <claude-dir> -> idempotently makes sure
# <claude-dir>/.gitignore excludes the transient lock artifacts
# (kanban.lock.flock, kanban.lock.lockdir) that must never be committed —
# unlike kanban.lock itself. Creates the file if missing; if it already
# exists, appends only whichever entries are absent, verbatim as their own
# lines, never rewriting or reordering what's already there (real projects
# already have their own `.claude/` gitignore entries).
kanban::ensure_lock_gitignore() {
  local dir="$1" gi="$1/.gitignore" line
  mkdir -p "$dir" 2>/dev/null || true
  [ -f "$gi" ] || : > "$gi" 2>/dev/null || true
  [ -w "$gi" ] || return 0
  for line in "/kanban.lock.flock" "/kanban.lock.lockdir"; do
    grep -qxF "$line" "$gi" 2>/dev/null || printf '%s\n' "$line" >> "$gi"
  done
}

kanban::_lock_acquire() {
  local lockfile="$1" claude_dir
  claude_dir="$(dirname "$lockfile")"
  mkdir -p "$claude_dir" 2>/dev/null || true
  kanban::ensure_lock_gitignore "$claude_dir"
  if command -v flock >/dev/null 2>&1; then
    # flock a STABLE companion file, never $lockfile itself: lock_upsert
    # replaces $lockfile via mktemp+mv (a new inode each write), so flock-ing
    # it directly is a classic TOCTOU — a process that opened the old inode
    # just before a rename holds a lock disconnected from the live file,
    # letting a concurrent opener of the new inode acquire the "same" lock
    # at the same time (observed as duplicate allocated IDs under load).
    local marker="${lockfile}.flock"
    [ -f "$marker" ] || : > "$marker"
    exec 9>>"$marker"
    flock -w "$KANBAN_LOCK_TIMEOUT_SEC" 9 || kanban::die "kanban: could not acquire lock (flock timeout): $marker" 3
    KANBAN_LOCK_MODE=flock
    trap '{ exec 9>&-; } 2>/dev/null' EXIT
  else
    local spin="${lockfile}.lockdir" waited=0 max_waits
    max_waits=$(( (KANBAN_LOCK_TIMEOUT_SEC * 10) > 0 ? KANBAN_LOCK_TIMEOUT_SEC * 10 : 1 ))
    while ! mkdir "$spin" 2>/dev/null; do
      sleep 0.2
      waited=$((waited+1))
      [ "$waited" -lt "$max_waits" ] || kanban::die "kanban: could not acquire lock (mkdir spinlock timeout): $spin" 3
    done
    KANBAN_LOCK_MODE=mkdir
    KANBAN_LOCK_SPIN="$spin"
    trap 'rmdir "$KANBAN_LOCK_SPIN" 2>/dev/null || true' EXIT
  fi
}

kanban::_lock_release() {
  if [ "$KANBAN_LOCK_MODE" = flock ]; then
    { exec 9>&-; } 2>/dev/null
  elif [ "$KANBAN_LOCK_MODE" = mkdir ]; then
    rmdir "$KANBAN_LOCK_SPIN" 2>/dev/null || true
  fi
  trap - EXIT
  KANBAN_LOCK_MODE=""
  KANBAN_LOCK_SPIN=""
}

# --- global prefix registry (personal, NOT in git) --------------------------

kanban::registry_path() {
  printf '%s' "${KANBAN_PREFIX_REGISTRY:-$HOME/.config/kanban/prefixes.tsv}"
}

kanban::registry_lookup_repo() {
  local regfile="$1" prefix="$2"
  [ -f "$regfile" ] || return 0
  awk -F'\t' -v p="$prefix" '$1==p {print $2; exit}' "$regfile"
}

kanban::registry_reserve() {
  local regfile="$1" prefix="$2" repo="$3" dir
  dir="$(dirname "$regfile")"
  if ! mkdir -p "$dir" 2>/dev/null; then
    echo "kanban: warning: cannot create prefix registry dir $dir; continuing without global registration" >&2
    return 0
  fi
  if ! touch "$regfile" 2>/dev/null; then
    echo "kanban: warning: cannot write prefix registry $regfile; continuing without global registration" >&2
    return 0
  fi
  printf '%s\t%s\n' "$prefix" "$repo" >> "$regfile"
}

# kanban::_derive_prefix_candidate <repo-dir-basename> -> a 2-4 char uppercase
# candidate prefix. Multi-word (hyphen/underscore separated): first 2 letters
# of word 1 + first letter of each following word. Single word: its leading
# consonants (falls back to the whole word if that's under 2 chars).
kanban::_derive_prefix_candidate() {
  local base="$1" words=() w candidate="" first rest_i wi w0 out c i
  base="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  IFS='-_' read -r -a words <<<"$base"
  local filtered=()
  for w in "${words[@]}"; do [ -n "$w" ] && filtered+=("$w"); done
  words=("${filtered[@]}")

  if [ "${#words[@]}" -ge 2 ]; then
    first="${words[0]}"
    candidate="${first:0:2}"
    for ((rest_i = 1; rest_i < ${#words[@]}; rest_i++)); do
      wi="${words[$rest_i]}"
      candidate+="${wi:0:1}"
    done
    candidate="${candidate^^}"
    candidate="${candidate:0:4}"
  else
    w0="${words[0]:-repo}"
    out=""
    for ((i = 0; i < ${#w0}; i++)); do
      c="${w0:i:1}"
      case "$c" in
        a|e|i|o|u) ;;
        *) out+="$c" ;;
      esac
    done
    candidate="${out^^}"
    if [ "${#candidate}" -lt 2 ]; then
      candidate="${w0^^}"
    fi
    candidate="${candidate:0:3}"
  fi

  candidate="$(printf '%s' "$candidate" | tr -cd 'A-Z')"
  [ -n "$candidate" ] || candidate="PRJ"
  [ "${#candidate}" -ge 2 ] || candidate="${candidate}X"
  printf '%s' "$candidate"
}

# kanban::prefix_candidates_report <repo> -> one line per prefix present on
# the board: "<count>\t<highest-card-number>\t<prefix>", most-frequent first
# (ties broken by the highest card number, then prefix name for
# determinism). Empty output if the board has no parseable card at all.
kanban::prefix_candidates_report() {
  local repo="$1" board f base prefix p
  local -A counts=()
  board="$(kanban::board_dir "$repo")"
  shopt -s nullglob
  for f in "$board"/*/*.md; do
    base="$(basename "$f" .md)"
    prefix="$(kanban::card_prefix "$base")"
    [ -n "$prefix" ] || continue
    counts["$prefix"]=$(( ${counts["$prefix"]:-0} + 1 ))
  done
  shopt -u nullglob
  for p in "${!counts[@]}"; do
    printf '%s\t%s\t%s\n' "${counts[$p]}" "$(kanban::max_card_num "$repo" "$p")" "$p"
  done | sort -t $'\t' -k1,1nr -k2,2nr -k3,3
}

# kanban::dominant_board_prefix <repo> -> the top prefix from
# kanban::prefix_candidates_report, or "" if the board has no parseable card
# at all. Used so a legacy board (cards but no kanban.lock yet) keeps its
# existing ID space instead of a fresh dir-name-derived prefix silently
# splitting it. Read-only — callers decide whether that's enough to act on.
kanban::dominant_board_prefix() {
  local repo="$1" report
  report="$(kanban::prefix_candidates_report "$repo")"
  [ -n "$report" ] || { printf ''; return 0; }
  printf '%s\n' "$report" | head -n1 | cut -f3
}

# kanban::valid_prefix_shape <candidate> -> true if it looks like a real
# prefix (letters/digits, starting with a letter) — same shape the card-ID
# regex expects.
kanban::valid_prefix_shape() {
  [[ "$1" =~ ^[A-Za-z][A-Za-z0-9]*$ ]]
}

# kanban::_persist_prefix <repo> <prefix> <note> -> the SINGLE code path that
# writes prefix= to kanban.lock (flock-guarded) and a registry row (if free),
# and ALWAYS prints a one-line stderr notice naming the prefix and where it
# was written. Every route that persists a default prefix — set-prefix,
# explicit --prefix on first use, a confirmed interactive prompt, or
# KANBAN_ASSUME_YES=1 — funnels through here so the notice can never be
# silently skipped.
kanban::_persist_prefix() {
  local repo="$1" prefix="$2" note="$3" lockfile regfile owner
  lockfile="$(kanban::lock_file "$repo")"
  regfile="$(kanban::registry_path)"
  kanban::lock_ensure "$lockfile"
  kanban::_lock_acquire "$lockfile"
  owner="$(kanban::registry_lookup_repo "$regfile" "$prefix")"
  if [ -n "$owner" ] && [ "$owner" != "$repo" ]; then
    echo "kanban: warning: prefix '$prefix' is already registered to $owner; adopting it anyway for this board" >&2
  elif [ -z "$owner" ]; then
    kanban::registry_reserve "$regfile" "$prefix" "$repo"
  fi
  kanban::lock_upsert "$lockfile" "prefix" "$prefix"
  kanban::_lock_release
  echo "kanban: set default prefix to '$prefix' ($note) — written to $lockfile" >&2
}

# kanban::persist_prefix_if_unset <repo> <prefix> [note] -> persists $prefix
# as the project default ONLY if kanban.lock has no prefix= line yet. Used
# when a caller passes an explicit --prefix on a mutating call: that explicit
# choice IS the first-use confirmation, so it may set the default — but it
# must never silently override an already-recorded different default.
kanban::persist_prefix_if_unset() {
  local repo="$1" prefix="$2" note="${3:-explicit --prefix, first use}" lockfile existing
  lockfile="$(kanban::lock_file "$repo")"
  existing="$(kanban::lock_get_prefix "$lockfile")"
  [ -z "$existing" ] || return 0
  kanban::_persist_prefix "$repo" "$prefix" "$note"
}

# kanban::_print_prefix_candidates <repo> <report> <derived> -> the shared
# stderr listing used by both the interactive prompt and the non-interactive
# confirm-required failure: board prefixes with counts (most frequent
# first), or "no existing cards", plus the dir-name-derived candidate always
# shown and labeled as the empty-board fallback.
kanban::_print_prefix_candidates() {
  local report="$2" derived="$3" cnt mx p
  echo "kanban: this project has no default prefix yet — confirmation required (never auto-picked)." >&2
  if [ -n "$report" ]; then
    echo "kanban: prefixes on the board, most frequent first:" >&2
    while IFS=$'\t' read -r cnt mx p; do
      [ -n "$p" ] || continue
      printf '  %-8s %s card(s), highest %s-%s\n' "$p" "$cnt" "$p" "$mx" >&2
    done <<<"$report"
  else
    echo "kanban: the board has no existing cards." >&2
  fi
  printf '  %-8s (fallback candidate derived from the repo dir name, used only on an empty board)\n' "$derived" >&2
}

# kanban::resolve_and_reserve_prefix <repo> -> prints the repo's default
# prefix. NEVER silently persists a first-use choice:
#
# Resolution order: (1) caller passes an explicit prefix — handled by the
# caller, never reaches here (see kanban::persist_prefix_if_unset for that
# path's own persistence); (2) `prefix=` already in kanban.lock — returned
# immediately below, read-only. Otherwise, confirmation is REQUIRED — the
# board's dominant existing prefix (or, on an empty board, a dir-basename-
# derived candidate) is only ever a *suggestion*:
#   - `KANBAN_ASSUME_YES=1` accepts that suggestion non-interactively
#     (autonomous runs that must not block) and persists it.
#   - an interactive terminal (stdin AND stderr both TTYs) is prompted once;
#     the answer (accept / decline / a different prefix) is persisted.
#   - otherwise (the default: agents, CI, scheduled runs) this prints the
#     candidate list and how to confirm to stderr, then exits 2 — no file is
#     touched. Confirm via `kanban-id.sh set-prefix <PREFIX>` or pass
#     `--prefix <PREFIX>` explicitly to the mutating call.
kanban::resolve_and_reserve_prefix() {
  local repo="$1" lockfile existing report derived top answer chosen

  lockfile="$(kanban::lock_file "$repo")"
  existing="$(kanban::lock_get_prefix "$lockfile")"
  if [ -n "$existing" ]; then
    printf '%s\n' "$existing"
    return 0
  fi

  report="$(kanban::prefix_candidates_report "$repo")"
  derived="$(kanban::_derive_prefix_candidate "$(basename "$repo")")"
  if [ -n "$report" ]; then
    top="$(printf '%s\n' "$report" | head -n1 | cut -f3)"
  else
    top="$derived"
  fi

  if [ "${KANBAN_ASSUME_YES:-}" = "1" ]; then
    kanban::_persist_prefix "$repo" "$top" "auto-accepted top candidate via KANBAN_ASSUME_YES=1"
    printf '%s\n' "$top"
    return 0
  fi

  if [ -t 0 ] && [ -t 2 ]; then
    kanban::_print_prefix_candidates "$repo" "$report" "$derived"
    printf "kanban: use '%s' as this project's default prefix? [Y/n/<other>] " "$top" >&2
    answer=""
    read -r answer || answer=""
    case "$answer" in
      ""|[Yy]|[Yy][Ee][Ss])
        chosen="$top"
        ;;
      [Nn]|[Nn][Oo])
        kanban::die "kanban: prefix not confirmed; re-run and confirm, or use 'kanban-id.sh set-prefix <PREFIX>' / pass --prefix explicitly" 2
        ;;
      *)
        kanban::valid_prefix_shape "$answer" \
          || kanban::die "kanban: '$answer' is not a valid prefix (letters/digits, starting with a letter)" 2
        chosen="$answer"
        ;;
    esac
    kanban::_persist_prefix "$repo" "$chosen" "confirmed interactively"
    printf '%s\n' "$chosen"
    return 0
  fi

  kanban::_print_prefix_candidates "$repo" "$report" "$derived"
  {
    echo "kanban: confirm with:  kanban-id.sh --repo <repo> set-prefix <PREFIX>"
    echo "kanban: or pass --prefix <PREFIX> explicitly to this call."
    echo "kanban: for autonomous/non-interactive runs, set KANBAN_ASSUME_YES=1 to accept '$top' automatically."
  } >&2
  exit 2
}

# kanban::allocate_next_id <repo> <prefix> -> allocates+persists a new ID,
# reconciling the lock counter against the highest scanned card number.
kanban::allocate_next_id() {
  local repo="$1" prefix="$2" lockfile width cur maxcard base next padded
  lockfile="$(kanban::lock_file "$repo")"
  kanban::lock_ensure "$lockfile"
  kanban::_lock_acquire "$lockfile"
  cur="$(kanban::lock_get_counter "$lockfile" "$prefix")"
  maxcard="$(kanban::max_card_num "$repo" "$prefix")"
  base="$cur"
  [ "$maxcard" -gt "$base" ] && base="$maxcard"
  next=$((base + 1))
  width="$(kanban::prefix_width "$repo" "$prefix")"
  kanban::lock_upsert "$lockfile" "$prefix" "$next"
  kanban::_lock_release
  printf -v padded '%0*d' "$width" "$next"
  printf '%s-%s\n' "$prefix" "$padded"
}
