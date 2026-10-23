#!/usr/bin/env python3
# tests/tmux_client.py
# Attach a real tmux client to a session on an isolated socket, through a pty, so
# a bats test can exercise code that asks tmux whether a client is attached and
# focused. A detached session has no client, so #{client_flags} is empty and
# nothing about focus can be tested. This never touches a live server: the socket
# name is the caller's and the process only attaches.
#
# Usage: tmux_client.py <socket-name> <session>
#   stdin    every byte read is typed into the client, like a keypress. A test
#            holds a FIFO open on it to send keys; /dev/null just ends the reader.
#   SIGUSR1  report terminal focus-out (CSI O), like switching to another app
#   SIGUSR2  report terminal focus-in  (CSI I)
#   SIGTERM  detach and exit
# A fresh tmux client counts as focused until the terminal reports otherwise.
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import threading

FOCUS_IN = b"\x1b[I"
FOCUS_OUT = b"\x1b[O"


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: tmux_client.py <socket-name> <session>\n")
        return 2
    socket_name, session = sys.argv[1], sys.argv[2]
    pid, fd = pty.fork()
    if pid == 0:
        # Attaching with TMUX set is refused as nesting; this client is the outer one.
        os.environ.pop("TMUX", None)
        os.environ.pop("TMUX_PANE", None)
        os.environ["TERM"] = "xterm-256color"
        os.execvp("tmux", ["tmux", "-L", socket_name, "attach", "-t", session])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))

    def drain():
        # tmux repaints constantly; an unread pty buffer would block the client.
        while True:
            try:
                ready, _, _ = select.select([fd], [], [], 0.1)
                if ready and not os.read(fd, 65536):
                    return
            except OSError:
                return

    def type_keys():
        while True:
            try:
                data = os.read(sys.stdin.fileno(), 1024)
            except OSError:
                return
            if not data:
                return
            os.write(fd, data)

    threading.Thread(target=drain, daemon=True).start()
    threading.Thread(target=type_keys, daemon=True).start()
    signal.signal(signal.SIGUSR1, lambda *_: os.write(fd, FOCUS_OUT))
    signal.signal(signal.SIGUSR2, lambda *_: os.write(fd, FOCUS_IN))
    done = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: done.set())
    done.wait()
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
