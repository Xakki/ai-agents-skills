#!/usr/bin/env bash
# Classify local+remote branches as merged / not merged into the default branch,
# report the unmerged ones, and (with --apply and a reviewed plan hash) delete
# the merged ones. Dry-run by default. Never touches the default branch, `dev`,
# `main`, `master`, protected prefixes, or anything checked out in a worktree.
#
# Deletion is a two-step, plan-bound operation:
#   1. a dry-run prints the candidates and `plan_sha256`;
#   2. --apply --plan-sha256 <that hash> recomputes the plan from the current
#      refs and refuses to delete anything if it differs.
# Only local branches are deleted unless --scope remote|both is given.
set -euo pipefail

REMOTE="${REMOTE:-origin}"
APPLY=0
SCOPE="local"         # local | remote | both
PROTECT_EXTRA=()      # extra exact branch names to never delete
EXCLUDE_RE_DEFAULT='^backup/'
EXCLUDE_RE="${EXCLUDE_RE:-$EXCLUDE_RE_DEFAULT}"
NO_FETCH=0
RESTORE_FILE=""
PLAN_SHA_ARG=""

usage() {
  cat <<'EOF'
usage: git-branch-clean.sh [options]

  --apply                delete the reviewed plan (default: dry-run, prints the plan)
  --plan-sha256 HASH     plan_sha256 printed by the dry-run; required with --apply
  --scope local|remote|both      what to delete (default: local)
  --remote NAME          git remote (default: origin)
  --protect NAME         extra branch to never delete (repeatable)
  --exclude-re REGEX     skip branches matching this (default: ^backup/ )
  --no-fetch             skip `git fetch --prune`
  --restore-file PATH    where to record <scope> <branch> <sha> before deleting
                         (default: <git-dir>/branch-cleanup/deleted-<UTC>.tsv)

Merged verdict (first match wins):
  1. ancestor of <remote>/<default>                      -> merged
  2. `git cherry` shows no unique patches                -> merged (rebase/cherry-pick)
  3. GitHub PR with base == <default> and mergedAt != nul -> merged (squash)
  otherwise                                              -> NOT merged, reported

A PR merged into `dev` (or any non-default base) does NOT count as merged.
Remote branches are deleted only with --scope remote|both, and only if they
still point at the reviewed commit (git push --force-with-lease).
EOF
}

die() { echo "ERROR: $*" >&2; exit 3; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --plan-sha256) [[ $# -ge 2 ]] || { echo "--plan-sha256 needs a value" >&2; exit 2; }; PLAN_SHA_ARG="$2"; shift 2 ;;
    --scope) [[ $# -ge 2 ]] || { echo "--scope needs a value" >&2; exit 2; }; SCOPE="$2"; shift 2 ;;
    --remote) REMOTE="$2"; shift 2 ;;
    --protect) PROTECT_EXTRA+=("$2"); shift 2 ;;
    --exclude-re) EXCLUDE_RE="$2"; shift 2 ;;
    --no-fetch) NO_FETCH=1; shift ;;
    --restore-file) RESTORE_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$SCOPE" in local|remote|both) ;; *) echo "--scope must be local, remote or both" >&2; exit 2 ;; esac
if [[ -n "$PLAN_SHA_ARG" && ! "$PLAN_SHA_ARG" =~ ^[0-9a-f]{64}$ ]]; then
  echo "--plan-sha256 must be 64 lowercase hex characters" >&2; exit 2
fi

git rev-parse --git-dir >/dev/null   # fail fast outside a repo
GITDIR="$(git rev-parse --absolute-git-dir)"

[[ $NO_FETCH -eq 1 ]] || git fetch --prune "$REMOTE"

# --- default branch -----------------------------------------------------------
DEFAULT="$(git symbolic-ref -q "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s@^refs/remotes/$REMOTE/@@")"
if [[ -z "$DEFAULT" ]]; then
  DEFAULT="$(git remote show "$REMOTE" | sed -n 's/.*HEAD branch: //p')"
fi
[[ -n "$DEFAULT" ]] || { echo "cannot determine default branch of $REMOTE" >&2; exit 1; }
BASE="$REMOTE/$DEFAULT"
git rev-parse -q --verify "$BASE" >/dev/null || { echo "$BASE not found" >&2; exit 1; }

# --- protected set ------------------------------------------------------------
declare -A PROTECTED=()
PROTECTED["$DEFAULT"]=1
PROTECTED["dev"]=1
PROTECTED["main"]=1
PROTECTED["master"]=1
for b in "${PROTECT_EXTRA[@]+"${PROTECT_EXTRA[@]}"}"; do PROTECTED["$b"]=1; done

# branches checked out in any worktree (git branch -D refuses those)
while IFS= read -r wb; do [[ -n "$wb" ]] && PROTECTED["$wb"]=1; done < <(
  git worktree list --porcelain | sed -n 's@^branch refs/heads/@@p'
)
# current HEAD, even in detached-adjacent cases
CUR="$(git symbolic-ref -q --short HEAD || true)"
[[ -n "$CUR" ]] && PROTECTED["$CUR"]=1

