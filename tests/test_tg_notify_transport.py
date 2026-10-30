"""Synthetic curl-boundary tests; no real Telegram requests or credentials."""

import json
import os
import http.server
from pathlib import Path
import shutil
import ssl
import subprocess
import tempfile
import threading
import urllib.parse
import unittest


ROOT = Path(__file__).resolve().parents[1]
SENDER = ROOT / "skills" / "agent-telegram-notify" / "agent-telegram-notify.sh"
TOKEN = "123456:synthetic_token_value"
CHAT = "-100424242"
BODY = "synthetic private body"

MOCK = r'''#!/usr/bin/python3
import json, os, pathlib, sys
args=sys.argv[1:]
config=args[args.index('--config')+1]
data=pathlib.Path(config).read_text()
body=sys.stdin.read()
pathlib.Path(os.environ['TEST_CAPTURE']).write_text(json.dumps({'argv':args,'config':data,'body':body,
 'telegram_env_present':any(k in os.environ for k in ('TELEGRAM_BOT_TOKEN','TELEGRAM_CHAT_ID','TELEGRAM_THREAD_ID','TELEGRAM_HOME_CHANNEL'))}))
mode=os.environ.get('TEST_MODE','ok')
if mode=='redirect':
 print('{"ok":true}\n302')
elif mode=='fail':
 print('synthetic private body 123456:synthetic_token_value',file=sys.stderr)
 print('{"ok":false,"description":"synthetic private body 123456:synthetic_token_value"}\n403')
else:
 print('{"ok": true, "result": {}}\n200')
'''


