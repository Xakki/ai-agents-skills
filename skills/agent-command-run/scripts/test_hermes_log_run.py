#!/usr/bin/env python3
"""Stdlib regression tests for hermes-log-run; no network or external services."""

import argparse
import ctypes
import errno
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stdout
from unittest import mock

sys.dont_write_bytecode = True
SCRIPT_DIR = Path(__file__).resolve().parent
WRAPPER = SCRIPT_DIR / "hermes-log-run.py"
FIXTURE = SCRIPT_DIR / "fixture_emitter.py"
EVIDENCE = []
RUN_ROOT = Path(".")
EXPECTED_CWD = ""


def load_wrapper_module():
    spec = importlib.util.spec_from_file_location("hermes_log_run_under_test", WRAPPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load wrapper module for finalization fixture")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_capture(stdout):
    first_end = stdout.find(b"\n")
    if first_end < 0:
        raise AssertionError(f"missing startup path line: {stdout!r}")
    first_line = stdout[:first_end].decode("utf-8", "replace")
    if not first_line.startswith("LOG_PATH="):
        raise AssertionError(f"unexpected startup line: {first_line!r}")
    second_start = first_end + 1
    second_end = stdout.find(b"\n", second_start)
    if second_end < 0:
        raise AssertionError(f"missing result line: {stdout!r}")
    result_line = stdout[second_start:second_end].decode("utf-8", "replace")
    fields = {}
    for token in result_line.split()[1:]:
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return Path(first_line[len("LOG_PATH="):]), fields, stdout[second_end + 1:]


def run_capture(command, name, options=(), timeout=20):
    env = os.environ.copy()
    env["TMPDIR"] = str(RUN_ROOT)
    argv = [sys.executable, str(WRAPPER), *options, "--", *command]
    completed = subprocess.run(
        argv,
        cwd=EXPECTED_CWD,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    log_path, fields, tail = parse_capture(completed.stdout)
    EVIDENCE.append(f"{name}: wrapper_exit={completed.returncode}, child_exit={fields.get('child_exit_code')}, log={log_path}")
    if completed.stderr:
        EVIDENCE.append(f"{name}: wrapper_stderr={completed.stderr.decode('utf-8', 'replace')!r}")
    return completed, log_path, fields, tail


def assert_private(testcase, log_path):
    directory_stat = log_path.parent.stat(follow_symlinks=False)
    file_stat = log_path.stat(follow_symlinks=False)
    testcase.assertTrue(stat.S_ISDIR(directory_stat.st_mode))
    testcase.assertEqual(directory_stat.st_uid, os.geteuid())
    testcase.assertEqual(stat.S_IMODE(directory_stat.st_mode), 0o700)
    testcase.assertEqual(file_stat.st_uid, os.geteuid())
    testcase.assertEqual(stat.S_IMODE(file_stat.st_mode), 0o600)


def wait_for_file(path, process, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return int(path.read_text(encoding="ascii"))
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            raise AssertionError(f"process exited before readiness: {stdout!r} {stderr!r}")
        time.sleep(0.01)
    raise AssertionError(f"fixture did not become ready: {path}")


def save_private(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        view = memoryview(data)
        while view:
            written = os.write(fd, view)
            if written <= 0:
                raise OSError("short fixture evidence write")
            view = view[written:]
        os.fsync(fd)
    finally:
        os.close(fd)


def prepare_artifact_root(path):
    """Create a private root or accept an already-private owned real directory."""
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError("artifact root must be an owner-held mode-0700 real directory")
    return path


class CompactCommandReportingTests(unittest.TestCase):
    def test_artifact_root_refuses_existing_loose_or_symlink_without_chmod(self):
        with tempfile.TemporaryDirectory(prefix="capture-root-test-") as directory:
            parent = Path(directory)
            loose = parent / "existing"
            loose.mkdir(mode=0o755)
            os.chmod(loose, 0o755)
            with self.assertRaises(ValueError):
                prepare_artifact_root(loose)
            self.assertEqual(stat.S_IMODE(loose.lstat().st_mode), 0o755)
            link = parent / "link"
            link.symlink_to(loose, target_is_directory=True)
            with self.assertRaises(ValueError):
                prepare_artifact_root(link)
            self.assertEqual(stat.S_IMODE(loose.lstat().st_mode), 0o755)

    def test_artifact_root_creates_private_directory_and_accepts_it(self):
        with tempfile.TemporaryDirectory(prefix="capture-root-test-") as directory:
            target = Path(directory) / "new"
            self.assertEqual(prepare_artifact_root(target), target)
            self.assertEqual(stat.S_IMODE(target.lstat().st_mode), 0o700)
            self.assertEqual(prepare_artifact_root(target), target)

    def test_public_limits_reject_before_underlying_fixture_starts(self):
        env = os.environ.copy()
        env["TMPDIR"] = str(RUN_ROOT)
        for option, value in (("--tail-bytes", "65537"), ("--tail-bytes", "1048576"),
                              ("--tail-lines", "10001")):
            with self.subTest(option=option, value=value):
                marker = RUN_ROOT / f"rejected-{option[2:]}-{value}.pid"
                completed = subprocess.run(
                    [sys.executable, str(WRAPPER), option, value, "--", sys.executable,
                     str(FIXTURE), "launch-marker", str(marker)],
                    cwd=EXPECTED_CWD, env=env, stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, timeout=5, check=False,
                )
                self.assertEqual(completed.returncode, 2)
                self.assertFalse(marker.exists(), "rejected options must not launch the child")
                self.assertEqual(completed.stdout, b"")
                self.assertIn(b"must be between", completed.stderr)
                evidence = RUN_ROOT / f"rejected-{option[2:]}-{value}.stderr"
                save_private(evidence, completed.stderr)
                EVIDENCE.append(f"rejected-{option}-{value}: wrapper_exit=2, child_started=false, evidence={evidence}")

    def test_maximum_rendered_tail_keeps_full_native_metadata(self):
        for mode in ("large", "giant", "control-giant"):
            with self.subTest(mode=mode):
                completed, log_path, fields, tail = run_capture(
                    [sys.executable, str(FIXTURE), mode], f"maximum-tail-{mode}",
                    options=("--tail-lines", "10000", "--tail-bytes", "65536"),
                )
                self.assertEqual(completed.returncode, 0)
                self.assertLessEqual(len(tail), 65536)
                self.assertLessEqual(tail.count(b"\n") + bool(tail and not tail.endswith(b"\n")), 10000)
                visible = completed.stdout.decode("utf-8", "strict")
                self.assertLess(len(visible), 200000)
                self.assertIn("LOG_PATH=" + str(log_path), visible[-200000:])
                self.assertIn("RESULT classification=OK exit_code=0 child_exit_code=0", visible[-200000:])
                self.assertEqual(fields["log_state"], "finalized")
                assert_private(self, log_path)
                if mode == "control-giant":
                    self.assertEqual(fields["display_omitted_bytes"], "yes")
                    self.assertNotIn(b"\x1b", tail)
                    self.assertNotIn(b"\x00", tail)
                    self.assertIn(b"CONTROL-SUFFIX", tail)
                    self.assertIn(b"\xff\x1b\x00", log_path.read_bytes())
                elif mode == "giant":
                    self.assertIn(b"GIANT-LINE-SUFFIX", tail)
                else:
                    self.assertIn(b"KNOWN-SUFFIX-END", tail)
                evidence = RUN_ROOT / f"maximum-tail-{mode}.stdout"
                save_private(evidence, completed.stdout)
                EVIDENCE.append(f"maximum-tail-{mode}: visible_chars={len(visible)}, tail_bytes={len(tail)}, metadata_retained=true, stdout={evidence}")

    def test_owned_group_is_signaled_before_leader_is_reaped(self):
        module = load_wrapper_module()
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signum):
                events = []
                process = mock.Mock(pid=12345)
                process.wait.side_effect = lambda: events.append("reap") or 0

                def send(_process, sent):
                    events.append(sent)
                    return None

                with mock.patch.object(module.os, "waitid", return_value=object()), \
                     mock.patch.object(module, "_send_to_child_group", side_effect=send), \
                     mock.patch.object(module.time, "monotonic", side_effect=[0.0, 0.0, 2.0]), \
                     mock.patch.object(module.time, "sleep"):
                    result = module._wait_for_child(process, [signum])
                self.assertEqual(result, (0, signum, None))
                self.assertEqual(events, [signum, signal.SIGKILL, "reap"])
                process.poll.assert_not_called()
                process.send_signal.assert_not_called()
        EVIDENCE.append("leader-reservation: INT/TERM final group signal precedes reap; no Popen.poll/send_signal")

    def test_skill_description_and_documented_limits_match_source(self):
        skill = SCRIPT_DIR.parent
        skill_text = (skill / "SKILL.md").read_text(encoding="utf-8")
        description = next(line.removeprefix("description: ") for line in skill_text.splitlines()
                           if line.startswith("description: "))
        self.assertTrue(description.strip())
        self.assertLessEqual(len(description), 160)
        module = load_wrapper_module()
        self.assertEqual((module.DEFAULT_TAIL_LINES, module.DEFAULT_TAIL_BYTES), (80, 8192))
        self.assertEqual((module.MAX_TAIL_LINES, module.MAX_TAIL_BYTES), (10000, 65536))
        self.assertEqual(module.SIGNAL_GRACE_SECONDS, 2.0)
        for expected in ("80 lines", "8192 bytes", "10,000 lines", "65,536 bytes", "2 seconds", "partial"):
            self.assertIn(expected, skill_text)
        self.assertNotIn("1 MiB", skill_text)
        EVIDENCE.append(f"description: length={len(description)}; documented defaults/caps/grace match source")

    def _owned_descendant_signal(self, signum):
        # Linux subreaper applies ONLY to this owned fixture runner. Restore it
        # after reaping every test-owned grandchild; never change parent Hermes.
        libc = ctypes.CDLL(None, use_errno=True)
        previous = ctypes.c_int()
        if libc.prctl(37, ctypes.byref(previous), 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), "cannot query fixture subreaper")
        if libc.prctl(36, 1, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), "cannot enable fixture subreaper")
        env = os.environ.copy()
        env["TMPDIR"] = str(RUN_ROOT)
        marker = RUN_ROOT / f"owned-descendant-{signum}.pid"
        sibling_marker = RUN_ROOT / f"descendant-sentinel-{signum}.pid"
        sibling = None
        process = None
        descendant = None
        reaped = False
        try:
            sibling = subprocess.Popen(
                [sys.executable, str(FIXTURE), "hold", str(sibling_marker)],
                cwd=EXPECTED_CWD, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            wait_for_file(sibling_marker, sibling)
            process = subprocess.Popen(
                [sys.executable, str(WRAPPER), "--", sys.executable, str(FIXTURE),
                 "owned-descendant", str(marker), str(signum)],
                cwd=EXPECTED_CWD, env=env, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, start_new_session=True)
            deadline = time.monotonic() + 5
            while not marker.exists():
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise AssertionError("owned descendant readiness failed")
                time.sleep(0.01)
            descendant, group = map(int, marker.read_text(encoding="ascii").split())
            self.assertEqual(os.getpgid(descendant), group)
            self.assertNotEqual(group, os.getpgrp())
            self.assertNotEqual(group, os.getpgid(sibling.pid))
            start = time.monotonic()
            os.kill(process.pid, signum)
            stdout, stderr = process.communicate(timeout=7)
            elapsed = time.monotonic() - start
            log_path, fields, _ = parse_capture(stdout)
            event = os.waitid(os.P_PID, descendant, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            running = event is None
            evidence = RUN_ROOT / f"owned-descendant-{signum}.stdout"
            save_private(evidence, stdout)
            self.assertEqual(process.returncode, 128 + signum)
            self.assertFalse(stderr)
            self.assertEqual(fields["child_exit_code"], "0")
            self.assertEqual(fields["classification"], "INTERRUPTED")
            self.assertEqual(fields["log_state"], "partial")
            self.assertGreaterEqual(elapsed, 1.9)
            self.assertLess(elapsed, 5.0)
            self.assertFalse(running, "TERM/INT-ignoring owned descendant must not remain running")
            if event is None:
                raise AssertionError("missing descendant wait event")
            self.assertEqual(event.si_code, os.CLD_KILLED)
            self.assertEqual(event.si_status, signal.SIGKILL)
            waited, _ = os.waitpid(descendant, 0)
            reaped = waited == descendant
            self.assertTrue(reaped)
            self.assertIsNone(sibling.poll(), "unrelated sentinel must survive group cleanup")
            self.assertIn(b"DIRECT-CHILD-SIGNALED", log_path.read_bytes())
            assert_private(self, log_path)
            EVIDENCE.append(f"owned-descendant-{signum}: wrapper_exit={process.returncode}, child_exit=0, elapsed={elapsed:.3f}s, running=false, zombie=true, reaped=true, sentinel_survived=true, log={log_path}, stdout={evidence}")
        finally:
            if process is not None and process.poll() is None:
                os.kill(process.pid, signal.SIGTERM)
                try:
                    process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate(timeout=3)
            if descendant is not None and not reaped:
                event = os.waitid(os.P_PID, descendant, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                if event is None:
                    os.kill(descendant, signal.SIGKILL)
                deadline = time.monotonic() + 3
                while True:
                    waited, _ = os.waitpid(descendant, os.WNOHANG)
                    if waited == descendant:
                        break
                    if time.monotonic() >= deadline:
                        raise RuntimeError("failed to reap test-owned descendant")
                    time.sleep(0.01)
            if sibling is not None and sibling.poll() is None:
                sibling.terminate()
                sibling.wait(timeout=3)
            if libc.prctl(36, previous.value, 0, 0, 0) != 0:
                raise OSError(ctypes.get_errno(), "cannot restore fixture subreaper")

    def test_sigint_cleans_owned_descendant_after_direct_child_exits(self):
        self._owned_descendant_signal(signal.SIGINT)

    def test_sigterm_cleans_owned_descendant_after_direct_child_exits(self):
        self._owned_descendant_signal(signal.SIGTERM)

    def test_skill_entrypoint_and_large_capture_are_private_and_exact(self):
        self.assertTrue(os.access(WRAPPER, os.X_OK), "wrapper script must be executable")
        completed, log_path, fields, tail = run_capture(
            [sys.executable, str(FIXTURE), "large"], "large-capture"
        )
        expected = bytearray(b"KNOWN-PREFIX-BEGIN\nMERGED-STDERR-MARKER\nKNOWN-MIDDLE-BEGIN\n")
        for index in range(16000):
            expected.extend(f"middle-record-{index:05d}\n".encode("ascii"))
        expected.extend(b"KNOWN-MIDDLE-END\nKNOWN-SUFFIX-END\n")
        actual = log_path.read_bytes()
        self.assertGreater(len(actual), 200000)
        self.assertEqual(actual, bytes(expected))
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(fields["classification"], "OK")
        self.assertEqual(fields["raw_bytes"], str(len(actual)))
        self.assertEqual(fields["omitted_bytes"], "yes")
        self.assertIn(b"KNOWN-SUFFIX-END", tail)
        self.assertNotIn(b"KNOWN-PREFIX-BEGIN", tail)
        self.assertLessEqual(len(tail), 8192)
        self.assertLessEqual(len(completed.stdout), 8192 + 1024)
        tail_lines = tail.count(b"\n") + (1 if tail and not tail.endswith(b"\n") else 0)
        self.assertLessEqual(tail_lines, 80)
        assert_private(self, log_path)

    def test_custom_limits_and_giant_single_line(self):
        completed, log_path, fields, tail = run_capture(
            [sys.executable, str(FIXTURE), "large"],
            "custom-limits",
            options=("--tail-lines", "3", "--tail-bytes", "64"),
        )
        self.assertEqual(completed.returncode, 0)
        self.assertLessEqual(len(tail), 64)
        self.assertLessEqual(tail.count(b"\n") + (1 if tail and not tail.endswith(b"\n") else 0), 3)
        self.assertIn(b"KNOWN-SUFFIX-END", tail)
        self.assertEqual(fields["omitted_lines"], "yes")
        self.assert_private_file_content(log_path)

        giant, giant_path, giant_fields, giant_tail = run_capture(
            [sys.executable, str(FIXTURE), "giant"], "giant-line"
        )
        self.assertEqual(giant.returncode, 0)
        self.assertGreater(giant_path.stat().st_size, 300000)
        self.assertIn(b"GIANT-LINE-SUFFIX", giant_tail)
        self.assertNotIn(b"GIANT-LINE-BEGIN", giant_tail)
        self.assertLessEqual(len(giant_tail), 8192)
        self.assertLessEqual(giant_tail.count(b"\n") + (1 if giant_tail and not giant_tail.endswith(b"\n") else 0), 80)
        self.assertEqual(giant_fields["raw_lines"], "1")

    def assert_private_file_content(self, log_path):
        assert_private(self, log_path)

    def test_unicode_invalid_utf8_and_control_bytes_are_safely_rendered(self):
        completed, log_path, _fields, tail = run_capture(
            [sys.executable, str(FIXTURE), "unicode-control"], "unicode-control"
        )
        raw = log_path.read_bytes()
        self.assertEqual(completed.returncode, 0)
        self.assertIn("雪".encode("utf-8"), tail)
        self.assertIn("🙂".encode("utf-8"), tail)
        self.assertIn("�".encode("utf-8"), tail)
        self.assertIn(b"\\x1b", tail)
        self.assertIn(b"\\x00", tail)
        self.assertNotIn(b"\x1b", tail)
        self.assertNotIn(b"\x00", tail)
        self.assertNotIn(b"\r", tail)
        self.assertIn(b"\xff", raw)
        self.assertIn(b"\x1b", raw)
        self.assertIn(b"\x00", raw)
        self.assert_private_file_content(log_path)

    def test_small_empty_nonzero_missing_and_non_executable(self):
        small, small_path, small_fields, small_tail = run_capture(
            [sys.executable, str(FIXTURE), "small"], "small-output"
        )
        self.assertEqual(small.returncode, 0)
        self.assertEqual(small_fields["omitted_bytes"], "no")
        self.assertEqual(small_fields["omitted_lines"], "no")
        self.assertEqual(small_tail, b"small-stdout\nsmall-stderr\n")
        self.assertEqual(small_path.read_bytes(), small_tail)

        empty, empty_path, empty_fields, empty_tail = run_capture(
            [sys.executable, str(FIXTURE), "empty"], "empty-output"
        )
        self.assertEqual(empty.returncode, 0)
        self.assertEqual(empty_fields["raw_bytes"], "0")
        self.assertEqual(empty_tail, b"")
        self.assertEqual(empty_path.read_bytes(), b"")

        failure, failure_path, failure_fields, _failure_tail = run_capture(
            [sys.executable, str(FIXTURE), "fail"], "nonzero-exit"
        )
        self.assertEqual(failure.returncode, 23)
        self.assertEqual(failure_fields["exit_code"], "23")
        self.assertEqual(failure_fields["classification"], "FAIL")
        self.assertEqual(failure_path.read_bytes(), b"failure-stdout\nfailure-stderr\n")

        missing_path = RUN_ROOT / "missing-command-does-not-exist"
        missing, missing_log, missing_fields, _ = run_capture(
            [str(missing_path)], "missing-executable"
        )
        self.assertEqual(missing.returncode, 127)
        self.assertEqual(missing_fields["exit_code"], "127")
        self.assertIn(b"command execution failed", missing_log.read_bytes())

        nonexec = RUN_ROOT / "fixture-no-execute-bit"
        nonexec.write_bytes(b"not executable\n")
        os.chmod(nonexec, 0o600)
        denied, denied_log, denied_fields, _ = run_capture(
            [str(nonexec)], "non-executable"
        )
        self.assertEqual(denied.returncode, 126)
        self.assertEqual(denied_fields["exit_code"], "126")
        self.assertIn(b"command execution failed", denied_log.read_bytes())

    def test_cwd_and_quoted_argv_are_literal(self):
        literals = ["space value", "single'quote", 'double"quote', "semi;$(not-shell)", "--looks-like-option"]
        completed, log_path, _fields, tail = run_capture(
            [sys.executable, str(FIXTURE), "argv", *literals], "literal-argv"
        )
        payload = json.loads(log_path.read_text(encoding="utf-8"))
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(payload["cwd"], EXPECTED_CWD)
        self.assertEqual(payload["argv"], literals)
        self.assertEqual(tail, log_path.read_bytes())

    def test_concurrent_invocations_get_unique_private_logs(self):
        env = os.environ.copy()
        env["TMPDIR"] = str(RUN_ROOT)
        processes = []
        for marker in ("concurrent-alpha", "concurrent-beta"):
            command = [sys.executable, str(FIXTURE), "marker", marker]
            processes.append((marker, subprocess.Popen(
                [sys.executable, str(WRAPPER), "--", *command],
                cwd=EXPECTED_CWD,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )))
        results = []
        for marker, process in processes:
            stdout, stderr = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 0, stderr.decode("utf-8", "replace"))
            log_path, fields, tail = parse_capture(stdout)
            self.assertEqual(fields["classification"], "OK")
            self.assertEqual(log_path.read_bytes(), marker.encode() + b"\n")
            self.assertEqual(tail, marker.encode() + b"\n")
            assert_private(self, log_path)
            results.append(log_path)
            EVIDENCE.append(f"concurrent-{marker}: wrapper_exit=0 log={log_path}")
        self.assertNotEqual(results[0], results[1])
        self.assertNotEqual(results[0].parent, results[1].parent)

    def _signal_wrapper(self, signal_mode, signum, name):
        marker = RUN_ROOT / f"{name}-child-pid"
        env = os.environ.copy()
        env["TMPDIR"] = str(RUN_ROOT)
        command = [sys.executable, str(FIXTURE), "wait-signal", str(marker), signal_mode]
        process = subprocess.Popen(
            [sys.executable, str(WRAPPER), "--", *command],
            cwd=EXPECTED_CWD,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        child_pid = None
        start = time.monotonic()
        try:
            child_pid = wait_for_file(marker, process)
            os.kill(process.pid, signum)
            stdout, stderr = process.communicate(timeout=6)
        except BaseException:
            if process.poll() is None:
                os.kill(process.pid, signal.SIGKILL)
                process.communicate(timeout=3)
            if child_pid is not None:
                try:
                    os.kill(child_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            raise
        elapsed = time.monotonic() - start
        log_path, fields, _tail = parse_capture(stdout)
        EVIDENCE.append(
            f"{name}: wrapper_exit={process.returncode}, elapsed={elapsed:.3f}s, log={log_path}"
        )
        self.assertFalse(stderr, stderr.decode("utf-8", "replace"))
        return process, child_pid, elapsed, log_path, fields

    def test_sigint_forwarding_reaping_and_process_group_isolation(self):
        sibling_marker = RUN_ROOT / "unrelated-sibling-pid"
        env = os.environ.copy()
        env["TMPDIR"] = str(RUN_ROOT)
        sibling = subprocess.Popen(
            [sys.executable, str(FIXTURE), "hold", str(sibling_marker)],
            cwd=EXPECTED_CWD,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        child_pid = None
        try:
            wait_for_file(sibling_marker, sibling)
            process, child_pid, elapsed, log_path, fields = self._signal_wrapper(
                "handle-int", signal.SIGINT, "sigint"
            )
            self.assertEqual(process.returncode, 128 + signal.SIGINT)
            self.assertEqual(fields["classification"], "INTERRUPTED")
            self.assertEqual(fields["signal"], str(signal.SIGINT))
            self.assertLess(elapsed, 4.0)
            self.assertIn(b"CHILD-RECEIVED-SIGINT", log_path.read_bytes())
            self.assertIsNone(sibling.poll(), "wrapper signal must not affect an unrelated process")
            with self.assertRaises(ProcessLookupError):
                os.kill(child_pid, 0)
        finally:
            if sibling.poll() is None:
                sibling.terminate()
                sibling.wait(timeout=3)

    def test_sigterm_forwarding_has_bounded_grace_and_reaps_child(self):
        process, child_pid, elapsed, log_path, fields = self._signal_wrapper(
            "record-ignore-term", signal.SIGTERM, "sigterm"
        )
        self.assertEqual(process.returncode, 128 + signal.SIGTERM)
        self.assertEqual(fields["classification"], "INTERRUPTED")
        self.assertEqual(fields["signal"], str(signal.SIGTERM))
        self.assertGreaterEqual(elapsed, 1.5)
        self.assertLess(elapsed, 5.0)
        self.assertIn(b"CHILD-RECEIVED-SIGTERM", log_path.read_bytes())
        with self.assertRaises(ProcessLookupError):
            os.kill(child_pid, 0)

    def test_log_finalization_failure_never_reports_success(self):
        module = load_wrapper_module()
        captured = io.StringIO()
        env_patch = mock.patch.dict(os.environ, {"TMPDIR": str(RUN_ROOT)})
        fsync_patch = mock.patch.object(module, "_fsync_log", side_effect=OSError(errno.EIO, "fixture fsync failure"))
        with env_patch, fsync_patch, redirect_stdout(captured):
            status = module.main(["--", sys.executable, str(FIXTURE), "small"])
        output = captured.getvalue().encode("utf-8")
        log_path, fields, _tail = parse_capture(output)
        self.assertEqual(status, 125)
        self.assertEqual(fields["classification"], "LOG_ERROR")
        self.assertEqual(fields["exit_code"], "125")
        self.assertEqual(fields["child_exit_code"], "0")
        self.assertNotIn("classification=OK", output.decode("utf-8"))
        self.assertEqual(log_path.read_bytes(), b"small-stdout\nsmall-stderr\n")
        EVIDENCE.append(f"finalization-failure: wrapper_exit={status}, child_exit=0, log={log_path}")


def write_report(path, run_root, tests_run, failures, errors):
    lines = [
        "# hermes-log-run fixture report",
        "",
        f"- Tests run: {tests_run}",
        f"- Failures: {failures}",
        f"- Errors: {errors}",
        f"- Fixture log root: {run_root}",
        f"- Wrapper: {WRAPPER}",
        f"- Fixture: {FIXTURE}",
        "",
        "## Captured command evidence",
        "",
    ]
    lines.extend(f"- {item}" for item in EVIDENCE)
    report_bytes = ("\n".join(lines) + "\n").encode("utf-8")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        view = memoryview(report_bytes)
        while view:
            written = os.write(fd, view)
            if written <= 0:
                raise OSError("short fixture report write")
            view = view[written:]
        os.fsync(fd)
    finally:
        os.close(fd)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-root", required=True)
    parser.add_argument("--report-path", required=True)
    options = parser.parse_args()

    artifact_root = Path(options.artifact_root).absolute()
    prepare_artifact_root(artifact_root)
    global RUN_ROOT, EXPECTED_CWD
    RUN_ROOT = Path(tempfile.mkdtemp(prefix="fixture-run-", dir=artifact_root))
    os.chmod(RUN_ROOT, 0o700)
    EXPECTED_CWD = os.getcwd()

    suite = unittest.defaultTestLoader.loadTestsFromTestCase(CompactCommandReportingTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    write_report(Path(options.report_path).absolute(), RUN_ROOT, result.testsRun, len(result.failures), len(result.errors))
    print(f"FIXTURE_REPORT={Path(options.report_path).absolute()}")
    print(f"FIXTURE_LOG_ROOT={RUN_ROOT}")
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