# --- GitHub PR index: branch -> merged-into-default? / open PR info ------------
declare -A PR_MERGED_DEFAULT=() PR_MERGED_SHA=() PR_INFO=()
if command -v gh >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then
  while IFS=$'\t' read -r head num state base merged created author oid; do
    [[ -z "$head" ]] && continue
    if [[ "$base" == "$DEFAULT" && "$merged" != "null" && -n "$merged" ]]; then
      PR_MERGED_DEFAULT["$head"]="#$num"
      # same tip under a different branch name (renamed / re-created locally)
      [[ -n "$oid" && "$oid" != "null" ]] && PR_MERGED_SHA["$oid"]="#$num"
    fi
    line="#$num $state->$base ${created%%T*} @$author"
    PR_INFO["$head"]="${PR_INFO[$head]+${PR_INFO[$head]}; }$line"
  done < <(gh pr list --state all --limit 1000 \
      --json number,headRefName,state,baseRefName,mergedAt,createdAt,author,headRefOid \
      --jq '.[]|[.headRefName,(.number|tostring),.state,.baseRefName,(.mergedAt//"null"),.createdAt,(.author.login//"?"),(.headRefOid//"null")]|@tsv')
else
  echo "note: gh unavailable — squash-merged PRs will not be detected" >&2
fi

# --- verdict ------------------------------------------------------------------
# echoes: MERGED:<reason> | UNMERGED
verdict() {
  local ref="$1" name="$2"
  if git merge-base --is-ancestor "$ref" "$BASE" 2>/dev/null; then
    echo "MERGED:ancestor"; return
  fi
  if [[ -z "$(git cherry "$BASE" "$ref" 2>/dev/null | grep '^+' || true)" ]]; then
    echo "MERGED:patches-upstream"; return
  fi
  if [[ -n "${PR_MERGED_DEFAULT[$name]+x}" ]]; then
    echo "MERGED:pr-${PR_MERGED_DEFAULT[$name]}"; return
  fi
  local sha; sha="$(git rev-parse "$ref")"
  if [[ -n "${PR_MERGED_SHA[$sha]+x}" ]]; then
    echo "MERGED:pr-${PR_MERGED_SHA[$sha]}-same-tip"; return
  fi
  echo "UNMERGED"
}

# how long the branch has been open: first commit not in the default branch
opened_since() {
  local ref="$1"
  git log --reverse --format=%cs "$BASE..$ref" 2>/dev/null | head -1
}

# --- collect ------------------------------------------------------------------
declare -a DEL_LOCAL=() DEL_REMOTE=() KEEP=() SKIPPED=()
declare -A SEEN=() SEEN_SKIP=()

collect() {  # $1 = local|remote, $2 = branch name, $3 = ref
  local kind="$1" name="$2" ref="$3"
  if [[ -n "${PROTECTED[$name]+x}" || "$name" =~ $EXCLUDE_RE ]]; then
    # still report it, so nothing silently vanishes from the picture
    [[ "$name" == "$DEFAULT" || "$name" == "$CUR" ]] && return
    [[ -n "${SEEN_SKIP[$name]+x}" ]] && return
    SEEN_SKIP[$name]=1
    local why="protected"
    [[ "$name" =~ $EXCLUDE_RE ]] && why="excluded-by-regex"
    git worktree list --porcelain | grep -qx "branch refs/heads/$name" && why="worktree"
    SKIPPED+=("$name"$'\t'"$why"$'\t'"$(verdict "$ref" "$name")")
    return
  fi
  local v; v="$(verdict "$ref" "$name")"
  if [[ "$v" == MERGED:* ]]; then
    if [[ "$kind" == local ]]; then DEL_LOCAL+=("$name"$'\t'"$(git rev-parse "$ref")"$'\t'"${v#MERGED:}")
    else DEL_REMOTE+=("$name"$'\t'"$(git rev-parse "$ref")"$'\t'"${v#MERGED:}"); fi
  else
    local key="$name"
    [[ -n "${SEEN[$key]+x}" ]] && return
    SEEN[$key]=1
    KEEP+=("$name"$'\t'"$(opened_since "$ref")"$'\t'"$(git log -1 --format=%cs "$ref")"$'\t'"$(git log -1 --format=%an "$ref")"$'\t'"${PR_INFO[$name]-—}")
  fi
}

while IFS= read -r name; do
  collect local "$name" "refs/heads/$name"
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

while IFS= read -r name; do
  [[ -z "$name" || "$name" == "HEAD" ]] && continue
  collect remote "$name" "refs/remotes/$REMOTE/$name"
done < <(git for-each-ref --format='%(refname)' "refs/remotes/$REMOTE/" \
           | sed -n "s@^refs/remotes/$REMOTE/@@p")

