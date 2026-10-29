"""Synthetic tests for the Yandex OAuth helper: fake transport, no network, no real credentials."""
import importlib.util
import io
import json
import multiprocessing
import os
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1] / "skills/yandex-oauth-token/scripts"
SPEC = importlib.util.spec_from_file_location("yandex_oauth", SCRIPTS / "yandex_oauth.py")
Y = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(Y)

SECRET = "synthetic-client-secret-0001"
OLD_ACCESS, OLD_REFRESH = "old-access-token-0001", "old-refresh-token-0001"


class FakeTransport:
    def __init__(self, status=200, body=None, delay=0.0):
        self.status, self.body, self.delay, self.calls = status, body or {}, delay, []

    def request(self, method, url, data=None, headers=None):
        self.calls.append((method, url, data, headers))
        time.sleep(self.delay)
        return self.status, json.dumps(self.body).encode()


class ChainTransport:
    """Each refresh must present the latest refresh token, as a rotating provider would."""

    def __init__(self, state_dir):
        self.state = Path(state_dir) / "chain"

    def request(self, method, url, data=None, headers=None):
        time.sleep(0.4)
        presented = [p.split("=", 1)[1] for p in data.decode().split("&") if p.startswith("refresh_token=")][0]
        expected = self.state.read_text() if self.state.exists() else OLD_REFRESH
        if presented != expected:
            return 400, b'{"error": "invalid_grant"}'
        new = "rotated-refresh-%s" % (os.getpid())
        self.state.write_text(new)
        return 200, json.dumps({"access_token": "access-from-%d-xx" % os.getpid(), "refresh_token": new, "expires_in": 3600}).encode()


def _worker(env_file, state_dir, queue):
    out, err = io.StringIO(), io.StringIO()
    code = Y.main(["refresh"], {"ENV_FILE": env_file}, io.StringIO(), out, err, ChainTransport(state_dir))
    queue.put((code, err.getvalue()))


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.tmp)]))
        self.env_file = self.tmp / "settings"
        self.write_env()
        self.env = {"ENV_FILE": str(self.env_file)}

    def write_env(self, extra="", mode=0o600):
        self.env_file.write_text(
            "# project settings\nOTHER=keep me\nOAUTH_CLIENT_ID=client_42\n"
            f"OAUTH_CLIENT_SECRET={SECRET}\nOAUTH_TOKEN={OLD_ACCESS}\nOAUTH_REFRESH_TOKEN={OLD_REFRESH}\n{extra}")
        self.env_file.chmod(mode)

    def run_main(self, argv, transport=None, stdin="", env=None):
        out, err = io.StringIO(), io.StringIO()
        code = Y.main(argv, env or self.env, io.StringIO(stdin), out, err, transport)
        return code, out.getvalue(), err.getvalue()

    def assertNoSecrets(self, *texts):
        for text in texts:
            for needle in (SECRET, OLD_ACCESS, OLD_REFRESH, "new-access-token", "new-refresh-token", "auth-code-1234"):
                self.assertNotIn(needle, text)


class AuthorizeUrlTests(Base):
    def test_public_url_and_refusals(self):
        code, out, _ = self.run_main(["authorize-url"])
        self.assertEqual((code, out), (0, "https://oauth.yandex.ru/authorize?response_type=code&client_id=client_42\n"))
        self.write_env("OAUTH_CLIENT_ID=second\n")
        self.assertIn("duplicate", self.run_main(["authorize-url"])[2])
        self.env_file.write_text("OAUTH_CLIENT_ID=$(touch %s)\n" % (self.tmp / "injected"))
        self.assertEqual(self.run_main(["authorize-url"])[0], 1)
        self.assertFalse((self.tmp / "injected").exists())
        self.env_file.write_text("OAUTH_CLIENT_ID=abc\n")
        self.assertEqual(self.run_main(["authorize-url"], env={**self.env, "OAUTH_PREFIX": "bad-prefix"})[0], 1)
        self.assertEqual(self.run_main(["authorize-url", "extra"])[0], 2)
        self.assertEqual(self.run_main(["bogus"])[0], 2)
        self.assertEqual(self.run_main(["authorize-url"], env={"ENV_FILE": str(self.tmp / "absent")})[0], 1)


