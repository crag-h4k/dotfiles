"""Run independent runtime groups, keeping shared-prefix npm installs serial."""

from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading


def main():
    jobs = int(os.environ.get("DOTFILES_RUNTIME_JOBS", "3"))
    if not 1 <= jobs <= 3:
        raise ValueError("DOTFILES_RUNTIME_JOBS must be between 1 and 3")
    prefix = Path(os.environ.get("OPENCODE2_NPM_PREFIX", str(Path.home() / ".local/share/opencode2")))
    if prefix.expanduser().resolve() == (Path.home() / ".local").resolve():
        jobs = 1
    groups = []
    if os.environ.get("INSTALL_AI_OPENCODE") == "true":
        groups.append("opencode")
    if any(os.environ.get(key) == "true" for key in ("INSTALL_AI_OPENCODE", "INSTALL_AI_COPILOT")):
        groups.append("shared-npm")
    if os.environ.get("INSTALL_AI_OPENVIKING") == "true":
        groups.append("openviking")

    processes = []
    lock = threading.Lock()
    output_lock = threading.Lock()
    stopped = threading.Event()
    worker = Path(__file__).with_name("install-ai-runtime-group.sh")

    def interrupt(signum, _frame):
        raise InterruptedError(signum)

    signal.signal(signal.SIGTERM, interrupt)

    with tempfile.TemporaryDirectory(prefix="dotfiles-runtimes-") as directory:
        def install(group):
            result = Path(directory) / group
            with lock:
                if stopped.is_set():
                    return (0, 1, 0)
                proc = subprocess.Popen(
                    ["bash", str(worker), group, str(result)],
                    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, errors="replace", start_new_session=True,
                )
                processes.append(proc)
            with proc.stdout:
                for line in proc.stdout:
                    with output_lock:
                        print(f"[{group}] {line.rstrip()}", flush=True)
            status = proc.wait()
            with lock:
                processes.remove(proc)
            if status != 0 or not result.exists():
                print(f"WARN: {group} exited without a complete result (exit={status})", flush=True)
                return (0, 1, 0)
            counts = tuple(int(value) for value in result.read_text().split())
            if len(counts) != 3 or any(value < 0 for value in counts):
                raise ValueError(f"invalid package result from {group}")
            return counts

        executor = ThreadPoolExecutor(max_workers=jobs)
        try:
            futures = [executor.submit(install, group) for group in groups]
            counts = [future.result() for future in futures]
        except BaseException:
            stopped.set()
            # Each group owns its process group, including npm and verification children.
            with lock:
                for proc in processes:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
            raise
        finally:
            executor.shutdown(wait=True, cancel_futures=True)

    totals = [sum(count[index] for count in counts) for index in range(3)]
    Path(sys.argv[1]).write_text(" ".join(map(str, totals)) + "\n")
    return int(totals[1] != 0)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, InterruptedError):
        sys.exit(130)
