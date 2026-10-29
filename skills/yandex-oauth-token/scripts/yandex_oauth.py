#!/usr/bin/env python3
"""Yandex OAuth helper: authorization URL, code exchange, refresh and token check.

Secrets never travel on a command line. The authorization code is read from
stdin; the client secret and tokens are read from, and written to, the key file
named by ENV_FILE (parsed, never sourced). Requests go straight to fixed Yandex
HTTPS hosts from this process: no subprocess, no proxy from the environment, no
redirects. Output carries lengths and status only, never a secret value.

    yandex-oauth.sh authorize-url
    printf '%s' "$CODE" | yandex-oauth.sh exchange [--dry-run]
    yandex-oauth.sh refresh [--dry-run]
    yandex-oauth.sh check [COUNTER_ID] [--dry-run]

Config: ENV_FILE (default .env.local) and OAUTH_PREFIX (default OAUTH) select
<PREFIX>_CLIENT_ID, <PREFIX>_CLIENT_SECRET, <PREFIX>_TOKEN, <PREFIX>_REFRESH_TOKEN.
"""
from __future__ import annotations

import contextlib
import fcntl
import json
import os
import re
import ssl
import stat
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

AUTHORIZE_URL = "https://oauth.yandex.ru/authorize?response_type=code&client_id=%s"
TOKEN_URL = "https://oauth.yandex.ru/token"
LOGIN_INFO_URL = "https://login.yandex.ru/info"
METRIKA_COUNTER_URL = "https://api-metrika.yandex.net/management/v1/counter/%s"
ALLOWED_HOSTS = frozenset({"oauth.yandex.ru", "login.yandex.ru", "api-metrika.yandex.net"})
MAX_RESPONSE = 64 * 1024
LOCK_TIMEOUT = 30.0

PREFIX_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
CLIENT_ID_RE = re.compile(r"[A-Za-z0-9_-]+")
CODE_RE = re.compile(r"[A-Za-z0-9_.~-]{1,128}")
TOKEN_RE = re.compile(r"[A-Za-z0-9._~+/=:-]{8,2048}")
COUNTER_RE = re.compile(r"[0-9]{1,20}")
LINE_RE = re.compile(r"(?P<export>export\s+)?(?P<key>[A-Za-z_][A-Za-z0-9_]*)=(?P<value>.*)")


class OAuthError(Exception):
    """An expected failure whose message is safe to print."""


class Transport:
    """HTTPS to the allowed Yandex hosts only; no proxies, no redirects."""

    class _NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None

    def __init__(self, timeout: float = 20.0):
        self.timeout = timeout
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            self._NoRedirect,
            urllib.request.HTTPSHandler(context=ssl.create_default_context()),
        )

    def request(self, method: str, url: str, data: bytes | None = None, headers: dict | None = None):
        parts = urllib.parse.urlsplit(url)
        if parts.scheme != "https" or parts.hostname not in ALLOWED_HOSTS or parts.username or parts.port:
            raise OAuthError("refusing a request outside the allowed Yandex HTTPS hosts")
        req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
        try:
            with self.opener.open(req, timeout=self.timeout) as resp:
                status, body = resp.status, resp.read(MAX_RESPONSE + 1)
        except urllib.error.HTTPError as exc:
            status, body = exc.code, exc.read(MAX_RESPONSE + 1)
        except (urllib.error.URLError, OSError, ssl.SSLError):
            raise OAuthError("network request failed before a response was received") from None
        if len(body) > MAX_RESPONSE:
            raise OAuthError("response exceeded the size limit")
        return status, body


def _safe(text: object, limit: int = 120) -> str:
    return re.sub(r"[^A-Za-z0-9 .,:_-]", "?", str(text))[:limit]


class Config:
    def __init__(self, environ):
        self.prefix = environ.get("OAUTH_PREFIX", "OAUTH")
        if not PREFIX_RE.fullmatch(self.prefix):
            raise OAuthError("invalid OAUTH_PREFIX")
        self.env_file = Path(environ.get("ENV_FILE", ".env.local"))
        self.k_id, self.k_secret = self.prefix + "_CLIENT_ID", self.prefix + "_CLIENT_SECRET"
        self.k_token, self.k_refresh = self.prefix + "_TOKEN", self.prefix + "_REFRESH_TOKEN"

    def real_path(self, for_secrets: bool) -> Path:
        path = Path(os.path.realpath(self.env_file))
        try:
            info = os.stat(path)
        except OSError:
            raise OAuthError("configured file unavailable") from None
        if not stat.S_ISREG(info.st_mode):
            raise OAuthError("configured file is not a regular file")
        if for_secrets:
            if info.st_uid != os.getuid():
                raise OAuthError("key file must be owned by the current user")
            if info.st_mode & 0o022:
                raise OAuthError("key file must not be writable by group or others")
            if info.st_mode & 0o044:
                print("WARNING: key file is readable by group or others; tighten its mode", file=sys.stderr)
        return path


