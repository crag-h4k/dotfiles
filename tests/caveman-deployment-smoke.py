# tests/caveman-deployment-smoke.py
"""Exercise installed compression/recovery and proxy startup with isolated state."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def main():
    binaries = Path.home() / ".caveman/bin"
    for name in ("caveman-proxy", "caveman-engine", "caveman-mcp"):
        if not os.access(binaries / name, os.X_OK):
            raise RuntimeError("missing installed Caveman binary: " + name)
    with tempfile.TemporaryDirectory(prefix="caveman-smoke-") as temporary:
        root = Path(temporary)
        env = {**os.environ, "CAVEMAN_HOME": str(root), "CAVEMAN_CCR_DB": str(root / "ccr.db"),
               "CAVEMAN_CONFIG": str(root / "proxy.json"), "DO_NOT_TRACK": "1"}
        for key in ("CAVEMAN_MODE", "CAVEMAN_LISTEN", "CAVEMAN_AUTH_TOKEN", "CAVEMAN_DB"):
            env.pop(key, None)
        content = b"INFO worker=fixture status=ok\n" * 300 + b"ERROR code=fixture-913 retries=3\n"
        result = subprocess.run([str(binaries / "caveman-engine"), "compress"], input=content,
                                env=env, check=True, capture_output=True)
        report = json.loads(result.stderr)
        if report["tokens_after"] >= report["tokens_before"] or b"fixture-913" not in result.stdout:
            raise RuntimeError("synthetic log compression failed")
        restored = subprocess.check_output([str(binaries / "caveman-engine"), "retrieve", report["recovery_handle"]], env=env)
        if restored != content:
            raise RuntimeError("Caveman recovery changed the original bytes")
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        (root / "proxy.json").write_text(json.dumps({"mode": "record", "listen": f"127.0.0.1:{port}"}))
        with (root / "proxy.log").open("wb") as log:
            process = subprocess.Popen([str(binaries / "caveman-proxy"), "serve"], env=env,
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 20
                while True:
                    if process.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError("installed Caveman proxy failed readiness")
                    try:
                        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health/ready", timeout=1) as response:
                            if response.status == 200:
                                break
                    except urllib.error.URLError:
                        time.sleep(0.1)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    print("Caveman deployment smoke: compression, byte-exact recovery, and proxy readiness passed")


if __name__ == "__main__":
    main()
