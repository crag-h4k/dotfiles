#!/usr/bin/env python3
# tests/ctty_run.py
# Run a command with a chosen controlling-terminal situation, so the interactive
# branches of home/.chezmoi.toml.tmpl are testable the same way on a developer's
# terminal and on a headless CI runner. The template probes /dev/tty and shells
# out to gum with </dev/tty 2>/dev/tty, which only works with a real controlling
# terminal. Unlike pty_run.py (which only exposes a tty path), this makes the pty
# the child's session terminal.
#
# Usage: ctty_run.py [--ctty | --stdin-tty | --stdin-only | --none] <command> [args...]
#   --ctty        (the default) a fresh pty is the controlling terminal; stdin stays
#                 the caller's (a pipe or file), so stdinIsATTY is false but
#                 /dev/tty opens.
#   --stdin-tty   a fresh pty is the controlling terminal AND the child's stdin, so
#                 stdinIsATTY is true as well.
#   --stdin-only  a pty is the child's stdin (stdinIsATTY is true) but is NOT its
#                 controlling terminal, so /dev/tty still does not open. This is
#                 the case chezmoi's own prompts cannot survive.
#   --none        a new session with no controlling terminal at all: /dev/tty does
#                 not open, even when the caller itself runs in a terminal.
# Everything the child writes to the terminal (gum's UI, printf >/dev/tty) is
# drained so it can never block, and saved to $CTTY_LOG when that is set. The
# child's own stdout and stderr stay the caller's, so a test can assert on them
# without terminal bytes mixed in. The exit status is the child's.
import fcntl
import os
import pty
import subprocess
import sys
import termios
import threading


def main():
    args = sys.argv[1:]
    mode = "ctty"
    if args and args[0] in ("--ctty", "--stdin-tty", "--stdin-only", "--none"):
        mode = args[0][2:]
        args = args[1:]
    if not args:
        sys.stderr.write("usage: ctty_run.py [--ctty | --stdin-tty | --stdin-only | --none] <command> [args...]\n")
        return 2

    if mode == "none":
        return subprocess.call(args, preexec_fn=os.setsid)

    master, slave = pty.openpty()
    chunks = []

    def drain():
        try:
            while True:
                data = os.read(master, 4096)
                if not data:
                    break
                chunks.append(data)
        except OSError:
            pass

    reader = threading.Thread(target=drain, daemon=True)
    reader.start()

    def child_setup():
        # New session, then (unless the pty is stdin only) adopt it as the
        # controlling terminal.
        os.setsid()
        if mode != "stdin-only":
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

    kwargs = {"stdin": slave} if mode in ("stdin-tty", "stdin-only") else {}
    proc = subprocess.Popen(args, preexec_fn=child_setup, pass_fds=(slave,), **kwargs)
    status = proc.wait()

    # The child is gone. Close our slave copy so the reader sees EOF, then reap it.
    os.close(slave)
    reader.join(timeout=2)
    try:
        os.close(master)
    except OSError:
        pass

    log = os.environ.get("CTTY_LOG")
    if log:
        with open(log, "wb") as handle:
            handle.write(b"".join(chunks))
    return status


if __name__ == "__main__":
    sys.exit(main())