class ExchangeRefreshTests(Base):
    def test_exchange_stores_tokens_preserves_file_and_leaks_nothing(self):
        transport = FakeTransport(body={"access_token": "new-access-token-0002", "refresh_token": "new-refresh-token-0002", "expires_in": 31536000})
        self.env_file.chmod(0o640)
        with mock.patch("subprocess.Popen", side_effect=AssertionError("no subprocess allowed")):
            code, out, err = self.run_main(["exchange"], transport, stdin="auth-code-1234\n")
        self.assertEqual(code, 0, err)
        text = self.env_file.read_text()
        self.assertIn("OAUTH_TOKEN=new-access-token-0002\n", text)
        self.assertIn("OAUTH_REFRESH_TOKEN=new-refresh-token-0002\n", text)
        self.assertTrue(text.startswith("# project settings\nOTHER=keep me\nOAUTH_CLIENT_ID=client_42\n"))
        self.assertEqual(stat.S_IMODE(self.env_file.stat().st_mode), 0o640)
        self.assertNoSecrets(out, err)
        self.assertIn("rotated_refresh=yes", out)
        (method, url, body, _), = transport.calls
        self.assertEqual((method, url), ("POST", "https://oauth.yandex.ru/token"))
        self.assertIn(b"code=auth-code-1234", body)

    def test_exchange_refuses_argv_code_bad_stdin_and_missing_refresh(self):
        transport = FakeTransport(body={"access_token": "new-access-token-0002", "expires_in": 1})
        self.assertEqual(self.run_main(["exchange", "auth-code-1234"], transport)[0], 1)
        for stdin in ("", "bad code with spaces\n", "a;b\n"):
            self.assertEqual(self.run_main(["exchange"], transport, stdin=stdin)[0], 1)
        before = self.env_file.read_text()
        code, _, err = self.run_main(["exchange"], transport, stdin="auth-code-1234\n")
        self.assertEqual(code, 1)
        self.assertIn("no refresh token", err)
        self.assertEqual(self.env_file.read_text(), before)
        self.assertEqual(len(transport.calls), 1)

    def test_refresh_rotates_or_keeps_refresh_token(self):
        code, out, _ = self.run_main(["refresh"], FakeTransport(body={"access_token": "new-access-token-0003", "expires_in": 60}))
        self.assertEqual(code, 0)
        self.assertIn("rotated_refresh=no", out)
        text = self.env_file.read_text()
        self.assertIn("OAUTH_TOKEN=new-access-token-0003\n", text)
        self.assertIn("OAUTH_REFRESH_TOKEN=" + OLD_REFRESH + "\n", text)
        code, out, _ = self.run_main(["refresh"], FakeTransport(body={"access_token": "new-access-token-0004", "refresh_token": "new-refresh-token-0004"}))
        self.assertIn("OAUTH_REFRESH_TOKEN=new-refresh-token-0004\n", self.env_file.read_text())

    def test_provider_failure_and_bad_token_shape_change_nothing(self):
        before = self.env_file.read_text()
        code, out, err = self.run_main(["refresh"], FakeTransport(400, {"error": "invalid_grant", "error_description": "Code has expired"}))
        self.assertEqual(code, 1)
        self.assertIn("HTTP=400 invalid_grant Code has expired", err)
        for bad in ({"access_token": "short"}, {"access_token": "has space token 0000"}, {"access_token": "new-access-token-0005", "refresh_token": "x\ny"}, {}):
            with self.subTest(bad=bad):
                code, _, err = self.run_main(["refresh"], FakeTransport(body=bad))
                self.assertEqual(code, 1)
                self.assertIn("nothing stored", err)
        self.assertEqual(self.env_file.read_text(), before)
        self.assertNoSecrets(out, err)

    def test_dry_run_never_touches_network_or_file(self):
        class Boom:
            def request(self, *a, **k):
                raise AssertionError("network used")
        before = self.env_file.read_bytes()
        for argv, stdin in ((["exchange", "--dry-run"], ""), (["refresh", "--dry-run"], ""), (["check", "--dry-run"], "")):
            code, out, err = self.run_main(argv, Boom(), stdin)
            self.assertEqual(code, 0, err)
            self.assertIn("dry-run", out)
            self.assertNoSecrets(out, err)
        self.assertEqual(self.env_file.read_bytes(), before)

    def test_missing_keys_and_duplicate_secret_refused(self):
        self.env_file.write_text("OAUTH_CLIENT_ID=client_42\n")
        self.env_file.chmod(0o600)
        self.assertIn("OAUTH_CLIENT_SECRET", self.run_main(["refresh"], FakeTransport())[2])
        self.write_env("OAUTH_REFRESH_TOKEN=another-refresh-0000\n")
        self.assertIn("duplicate", self.run_main(["refresh"], FakeTransport())[2])

    def test_file_permission_and_symlink_handling(self):
        transport = FakeTransport(body={"access_token": "new-access-token-0006", "expires_in": 1})
        self.env_file.chmod(0o666)
        self.assertIn("writable", self.run_main(["refresh"], transport)[2])
        self.assertEqual(transport.calls, [])
        self.env_file.chmod(0o600)
        link = self.tmp / "link"
        link.symlink_to(self.env_file)
        code, _, err = self.run_main(["refresh"], transport, env={"ENV_FILE": str(link)})
        self.assertEqual(code, 0, err)
        self.assertTrue(link.is_symlink())
        self.assertIn("new-access-token-0006", self.env_file.read_text())

    def test_storage_failure_keeps_tokens_in_private_recovery_file(self):
        transport = FakeTransport(body={"access_token": "new-access-token-0007", "refresh_token": "new-refresh-token-0007"})
        before = self.env_file.read_text()
        with mock.patch("os.replace", side_effect=OSError("disk full")):
            code, _, err = self.run_main(["refresh"], transport)
        self.assertEqual(code, 1)
        self.assertEqual(self.env_file.read_text(), before)
        recoveries = list(self.tmp.glob(".settings.yandex-oauth-recovery-*"))
        self.assertEqual(len(recoveries), 1)
        self.assertEqual(stat.S_IMODE(recoveries[0].stat().st_mode), 0o600)
        self.assertIn("new-refresh-token-0007", recoveries[0].read_text())
        self.assertIn(str(recoveries[0]), err)
        self.assertNotIn("new-refresh-token-0007", err)
        self.assertEqual([p.name for p in self.tmp.glob("settings.*") if p.name != "settings.lock"], [])

    def test_concurrent_refreshes_serialize_on_the_rotating_token(self):
        ctx = multiprocessing.get_context("fork")
        queue = ctx.Queue()
        procs = [ctx.Process(target=_worker, args=(str(self.env_file), str(self.tmp), queue)) for _ in range(3)]
        for p in procs:
            p.start()
        for p in procs:
            p.join(30)
        results = [queue.get(timeout=5) for _ in procs]
        self.assertEqual([code for code, _ in results], [0, 0, 0], results)
        final = self.env_file.read_text()
        self.assertIn("OAUTH_REFRESH_TOKEN=" + (self.tmp / "chain").read_text() + "\n", final)


