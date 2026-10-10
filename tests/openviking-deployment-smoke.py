# tests/openviking-deployment-smoke.py
"""Exercise the installed native runtime with disposable private state."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def main():
    home = Path.home()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--controller", type=Path, default=home / ".local/bin/openvikingctl")
    parser.add_argument("--assets", type=Path, default=home / ".local/share/dotfiles/openviking")
    parser.add_argument("--runtime", type=Path)
    args = parser.parse_args()
    root = args.runtime
    if root is None:
        root = Path(json.loads((home / ".openviking/runtime.json").read_text())["install_root"])
    if not (root / "current/bin/python").is_file():
        raise ValueError("installed OpenViking runtime is missing")

    with tempfile.TemporaryDirectory(prefix="openviking-smoke-") as directory:
        temporary = Path(directory)
        examples = temporary / ".local/share/dotfiles/openviking"
        examples.mkdir(parents=True)
        for source in args.assets.iterdir():
            if source.is_file():
                shutil.copyfile(source, examples / source.name.removeprefix("readonly_"))
        private = temporary / ".openviking"
        private.mkdir(mode=0o700)
        config = json.loads((examples / "ollama.json").read_text())
        config["server"]["root_api_key"] = secrets.token_urlsafe(32)
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        config["server"]["port"] = port
        path = private / "ov.conf"
        path.write_text(json.dumps(config))
        path.chmod(0o600)
        env = dict(os.environ, HOME=str(temporary), XDG_CONFIG_HOME=str(temporary / ".config"),
                   OPENVIKING_INSTALL_ROOT=str(root.resolve()), PYTHONPATH="")
        env.pop("OPENVIKING_CONFIG_FILE", None)
        controller = [str(args.controller.resolve())]
        snapshot = temporary / "codex-snapshot"
        rollout = snapshot / "2026/01/01/rollout-smoke.jsonl"
        rollout.parent.mkdir(parents=True)
        records = [
            {"type": "session_meta", "payload": {"id": "smoke", "timestamp": "2026-01-01T00:00:00Z"}},
            {"type": "response_item", "payload": {"type": "message", "role": "user",
                                                 "content": [{"type": "input_text", "text": "fixture"}]}},
        ]
        rollout.write_text("".join(json.dumps(record) + "\n" for record in records))
        preview = subprocess.run([*controller, "import-codex", "--source", str(snapshot), "--name", "smoke"],
                                 env=env, check=True, capture_output=True, text=True, timeout=30)
        if json.loads(preview.stdout)["messages"] != 1 or (private / "imports").exists():
            raise ValueError("Codex preview failed or unexpectedly wrote import state")
        subprocess.run([str(root / "current/bin/python"), "-B", "-m", "unittest", "tests.test_openviking_import"],
                       env=env, cwd=Path(__file__).resolve().parents[1], check=True, timeout=120)
        subprocess.run([*controller, "init", "--profile", "ollama"], env=env, check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        url = "http://127.0.0.1:" + str(port)
        with (temporary / "server.log").open("w") as log:
            process = subprocess.Popen([*controller, "run"], env=env, cwd=temporary, stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 60
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise ValueError("native server exited before readiness")
                    try:
                        with urllib.request.urlopen(url + "/ready", timeout=2) as response:
                            if response.status == 200:
                                break
                    except OSError:
                        pass
                    time.sleep(0.2)
                else:
                    raise ValueError("native server did not become ready")
                route = url + "/api/v1/fs/ls?uri=viking%3A%2F%2F"
                try:
                    urllib.request.urlopen(route, timeout=10)
                except urllib.error.HTTPError as error:
                    if error.code != 401:
                        raise ValueError("unauthenticated data access was not rejected with HTTP 401") from error
                else:
                    raise ValueError("unauthenticated data access unexpectedly succeeded")
                subprocess.run([*controller, "bootstrap-client"], env=env, check=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
                client = json.loads((private / "ovcli.conf").read_text())
                if client["api_key"] == config["server"]["root_api_key"]:
                    raise ValueError("agent was given the ROOT credential")
                request = urllib.request.Request(route, headers={"Authorization": "Bearer " + client["api_key"]})
                with urllib.request.urlopen(request, timeout=10) as response:
                    if json.load(response)["status"] != "ok":
                        raise ValueError("authenticated USER data access failed")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        print("OpenViking native runtime smoke passed: loopback readiness, API-key enforcement, and USER access")


if __name__ == "__main__":
    main()