def read_values(path: Path, keys) -> dict:
    """Parse KEY=VALUE lines without sourcing; duplicate wanted keys are an error."""
    found: dict = {}
    try:
        text = path.read_bytes().decode("utf-8")
    except (OSError, UnicodeDecodeError):
        raise OAuthError("configured file unreadable") from None
    for raw in text.splitlines():
        m = LINE_RE.fullmatch(raw.rstrip("\r"))
        if not m or m["key"] not in keys:
            continue
        if m["key"] in found:
            raise OAuthError("duplicate %s in key file" % m["key"])
        value = m["value"].strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        found[m["key"]] = value
    return found


@contextlib.contextmanager
def file_lock(path: Path, timeout: float = LOCK_TIMEOUT):
    lock = path.with_name(path.name + ".lock")
    fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise OAuthError("another process holds the key-file lock") from None
                time.sleep(0.1)
        yield
    finally:
        os.close(fd)


def _fsync_dir(directory: Path) -> None:
    fd = os.open(directory, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def merge_updates(content: bytes, updates: dict) -> bytes:
    """Replace or append only the given keys; every other byte of the file stays."""
    lines = content.decode("utf-8").splitlines(keepends=True)
    pending = dict(updates)
    seen: set = set()
    for i, raw in enumerate(lines):
        eol = raw[len(raw.rstrip("\r\n")):]
        m = LINE_RE.fullmatch(raw.rstrip("\r\n"))
        if m and m["key"] in pending:
            if m["key"] in seen:
                raise OAuthError("duplicate %s in key file" % m["key"])
            seen.add(m["key"])
            lines[i] = "%s%s=%s%s" % (m["export"] or "", m["key"], pending.pop(m["key"]), eol or "\n")
    if pending and lines and not lines[-1].endswith(("\n", "\r")):
        lines[-1] += "\n"
    lines.extend("%s=%s\n" % item for item in pending.items())
    return "".join(lines).encode("utf-8")


def store(path: Path, updates: dict) -> None:
    """Atomically merge `updates` into the file; on failure keep them in a 0600 recovery file."""
    try:
        info = os.stat(path)
        merged = merge_updates(path.read_bytes(), updates)
        fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".")
        try:
            with os.fdopen(fd, "wb") as handle:
                os.fchmod(handle.fileno(), stat.S_IMODE(info.st_mode))
                handle.write(merged)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp, path)
        except BaseException:
            with contextlib.suppress(OSError):
                os.unlink(tmp)
            raise
        _fsync_dir(path.parent)
    except (OSError, OAuthError, UnicodeError):
        recovery = path.parent / (".%s.yandex-oauth-recovery-%d-%d" % (path.name, os.getpid(), time.time_ns()))
        try:
            fd = os.open(recovery, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as handle:
                handle.write("".join("%s=%s\n" % item for item in updates.items()))
        except OSError:
            raise OAuthError("tokens were issued but could not be stored or saved for recovery") from None
        raise OAuthError("tokens were issued but the key file was not updated; recovery file written: %s" % recovery) from None


def token_request(cfg: Config, transport, values: dict, grant: dict) -> dict:
    fields = {"client_id": values[cfg.k_id], "client_secret": values[cfg.k_secret], **grant}
    status, raw = transport.request(
        "POST", TOKEN_URL, data=urllib.parse.urlencode(fields).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"},
    )
    try:
        body = json.loads(raw.decode("utf-8"))
        if not isinstance(body, dict):
            raise ValueError
    except ValueError:
        body = {}
    if status != 200:
        detail = _safe("%s %s" % (body.get("error", ""), body.get("error_description", ""))).strip()
        raise OAuthError("HTTP=%s %s" % (status, detail))
    return body


def _valid_token(value: object) -> bool:
    return isinstance(value, str) and TOKEN_RE.fullmatch(value) is not None


def _require(values: dict, names, cfg: Config) -> None:
    for name in names:
        if not values.get(name):
            raise OAuthError("%s is empty or missing in the key file" % name)
    for name in (cfg.k_id,):
        if name in values and not CLIENT_ID_RE.fullmatch(values[name]):
            raise OAuthError("unsupported client ID")


def cmd_authorize_url(cfg: Config, out) -> int:
    values = read_values(cfg.real_path(False), {cfg.k_id})
    client_id = values.get(cfg.k_id, "")
    if cfg.k_id in values and not CLIENT_ID_RE.fullmatch(client_id):
        raise OAuthError("missing or unsupported client ID")
    if not client_id:
        raise OAuthError("missing or unsupported client ID")
    print(AUTHORIZE_URL % client_id, file=out)
    return 0


def _issue(cfg: Config, transport, out, grant_name: str, build_grant, needed, dry_run: bool) -> int:
    path = cfg.real_path(True)
    keys = {cfg.k_id, cfg.k_secret, cfg.k_token, cfg.k_refresh}
    with file_lock(path):
        values = read_values(path, keys)
        _require(values, needed, cfg)
        if dry_run:
            print("dry-run %s: would POST %s (grant_type=%s) and update %s, %s in %s; no network, no write"
                  % (grant_name, TOKEN_URL, grant_name_to_grant(grant_name), cfg.k_token, cfg.k_refresh, cfg.env_file), file=out)
            return 0
        body = token_request(cfg, transport, values, build_grant(values))
        access, refresh, expires = body.get("access_token"), body.get("refresh_token"), body.get("expires_in")
        if not _valid_token(access) or (refresh is not None and not _valid_token(refresh)):
            raise OAuthError("response held a missing or unsupported token shape; nothing stored")
        if grant_name == "exchange" and refresh is None:
            raise OAuthError("response held no refresh token; nothing stored")
        updates = {cfg.k_token: access}
        if refresh is not None:
            updates[cfg.k_refresh] = refresh
        store(path, updates)
    rotated = "yes" if refresh is not None else "no"
    print("OK %s: expires_in=%s %s_len=%d rotated_refresh=%s -> %s"
          % (grant_name, _safe(expires, 20), cfg.k_token, len(access), rotated, cfg.env_file), file=out)
    return 0


def grant_name_to_grant(name: str) -> str:
    return "authorization_code" if name == "exchange" else "refresh_token"


def cmd_check(cfg: Config, transport, out, counter: str, dry_run: bool) -> int:
    path = cfg.real_path(True)
    values = read_values(path, {cfg.k_token})
    _require(values, [cfg.k_token], cfg)
    url = METRIKA_COUNTER_URL % counter if counter else LOGIN_INFO_URL
    if dry_run:
        print("dry-run check: would GET %s with the stored token; no network" % url, file=out)
        return 0
    status, _ = transport.request("GET", url, headers={"Authorization": "OAuth " + values[cfg.k_token]})
    print("check: HTTP=%d (%s)  200=valid 401/403=token invalid/lost-access" % (status, url), file=out)
    return 0


USAGE = (
    "usage: yandex-oauth.sh authorize-url\n"
    "       printf '%s' \"$CODE\" | yandex-oauth.sh exchange [--dry-run]\n"
    "       yandex-oauth.sh refresh [--dry-run]\n"
    "       yandex-oauth.sh check [COUNTER_ID] [--dry-run]\n"
    "config via env: ENV_FILE (default .env.local), OAUTH_PREFIX (default OAUTH)\n"
)


def main(argv=None, environ=None, stdin=None, stdout=None, stderr=None, transport=None) -> int:
    argv = sys.argv[1:] if argv is None else list(argv)
    environ = os.environ if environ is None else environ
    stdin, stdout, stderr = stdin or sys.stdin, stdout or sys.stdout, stderr or sys.stderr
    cmd, args = (argv[0], argv[1:]) if argv else ("", [])
    dry_run = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]
    try:
        if cmd == "authorize-url" and not (args or dry_run):
            return cmd_authorize_url(Config(environ), stdout)
        if cmd not in ("exchange", "refresh", "check"):
            stderr.write(USAGE)
            return 2
        cfg = Config(environ)
        transport = transport or Transport()
        if cmd == "check":
            if len(args) > 1 or (args and not COUNTER_RE.fullmatch(args[0])):
                raise OAuthError("check takes an optional numeric counter ID")
            return cmd_check(cfg, transport, stdout, args[0] if args else "", dry_run)
        if args:
            raise OAuthError("%s takes no arguments; never pass a code or token on the command line" % cmd)
        if cmd == "refresh":
            return _issue(cfg, transport, stdout, "refresh",
                          lambda v: {"grant_type": "refresh_token", "refresh_token": v[cfg.k_refresh]},
                          [cfg.k_id, cfg.k_secret, cfg.k_refresh], dry_run)
        code = "" if dry_run else stdin.readline().strip()
        if not dry_run and not CODE_RE.fullmatch(code):
            raise OAuthError("provide the authorization code on stdin (one line, letters, digits, . _ ~ - only)")
        return _issue(cfg, transport, stdout, "exchange",
                      lambda v: {"grant_type": "authorization_code", "code": code},
                      [cfg.k_id, cfg.k_secret], dry_run)
    except OAuthError as exc:
        stderr.write("ERROR: %s\n" % exc)
        return 1
    except Exception as exc:  # never echo exception text: it could carry request data
        stderr.write("ERROR: unexpected %s\n" % type(exc).__name__)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