class CheckAndTransportTests(Base):
    def test_check_uses_token_header_and_prints_status_only(self):
        transport = FakeTransport(200, {})
        code, out, _ = self.run_main(["check", "12345"], transport)
        self.assertEqual(code, 0)
        self.assertIn("HTTP=200 (https://api-metrika.yandex.net/management/v1/counter/12345)", out)
        self.assertEqual(transport.calls[0][3], {"Authorization": "OAuth " + OLD_ACCESS})
        self.assertNoSecrets(out)
        code, out, _ = self.run_main(["check"], FakeTransport(401, {}))
        self.assertIn("HTTP=401 (https://login.yandex.ru/info)", out)

    def test_check_refuses_non_numeric_counter(self):
        transport = FakeTransport()
        for bad in ("1/../x", "abc", "1 2", "12345678901234567890123"):
            self.assertEqual(self.run_main(["check", bad], transport)[0], 1)
        self.assertEqual(transport.calls, [])

    def test_transport_allows_only_fixed_yandex_https_hosts(self):
        transport = Y.Transport()
        for url in ("https://evil.example/token", "http://oauth.yandex.ru/token", "https://oauth.yandex.ru.evil.example/",
                    "https://user@oauth.yandex.ru/token", "https://oauth.yandex.ru:8443/token"):
            with self.subTest(url=url), self.assertRaises(Y.OAuthError):
                transport.request("GET", url)

    def test_launcher_runs_python_isolated_and_fails_closed(self):
        env = {"PATH": os.environ["PATH"], "ENV_FILE": str(self.tmp / "absent")}
        result = subprocess.run([str(SCRIPTS / "yandex-oauth.sh"), "refresh"], env=env, capture_output=True, text=True, cwd=self.tmp)
        self.assertEqual(result.returncode, 1)
        self.assertIn("ERROR", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