class NotifyTransport(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tg-transport-test-")
        self.root = Path(self.temp.name)
        bindir = self.root / "bin"
        bindir.mkdir()
        fake = bindir / "curl"
        fake.write_text(MOCK, encoding="utf-8")
        fake.chmod(0o700)
        self.capture = self.root / "curl.json"
        self.env = {
            "PATH": str(bindir) + ":/usr/bin:/bin",
            "HOME": str(self.root),
            "LANG": "C.UTF-8",
            "TG_NOTIFY_HOME": str(self.root / "state"),
            "TELEGRAM_BOT_TOKEN": TOKEN,
            "TELEGRAM_CHAT_ID": CHAT,
            "TELEGRAM_THREAD_ID": "42",
            "TG_NOTIFY_MAX_ATTEMPTS": "1",
            "TEST_CAPTURE": str(self.capture),
        }

    def tearDown(self):
        self.temp.cleanup()

    def run_sender(self, extra=None):
        return subprocess.run(["bash", str(SENDER), "-q"], input=BODY, text=True, capture_output=True,
                              env={**self.env, **(extra or {})}, cwd=self.root, timeout=8)

    def test_success_sends_fields_through_pipes_not_argv(self):
        result = self.run_sender()
        self.assertEqual(result.returncode, 0, result.stderr)
        captured = json.loads(self.capture.read_text(encoding="utf-8"))
        self.assertFalse(captured["telegram_env_present"])
        argv = " ".join(captured["argv"])
        for value in (TOKEN, CHAT, BODY):
            self.assertNotIn(value, argv)
        self.assertIn("--disable", captured["argv"])
        self.assertEqual(captured["argv"][captured["argv"].index("--proto") + 1], "=https")
        self.assertNotIn("--location", captured["argv"])
        self.assertNotIn("-L", captured["argv"])
        self.assertIn("text@-", captured["argv"])
        self.assertIn(TOKEN, captured["config"])
        self.assertIn(CHAT, captured["config"])
        self.assertIn("message_thread_id=42", captured["config"])
        self.assertIn(BODY, captured["body"])

    def test_redirect_never_counts_as_success(self):
        result = self.run_sender({"TEST_MODE": "redirect"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("http=302", result.stderr)

    def test_server_errors_and_curl_stderr_are_not_echoed(self):
        result = self.run_sender({"TEST_MODE": "fail"})
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(TOKEN, result.stdout + result.stderr)
        self.assertNotIn(BODY, result.stdout + result.stderr)
        log = self.root / "state" / "tg-notify.log"
        self.assertNotIn(TOKEN, log.read_text(encoding="utf-8"))
        self.assertNotIn(BODY, log.read_text(encoding="utf-8"))

    def test_invalid_config_is_rejected_before_curl(self):
        for key, value in (("TELEGRAM_BOT_TOKEN", '123:bad"\\nurl="http://bad'),
                           ("TELEGRAM_CHAT_ID", "@bad\nnext"),
                           ("TELEGRAM_THREAD_ID", '42"')):
            with self.subTest(key=key):
                self.capture.unlink(missing_ok=True)
                result = self.run_sender({key: value})
                self.assertEqual(result.returncode, 2)
                self.assertFalse(self.capture.exists())
                self.assertNotIn(value, result.stderr)

    def test_explicit_environment_overrides_config_file(self):
        config = self.root / "synthetic.env"
        config.write_text('TELEGRAM_BOT_TOKEN="789:file_token"\nTELEGRAM_CHAT_ID="@file_channel"\n', encoding="utf-8")
        result = self.run_sender({"TG_NOTIFY_ENV": str(config)})
        self.assertEqual(result.returncode, 0, result.stderr)
        request = json.loads(self.capture.read_text(encoding="utf-8"))["config"]
        self.assertIn(TOKEN, request)
        self.assertIn(CHAT, request)
        self.assertNotIn("789:file_token", request)
        self.assertNotIn("@file_channel", request)

    def test_credentials_can_be_supplied_by_config_file(self):
        config = self.root / "synthetic.env"
        config.write_text('TELEGRAM_BOT_TOKEN="789:file_token"\nTELEGRAM_CHAT_ID="@file_channel"\n', encoding="utf-8")
        env = {k: v for k, v in self.env.items() if k not in {"TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID"}}
        env["TG_NOTIFY_ENV"] = str(config)
        result = subprocess.run(["bash", str(SENDER), "-q"], input=BODY, text=True,
                                capture_output=True, env=env, cwd=self.root, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)
        request = json.loads(self.capture.read_text(encoding="utf-8"))["config"]
        self.assertIn("789:file_token", request)
        self.assertIn("@file_channel", request)


@unittest.skipUnless(shutil.which("openssl") and Path("/usr/bin/curl").exists(), "requires openssl and system curl")
class RealCurlLoopback(unittest.TestCase):
    """Exercise the real curl/config interface against an isolated TLS server."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tg-curl-https-")
        self.root = Path(self.temp.name)
        self.cert, self.key = self.root / "cert.pem", self.root / "key.pem"
        subprocess.run(["openssl", "req", "-x509", "-nodes", "-newkey", "rsa:2048", "-days", "1",
                        "-subj", "/CN=api.telegram.org", "-addext", "subjectAltName=DNS:api.telegram.org",
                        "-keyout", str(self.key), "-out", str(self.cert)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        self.requests = []
        self.mode = "ok"
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_POST(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", "0"))).decode()
                owner.requests.append((self.path, urllib.parse.parse_qs(body)))
                status = 302 if owner.mode == "redirect" else 200
                self.send_response(status)
                if status == 302:
                    self.send_header("Location", "http://127.0.0.1:1/forbidden")
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(b'{"ok":true}')))
                self.end_headers()
                self.wfile.write(b'{"ok":true}')

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, self.key)
        self.server.socket = context.wrap_socket(self.server.socket, server_side=True)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        bindir = self.root / "bin"
        bindir.mkdir()
        wrapper = bindir / "curl"
        wrapper.write_text('#!/usr/bin/env bash\nexec /usr/bin/curl "$@" '
                           '--noproxy "*" --cacert "$TEST_CA" '
                           '--connect-to "api.telegram.org:443:127.0.0.1:$TEST_PORT"\n', encoding="utf-8")
        wrapper.chmod(0o700)
        self.env = {"PATH": str(bindir) + ":/usr/bin:/bin", "HOME": str(self.root), "LANG": "C.UTF-8",
                    "TG_NOTIFY_HOME": str(self.root / "state"), "TELEGRAM_BOT_TOKEN": TOKEN,
                    "TELEGRAM_CHAT_ID": CHAT, "TELEGRAM_THREAD_ID": "42", "TG_NOTIFY_MAX_ATTEMPTS": "1",
                    "TEST_CA": str(self.cert), "TEST_PORT": str(self.server.server_port)}

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        self.temp.cleanup()

    def run_sender(self):
        return subprocess.run(["bash", str(SENDER), "-q"], input=BODY, text=True, capture_output=True,
                              env=self.env, cwd=self.root, timeout=8)

    def test_real_curl_correct_form_and_tls(self):
        result = self.run_sender()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.requests), 1)
        path, form = self.requests[0]
        self.assertEqual(path, "/bot" + TOKEN + "/sendMessage")
        self.assertEqual(form["chat_id"], [CHAT])
        self.assertEqual(form["message_thread_id"], ["42"])
        self.assertEqual(form["text"], ["<pre>" + BODY + "</pre>"])

    def test_real_curl_rejects_redirect(self):
        self.mode = "redirect"
        result = self.run_sender()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("http=302", result.stderr)
        self.assertEqual(len(self.requests), 1)


if __name__ == "__main__":
    unittest.main()
