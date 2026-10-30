#!/usr/bin/env python3
"""Capture a command's complete combined output before returning a bounded tail."""

import argparse
import errno
import os
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unicodedata

DEFAULT_TAIL_LINES = 80
DEFAULT_TAIL_BYTES = 8192
MAX_TAIL_LINES = 10000
MAX_TAIL_BYTES = 65536
LOG_FAILURE_STATUS = 125
SIGNAL_GRACE_SECONDS = 2.0
WAIT_POLL_SECONDS = 0.05
SCAN_CHUNK_BYTES = 64 * 1024


def _bounded_positive(value, maximum, label):
    try:
        number = int(value, 10)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"{label} must be an integer") from exc
    if number < 1 or number > maximum:
        raise argparse.ArgumentTypeError(f"{label} must be between 1 and {maximum}")
    return number


def _parser():
    parser = argparse.ArgumentParser(
        prog="hermes-log-run",
        description="Capture merged command output to a private log and show a bounded tail.",
    )
    parser.add_argument(
        "--tail-lines",
        type=lambda value: _bounded_positive(value, MAX_TAIL_LINES, "tail-lines"),
        default=DEFAULT_TAIL_LINES,
    )
    parser.add_argument(
        "--tail-bytes",
        type=lambda value: _bounded_positive(value, MAX_TAIL_BYTES, "tail-bytes"),
        default=DEFAULT_TAIL_BYTES,
    )
    parser.add_argument("command", nargs=argparse.REMAINDER, help="literal command argv after --")
    return parser


def _escape_control_text(value):
    rendered = []
    for char in value:
        if char == "\n":
            rendered.append(char)
            continue
        category = unicodedata.category(char)
        if category.startswith("C") or category in {"Zl", "Zp"}:
            codepoint = ord(char)
            if codepoint <= 0xFF:
                rendered.append(f"\\x{codepoint:02x}")
            elif codepoint <= 0xFFFF:
                rendered.append(f"\\u{codepoint:04x}")
            else:
                rendered.append(f"\\U{codepoint:08x}")
        else:
            rendered.append(char)
    return "".join(rendered)


def _safe_path(path):
    return _escape_control_text(path)


def _write_text(stream, text):
    stream.write(text)
    stream.flush()


def _write_bytes(stream, data):
    binary = getattr(stream, "buffer", None)
    if binary is not None:
        binary.write(data)
        binary.flush()
    else:
        stream.write(data.decode("utf-8", "replace"))
        stream.flush()


def _write_all(fd, data):
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        if written <= 0:
            raise OSError(errno.EIO, "short write")
        view = view[written:]


