#!/usr/bin/env bash
# yandex-oauth.sh — helper for the Yandex OAuth (Yandex ID) token lifecycle.
#
# Subcommands:
#   authorize-url            print the browser URL to obtain an auth `code`
#   exchange <CODE>          exchange an auth code -> access_token + refresh_token
#   refresh                  use stored refresh_token -> new access_token
#   check [COUNTER_ID]       probe token validity (Metrika counter, else login info)
#
# Config via env vars (defaults in brackets):
#   ENV_FILE     [.env.local]  file holding the keys below (KEY=VALUE lines)
#   OAUTH_PREFIX [OAUTH]       key prefix; keys used are:
#                                <PREFIX>_CLIENT_ID, <PREFIX>_CLIENT_SECRET,
#                                <PREFIX>_TOKEN, <PREFIX>_REFRESH_TOKEN
#
# Secrets are read from ENV_FILE and NEVER printed — only lengths / expires_in.
# Yandex may rotate the refresh_token on refresh; this script persists the new one.
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env.local}"
PREFIX="${OAUTH_PREFIX:-OAUTH}"
AUTH_HOST="https://oauth.yandex.ru"

K_CID="${PREFIX}_CLIENT_ID"
K_SEC="${PREFIX}_CLIENT_SECRET"
K_TOK="${PREFIX}_TOKEN"
K_REF="${PREFIX}_REFRESH_TOKEN"

die(){ echo "ERROR: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required"
command -v curl >/dev/null 2>&1 || die "curl is required"

readkey(){ # readkey KEY -> prints value of ^KEY= from ENV_FILE (empty if absent)
  [ -f "$ENV_FILE" ] || { printf ''; return 0; }
  local v
  v="$(grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '\r' || true)"
  printf '%s' "$v"
  return 0
}

writekeys(){ # writekeys KEY1 VAL1 [KEY2 VAL2] : atomic replace-or-append in ENV_FILE
  local tmp
  tmp="$(mktemp "${ENV_FILE}.XXXXXX")"
  # Values passed via environment (not inline) so + / = in tokens are safe.
  K1="$1" V1="$2" K2="${3:-}" V2="${4:-}" awk '
    BEGIN{ k1=ENVIRON["K1"]; v1=ENVIRON["V1"]; k2=ENVIRON["K2"]; v2=ENVIRON["V2"]; s1=0; s2=0 }
    { if (k1!="" && $0 ~ "^" k1 "=") { print k1 "=" v1; s1=1; next }
      if (k2!="" && $0 ~ "^" k2 "=") { print k2 "=" v2; s2=1; next }
      print }
    END{ if (k1!="" && !s1) print k1 "=" v1; if (k2!="" && !s2) print k2 "=" v2 }
  ' "$ENV_FILE" > "$tmp"
  [ -f "$ENV_FILE" ] && chmod --reference="$ENV_FILE" "$tmp" 2>/dev/null || true
  mv "$tmp" "$ENV_FILE"
}

api_token(){ # api_token <curl --data-urlencode pairs...> ; sets RESP_HTTP,A,R,E,ERR
  local cid csec resp
  cid="$(readkey "$K_CID")"; csec="$(readkey "$K_SEC")"
  [ -n "$cid" ]  || die "$K_CID empty in $ENV_FILE"
  [ -n "$csec" ] || die "$K_SEC empty in $ENV_FILE"
  resp="$(curl -sS -w '\n%{http_code}' -X POST "$AUTH_HOST/token" \
    --data-urlencode "client_id=$cid" --data-urlencode "client_secret=$csec" "$@" || true)"
  RESP_HTTP="$(printf '%s' "$resp" | tail -n1)"
  local body; body="$(printf '%s' "$resp" | sed '$d')"
  A="$(printf '%s' "$body" | jq -r '.access_token // empty' 2>/dev/null || true)"
  R="$(printf '%s' "$body" | jq -r '.refresh_token // empty' 2>/dev/null || true)"
  E="$(printf '%s' "$body" | jq -r '.expires_in // empty' 2>/dev/null || true)"
  ERR="$(printf '%s' "$body" | jq -r '[(.error // ""),(.error_description // "")]|join(" ")' 2>/dev/null || true)"
}

cmd="${1:-}"; [ $# -gt 0 ] && shift || true
case "$cmd" in
  authorize-url)
    cid="$(readkey "$K_CID")"; [ -n "$cid" ] || die "$K_CID empty in $ENV_FILE"
    echo "$AUTH_HOST/authorize?response_type=code&client_id=$cid"
    ;;
  exchange)
    code="${1:-}"; [ -n "$code" ] || die "usage: $0 exchange <CODE>"
    api_token --data-urlencode 'grant_type=authorization_code' --data-urlencode "code=$code"
    if [ "$RESP_HTTP" = 200 ] && [ -n "$A" ] && [ -n "$R" ]; then
      writekeys "$K_TOK" "$A" "$K_REF" "$R"
      echo "OK exchange: expires_in=$E ${K_TOK}_len=${#A} ${K_REF}_len=${#R} -> $ENV_FILE"
    else
      die "exchange failed HTTP=$RESP_HTTP $ERR"
    fi
    ;;
  refresh)
    ref="$(readkey "$K_REF")"; [ -n "$ref" ] || die "$K_REF empty in $ENV_FILE"
    api_token --data-urlencode 'grant_type=refresh_token' --data-urlencode "refresh_token=$ref"
    if [ "$RESP_HTTP" = 200 ] && [ -n "$A" ]; then
      if [ -n "$R" ]; then writekeys "$K_TOK" "$A" "$K_REF" "$R"; else writekeys "$K_TOK" "$A"; fi
      echo "OK refresh: expires_in=$E ${K_TOK}_len=${#A} rotated_refresh=$([ -n "$R" ] && echo yes || echo no) -> $ENV_FILE"
    else
      die "refresh failed HTTP=$RESP_HTTP $ERR"
    fi
    ;;
  check)
    counter="${1:-}"; tok="$(readkey "$K_TOK")"; [ -n "$tok" ] || die "$K_TOK empty in $ENV_FILE"
    if [ -n "$counter" ]; then
      url="https://api-metrika.yandex.net/management/v1/counter/$counter"
    else
      url="https://login.yandex.ru/info"
    fi
    code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: OAuth $tok" "$url" || true)"
    echo "check: HTTP=$code ($url)  200=valid 401/403=token invalid/lost-access"
    ;;
  *)
    cat >&2 <<EOF
usage: $(basename "$0") <authorize-url | exchange <CODE> | refresh | check [COUNTER_ID]>
  config via env: ENV_FILE (default .env.local), OAUTH_PREFIX (default OAUTH)
  keys used:      ${K_CID}, ${K_SEC}, ${K_TOK}, ${K_REF}
  example (this project's metrics token):
    OAUTH_PREFIX=OAUTH_METRIC ENV_FILE=.env.local $(basename "$0") authorize-url
    OAUTH_PREFIX=OAUTH_METRIC ENV_FILE=.env.local $(basename "$0") exchange <CODE>
EOF
    exit 2
    ;;
esac
