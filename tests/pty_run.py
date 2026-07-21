#!/usr/bin/env python3
# tests/pty_run.py
# Run a command with a real controlling pty exposed as DOTFILES_TTY, feed it one
# canned response line, and print ONLY the command's own stdout so a bats test can
# assert the exact result token without the menu bytes (written to the tty) mixing
# in. Used to drive confirm-install.sh's interactive menu deterministically.
#
# Usage: pty_run.py <response-without-newline> <command> [args...]
#   A trailing newline is appended to <response> before it is written to the pty.
#   The child's PATH/other env is inherited from this process (the bats test sets
#   it), plus DOTFILES_TTY is pointed at the pty slave.
import os
import pty
import subprocess
import sys
import threading


def _drain(fd):
    # Consume everything the child writes to the tty (menu/plan) so a full tty
    # buffer never blocks the child mid-write.
    try:
        while True:
            if not os.read(fd, 1024):
                break
    except OSError:
        pass


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: pty_run.py <response> <command> [args...]\n")
        return 2

    response = sys.argv[1]
    cmd = sys.argv[2:]

    master, slave = pty.openpty()
    env = dict(os.environ)
    env["DOTFILES_TTY"] = os.ttyname(slave)

    # The child (with close_fds) opens the pty by name on its own schedule. Keep
    # our slave fd open the whole time so the pty always has a slave endpoint;
    # otherwise a write to master before the child opens the pts raises EIO.
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, close_fds=True
    )

    drainer = threading.Thread(target=_drain, args=(master,), daemon=True)
    drainer.start()
    os.write(master, (response + "\n").encode())

    out, err = proc.communicate()
    # Child is dead now, so no more master writes can happen. Close our slave copy
    # so the drain thread's read hits EOF and exits, then reap it and close master.
    try:
        os.close(slave)
    except OSError:
        pass
    drainer.join(timeout=2)
    try:
        os.close(master)
    except OSError:
        pass

    sys.stdout.buffer.write(out)
    sys.stderr.buffer.write(err)
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
