#!/usr/bin/env bash
# Thin launcher: the implementation lives in yandex_oauth.py so secrets stay off
# every command line. See that file's header for usage.
set -eu
exec python3 -I "$(dirname -- "${BASH_SOURCE[0]}")/yandex_oauth.py" "$@"
