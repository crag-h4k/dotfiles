# tests/caveman-launchd-smoke.py
"""Exercise the deployed Caveman launchd user-agent on a disposable route."""

from __future__ import annotations

import json
import os
from pathlib import Path
import platform
import shutil
import socket
import subprocess
import time


LABEL = "io.github.crag-h4k.dotfiles.caveman"


def free_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def configure_record_route(private: Path, port: int) -> None:
    settings = private / "settings.json"
    value = json.loads(settings.read_text())
    value.update({
        "listen": f"127.0.0.1:{port}",
        "url": f"http://127.0.0.1:{port}",
        "mode": "record",
        "enabled": False,
    })
    settings.write_text(json.dumps(value, indent=2) + "\n")
    settings.chmod(0o600)


def main() -> None:
    if platform.system() != "Darwin":
        raise RuntimeError("Caveman launchd smoke must run on macOS")
    if os.getuid() == 0:
        raise RuntimeError("Caveman launchd smoke must run as a user")

    home = Path.home()
    controller = home / ".local/bin/cavemanctl"
    private = home / ".caveman/oc2"
    if not controller.is_file() or not os.access(controller, os.X_OK):
        raise RuntimeError("managed cavemanctl is missing")
    if private.exists():
        raise RuntimeError("Caveman launchd smoke requires a fresh CI home")

    initialized = False
    try:
        port = free_port()
        url = f"http://127.0.0.1:{port}"
        subprocess.run([
            str(controller), "init", "--provider", "fixture", "--upstream", "https://example.invalid",
            "--listen", f"127.0.0.1:{port}", "--url", url,
        ], check=True, timeout=30)
        initialized = True
        for attempt in range(3):
            port = free_port()
            configure_record_route(private, port)
            try:
                subprocess.run([str(controller), "enable"], check=True, timeout=45)
                status = subprocess.run([str(controller), "status"], check=True, capture_output=True, text=True, timeout=15)
                report = json.loads(status.stdout)
                if report != {"enabled": True, "ready": True, "mode": "record", "provider": "fixture", "backend": "native"}:
                    raise RuntimeError("Caveman launchd route did not report the expected ready state")
                break
            except (subprocess.CalledProcessError, RuntimeError):
                subprocess.run([str(controller), "disable"], check=False, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=15)
                subprocess.run([str(controller), "stop"], check=False, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=30)
                if attempt == 2:
                    raise
        subprocess.run([str(controller), "disable"], check=True, timeout=15)
        subprocess.run([str(controller), "stop"], check=True, timeout=30)
    finally:
        if initialized:
            subprocess.run([str(controller), "disable"], check=False, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=15)
            subprocess.run([str(controller), "stop"], check=False, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=30)
            subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}",
                            str(home / "Library/LaunchAgents" / (LABEL + ".plist"))],
                           check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            shutil.rmtree(home / ".caveman")
    print("Caveman launchd smoke: user agent readiness and clean shutdown passed")


if __name__ == "__main__":
    main()