def _create_private_log():
    temp_root = tempfile.mkdtemp(prefix="hermes-log-run-", dir=os.environ.get("TMPDIR") or None)
    temp_root = os.path.abspath(temp_root)
    os.chmod(temp_root, 0o700)
    directory_stat = os.stat(temp_root, follow_symlinks=False)
    if (
        not stat.S_ISDIR(directory_stat.st_mode)
        or directory_stat.st_uid != os.geteuid()
        or stat.S_IMODE(directory_stat.st_mode) != 0o700
    ):
        raise OSError(errno.EPERM, "private log directory verification failed")

    path = os.path.join(temp_root, "command.log")
    flags = os.O_RDWR | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    flags |= getattr(os, "O_CLOEXEC", 0)
    fd = os.open(path, flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
        file_stat = os.fstat(fd)
        if file_stat.st_uid != os.geteuid() or stat.S_IMODE(file_stat.st_mode) != 0o600:
            raise OSError(errno.EPERM, "private log file verification failed")
    except BaseException:
        os.close(fd)
        raise
    return temp_root, path, fd


def _fsync_log(fd):
    os.fsync(fd)


def _send_to_child_group(process, signum):
    try:
        os.killpg(process.pid, signum)
        return None
    except ProcessLookupError:
        return None
    except OSError as exc:
        try:
            # The leader remains unreaped until the final group signal, so its
            # PID cannot be recycled. Popen.send_signal/poll would reap it.
            os.kill(process.pid, signum)
        except OSError:
            pass
        return exc


def _wait_for_child(process, interrupted):
    sent_signal = None
    kill_deadline = None
    signal_error = None
    while True:
        if interrupted and sent_signal is None:
            sent_signal = interrupted[0]
            signal_error = _send_to_child_group(process, sent_signal)
            kill_deadline = time.monotonic() + SIGNAL_GRACE_SECONDS

        # Observe without reaping. Keeping the session/group leader reserved
        # prevents a later killpg from ever targeting a recycled PID/PGID.
        exited = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        if exited is not None and not interrupted:
            return process.wait(), sent_signal, signal_error

        if kill_deadline is not None and time.monotonic() >= kill_deadline:
            # An exited direct child does not mean its descendants exited.
            # Complete the same bounded group grace for INT and TERM alike.
            kill_error = _send_to_child_group(process, signal.SIGKILL)
            signal_error = signal_error or kill_error
            return process.wait(), sent_signal, signal_error

        time.sleep(WAIT_POLL_SECONDS)


def _line_count(size, newline_count, last_byte):
    if size == 0:
        return 0
    return newline_count + (1 if last_byte != b"\n" else 0)


def _pread_some(fd, length, offset):
    chunks = []
    remaining = length
    position = offset
    while remaining:
        chunk = os.pread(fd, remaining, position)
        if not chunk:
            break
        chunks.append(chunk)
        position += len(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def _inspect_log(fd, size, tail_lines, tail_bytes):
    position = 0
    newline_count = 0
    last_byte = b""
    while position < size:
        chunk = os.pread(fd, min(SCAN_CHUNK_BYTES, size - position), position)
        if not chunk:
            raise OSError(errno.EIO, "short read while scanning log")
        newline_count += chunk.count(b"\n")
        last_byte = chunk[-1:]
        position += len(chunk)

    raw_lines = _line_count(size, newline_count, last_byte)
    read_size = min(size, tail_bytes)
    tail_data = _pread_some(fd, read_size, size - read_size)
    if len(tail_data) != read_size:
        raise OSError(errno.EIO, "short read while collecting log tail")

    if not tail_data:
        selected = b""
        selected_line_count = 0
    else:
        ends_in_newline = tail_data.endswith(b"\n")
        pieces = tail_data.split(b"\n")
        if ends_in_newline:
            pieces.pop()
        selected_pieces = pieces[-tail_lines:]
        selected_line_count = len(selected_pieces)
        selected = b"\n".join(selected_pieces)
        if ends_in_newline and selected_pieces:
            selected += b"\n"

    safe_text = _escape_control_text(selected.decode("utf-8", "replace"))
    safe_bytes = safe_text.encode("utf-8")
    display_omitted_bytes = len(safe_bytes) > tail_bytes
    if display_omitted_bytes:
        safe_bytes = safe_bytes[-tail_bytes:]
        safe_bytes = safe_bytes.decode("utf-8", "ignore").encode("utf-8")

    omitted_bytes = size > read_size or len(selected) < len(tail_data) or display_omitted_bytes
    omitted_lines = raw_lines > selected_line_count
    return raw_lines, safe_bytes, omitted_bytes, omitted_lines, display_omitted_bytes


def _install_signal_handlers():
    interrupted = []
    previous = {}

    def record_signal(signum, _frame):
        if not interrupted:
            interrupted.append(signum)

    for signum in (signal.SIGINT, signal.SIGTERM):
        previous[signum] = signal.getsignal(signum)
        signal.signal(signum, record_signal)
    return interrupted, previous


def _restore_signal_handlers(previous):
    for signum, handler in previous.items():
        signal.signal(signum, handler)


def _result_line(classification, wrapper_status, child_status, log_path, size, lines,
                 omitted_bytes, omitted_lines, display_omitted_bytes, signum=None):
    fields = [
        "RESULT",
        f"classification={classification}",
        f"exit_code={wrapper_status}",
        f"child_exit_code={child_status if child_status is not None else 'not_started'}",
        f"log_state={'partial' if classification in {'INTERRUPTED', 'LOG_ERROR'} else 'finalized'}",
        f"log_path={_safe_path(log_path)}",
        f"raw_bytes={size if size is not None else 'unknown'}",
        f"raw_lines={lines if lines is not None else 'unknown'}",
        f"omitted_bytes={'yes' if omitted_bytes else 'no'}",
        f"omitted_lines={'yes' if omitted_lines else 'no'}",
        f"display_omitted_bytes={'yes' if display_omitted_bytes else 'no'}",
    ]
    if signum is not None:
        fields.append(f"signal={signum}")
    return " ".join(fields) + "\n"


def run_command(command, tail_lines=DEFAULT_TAIL_LINES, tail_bytes=DEFAULT_TAIL_BYTES):
    if not all(hasattr(os, name) for name in ('waitid', 'P_PID', 'WEXITED', 'WNOHANG', 'WNOWAIT')):
        _write_text(sys.stderr, 'FAIL classification=platform requires=POSIX_waitid_WNOWAIT\n')
        return LOG_FAILURE_STATUS
    interrupted, previous_handlers = _install_signal_handlers()
    log_path = None
    fd = None
    child_status = None
    wrapper_status = LOG_FAILURE_STATUS
    classification = "LOG_ERROR"
    raw_size = None
    raw_lines = None
    rendered_tail = b""
    omitted_bytes = False
    omitted_lines = False
    display_omitted_bytes = False
    signal_number = None
    log_error = None

    try:
        try:
            _temp_root, log_path, fd = _create_private_log()
        except OSError as exc:
            _write_text(sys.stderr, f"FAIL classification=log errno={exc.errno or 'unknown'}\n")
            return LOG_FAILURE_STATUS

        try:
            _write_text(sys.stdout, f"LOG_PATH={_safe_path(log_path)}\n")
        except (OSError, UnicodeError):
            return LOG_FAILURE_STATUS

        if not interrupted:
            try:
                process = subprocess.Popen(
                    command,
                    stdin=None,
                    stdout=fd,
                    stderr=fd,
                    close_fds=True,
                    start_new_session=True,
                )
            except OSError as exc:
                child_status = 127 if exc.errno == errno.ENOENT else 126
                diagnostic = f"hermes-log-run: command execution failed (errno={exc.errno or 'unknown'})\n".encode()
                try:
                    _write_all(fd, diagnostic)
                except OSError as write_exc:
                    log_error = write_exc
            else:
                child_return_code, forwarded_signal, _signal_error = _wait_for_child(process, interrupted)
                child_status = 128 + (-child_return_code) if child_return_code < 0 else child_return_code
                signal_number = forwarded_signal

        if interrupted:
            signal_number = interrupted[0]
            wrapper_status = 128 + signal_number
            classification = "INTERRUPTED"
        elif child_status is not None:
            wrapper_status = child_status
            classification = "OK" if child_status == 0 else "FAIL"

        try:
            _fsync_log(fd)
        except OSError as exc:
            log_error = log_error or exc

        try:
            file_stat = os.fstat(fd)
            raw_size = file_stat.st_size
            raw_lines, rendered_tail, omitted_bytes, omitted_lines, display_omitted_bytes = _inspect_log(
                fd, raw_size, tail_lines, tail_bytes
            )
        except OSError as exc:
            log_error = log_error or exc

        try:
            os.close(fd)
            fd = None
        except OSError as exc:
            log_error = log_error or exc

        if log_error is not None:
            wrapper_status = LOG_FAILURE_STATUS
            classification = "LOG_ERROR"
        elif interrupted:
            # A cancellation during log finalization is still not success.
            signal_number = interrupted[0]
            wrapper_status = 128 + signal_number
            classification = "INTERRUPTED"

        try:
            _write_text(
                sys.stdout,
                _result_line(
                    classification,
                    wrapper_status,
                    child_status,
                    log_path,
                    raw_size,
                    raw_lines,
                    omitted_bytes,
                    omitted_lines,
                    display_omitted_bytes,
                    signal_number,
                ),
            )
            _write_bytes(sys.stdout, rendered_tail)
        except (OSError, UnicodeError):
            return LOG_FAILURE_STATUS
        return wrapper_status
    finally:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
        _restore_signal_handlers(previous_handlers)


def main(argv=None):
    parser = _parser()
    options = parser.parse_args(argv)
    command = list(options.command)
    if command and command[0] == "--":
        command.pop(0)
    if not command:
        parser.error("expected COMMAND ARG... after --")
    return run_command(command, options.tail_lines, options.tail_bytes)


if __name__ == "__main__":
    sys.exit(main())