# --- plan ---------------------------------------------------------------------
# The reviewed plan: base tip, remote, scope and every <scope>\t<branch>\t<sha>\t<reason>
# row that would be deleted. Any ref movement or classification change alters the hash.
plan_text() {
  printf 'base\t%s\n' "$(git rev-parse "$BASE")"
  printf 'remote\t%s\n' "$REMOTE"
  printf 'scope\t%s\n' "$SCOPE"
  if [[ "$SCOPE" == both || "$SCOPE" == local ]]; then
    printf '%s\n' "${DEL_LOCAL[@]+"${DEL_LOCAL[@]}"}" | sed '/^$/d' | sort | sed 's/^/local\t/'
  fi
  if [[ "$SCOPE" == both || "$SCOPE" == remote ]]; then
    printf '%s\n' "${DEL_REMOTE[@]+"${DEL_REMOTE[@]}"}" | sed '/^$/d' | sort | sed 's/^/remote\t/'
  fi
}
PLAN_SHA="$(plan_text | sha256sum | cut -d' ' -f1)"

# --- report -------------------------------------------------------------------
echo "default branch: $BASE   |   mode: $([[ $APPLY -eq 1 ]] && echo APPLY || echo DRY-RUN)   |   scope: $SCOPE"
echo
echo "== MERGED, local (${#DEL_LOCAL[@]}) =="
printf '%s\n' "${DEL_LOCAL[@]+"${DEL_LOCAL[@]}"}" | sed '/^$/d' | sort
echo
echo "== MERGED, remote $REMOTE/ (${#DEL_REMOTE[@]}) =="
printf '%s\n' "${DEL_REMOTE[@]+"${DEL_REMOTE[@]}"}" | sed '/^$/d' | sort
echo
echo "== NOT merged (${#KEEP[@]}) ==  name / opened / last-commit / author / PRs"
printf '%s\n' "${KEEP[@]+"${KEEP[@]}"}" | sed '/^$/d' | sort
echo
echo "== SKIPPED (${#SKIPPED[@]}) ==  name / why / verdict"
printf '%s\n' "${SKIPPED[@]+"${SKIPPED[@]}"}" | sed '/^$/d' | sort
echo
echo "plan_sha256: $PLAN_SHA   (covers scope=$SCOPE only)"

# --- act ----------------------------------------------------------------------
if [[ $APPLY -ne 1 ]]; then
  echo "(dry-run — review the lists, then rerun with --apply --plan-sha256 $PLAN_SHA)"
  exit 0
fi

[[ -n "$PLAN_SHA_ARG" ]] || die "--apply requires --plan-sha256 from a reviewed dry-run; nothing was deleted"
[[ "$PLAN_SHA_ARG" == "$PLAN_SHA" ]] || die "the branches differ from the reviewed plan (or the hash is wrong); nothing was deleted — rerun the dry-run and review it"

ROWS=()
if [[ "$SCOPE" == both || "$SCOPE" == local ]]; then
  for row in "${DEL_LOCAL[@]+"${DEL_LOCAL[@]}"}"; do ROWS+=("local"$'\t'"$row"); done
fi
if [[ "$SCOPE" == both || "$SCOPE" == remote ]]; then
  for row in "${DEL_REMOTE[@]+"${DEL_REMOTE[@]}"}"; do ROWS+=("remote"$'\t'"$row"); done
fi
if [[ ${#ROWS[@]} -eq 0 ]]; then echo "nothing to delete for scope=$SCOPE"; exit 0; fi

if [[ -z "$RESTORE_FILE" ]]; then
  mkdir -p -- "$GITDIR/branch-cleanup"; chmod 700 "$GITDIR/branch-cleanup"
  RESTORE_FILE="$GITDIR/branch-cleanup/deleted-$(date -u +%Y%m%dT%H%M%SZ).tsv"
fi
{                                  # record only what this run will actually delete
  echo "# deleted $(date -Is) base=$BASE scope=$SCOPE remote=$REMOTE plan_sha256=$PLAN_SHA"
  echo "# restore local : git branch <branch> <sha>"
  echo "# restore remote: git push $REMOTE <sha>:refs/heads/<branch>"
  printf '%s\n' "${ROWS[@]}"
} >> "$RESTORE_FILE"
sync -- "$RESTORE_FILE" 2>/dev/null || sync
for row in "${ROWS[@]}"; do
  grep -qxF -- "$row" "$RESTORE_FILE" || die "restore file read-back failed; nothing was deleted"
done
echo; echo "restore file: $RESTORE_FILE"

if [[ "$SCOPE" == both || "$SCOPE" == local ]]; then
  for row in "${DEL_LOCAL[@]+"${DEL_LOCAL[@]}"}"; do
    IFS=$'\t' read -r name sha _ <<<"$row"
    [[ "$(git rev-parse -q --verify "refs/heads/$name" || true)" == "$sha" ]] \
      || die "$name moved after the plan was verified; stopped before deleting it"
    git branch -D -- "$name"
  done
fi
if [[ "$SCOPE" == both || "$SCOPE" == remote ]]; then
  leases=(); refspecs=()
  for row in "${DEL_REMOTE[@]+"${DEL_REMOTE[@]}"}"; do
    IFS=$'\t' read -r name sha _ <<<"$row"
    leases+=("--force-with-lease=refs/heads/$name:$sha"); refspecs+=(":refs/heads/$name")
  done
  [[ ${#refspecs[@]} -gt 0 ]] && git push "${leases[@]}" "$REMOTE" "${refspecs[@]}"
fi
exit 0
