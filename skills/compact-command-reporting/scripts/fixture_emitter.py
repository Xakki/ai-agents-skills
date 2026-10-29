#!/usr/bin/env python3
"""Deterministic child process used only by the compact-reporting fixtures."""

import json
import os
import signal
import sys
import time


def write_all(fd, data):
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        if written <= 0:
            raise OSError("short fixture write")
        view = view[written:]


def write_marker(path, payload=None):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    try:
        write_all(fd, (str(os.getpid()) if payload is None else payload).encode("ascii"))
    finally:
        os.close(fd)


def main(argv):
    if not argv:
        return 2
    mode = argv[0]

    if mode == "large":
        write_all(1, b"KNOWN-PREFIX-BEGIN\n")
        write_all(2, b"MERGED-STDERR-MARKER\n")
        write_all(1, b"KNOWN-MIDDLE-BEGIN\n")
        for index in range(16000):
            write_all(1, f"middle-record-{index:05d}\n".encode("ascii"))
        write_all(2, b"KNOWN-MIDDLE-END\n")
        write_all(1, b"KNOWN-SUFFIX-END\n")
        return 0

    if mode == "giant":
        write_all(1, b"GIANT-LINE-BEGIN")
        block = b"x" * 65536
        for _ in range(5):
            write_all(1, block)
        write_all(2, b"GIANT-LINE-SUFFIX")
        return 0

    if mode == "unicode-control":
        write_all(1, "unicode: snow=雪 face=🙂\n".encode("utf-8"))
        write_all(2, b"invalid=\xff escape=\x1b[31mred\x1b[0m null=\x00\r\n")
        write_all(1, b"control-tail\n")
        return 0

    if mode == "control-giant":
        write_all(1, b"CONTROL-BEGIN")
        for _ in range(5):
            write_all(1, b"\xff\x1b\x00" * 22000)
        write_all(2, b"CONTROL-SUFFIX\n")
        return 0

    if mode == "launch-marker":
        write_marker(argv[1])
        write_all(1, b"FIXTURE-LAUNCHED\n")
        return 0

    if mode == "owned-descendant":
        marker = argv[1]
        signum = int(argv[2])

        def exit_parent(_signum, _frame):
            write_all(1, b"DIRECT-CHILD-SIGNALED\n")
            raise SystemExit(0)

        signal.signal(signum, exit_parent)
        descendant = os.fork()
        if descendant == 0:
            signal.signal(signum, signal.SIG_IGN)
            write_marker(marker, f"{os.getpid()} {os.getpgrp()}")
            write_all(1, b"DESCENDANT-READY\n")
        while True:
            time.sleep(0.05)

    if mode == "small":
        write_all(1, b"small-stdout\n")
        write_all(2, b"small-stderr\n")
        return 0

    if mode == "empty":
        return 0

    if mode == "marker":
        if len(argv) != 2:
            return 2
        write_all(1, argv[1].encode("utf-8") + b"\n")
        return 0

    if mode == "fail":
        write_all(1, b"failure-stdout\n")
        write_all(2, b"failure-stderr\n")
        return 23

    if mode == "argv":
        payload = {"cwd": os.getcwd(), "argv": argv[1:]}
        write_all(1, json.dumps(payload, ensure_ascii=False).encode("utf-8") + b"\n")
        return 0

    if mode in {"wait-signal", "hold"}:
        if len(argv) < 2:
            return 2
        marker = argv[1]
        if mode == "wait-signal":
            signal_mode = argv[2]
            if signal_mode == "handle-int":
                def handle_int(_signum, _frame):
                    write_all(1, b"CHILD-RECEIVED-SIGINT\n")
                    raise SystemExit(0)

                signal.signal(signal.SIGINT, handle_int)
            elif signal_mode == "record-ignore-term":
                def record_term(_signum, _frame):
                    write_all(1, b"CHILD-RECEIVED-SIGTERM\n")

                signal.signal(signal.SIGTERM, record_term)
            elif signal_mode != "default":
                return 2
        write_marker(marker)
        write_all(1, b"CHILD-READY\n")
        while True:
            time.sleep(0.1)

    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
