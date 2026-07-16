#!/usr/bin/env python3
# ~/.claude/statusline-tokens.py
# Detached background updater for the gud Claude statusline. Walks the main
# transcript plus every subagents/agent-*.jsonl beside it, dedups messages by
# message.id (fallback line uuid), and sums input+output+cache_creation+cache_read
# per deduped message. Writes the subagent-inclusive cumulative total to
# <cachedir>/<sid>.total (a single integer). The render path reads only that file,
# so this cold start never touches render latency.
#
# Incremental: <cachedir>/<sid>.state remembers each source file's byte offset,
# size, mtime, and the running id->tokens map, so each run parses only new lines.
# Truncated files re-read from 0; new agent files full-read once. Lock is an atomic
# mkdir directory (macOS has no flock); a stale lock (updater crashed) is stolen.
#
# Usage: statusline-tokens.py <session_id> <transcript_path> <cache_dir>
import atexit
import glob
import json
import os
import shutil
import sys
import time

STALE_LOCK_SECS = 30


def load_state(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            st = json.load(f)
        if isinstance(st, dict) and "files" in st and "ids" in st:
            return st
    except Exception:
        pass
    return {"files": {}, "ids": {}}


def add_usage(obj, ids):
    """Record one transcript line's token usage into the dedup map."""
    msg = obj.get("message")
    if not isinstance(msg, dict):
        return
    u = msg.get("usage")
    if not isinstance(u, dict):
        return
    mid = msg.get("id") or obj.get("uuid")
    if not mid:
        return

    def g(k):
        v = u.get(k, 0)
        return v if isinstance(v, int) else 0

    ids[mid] = (
        g("input_tokens")
        + g("output_tokens")
        + g("cache_creation_input_tokens")
        + g("cache_read_input_tokens")
    )


def process_file(path, files, ids):
    """Incrementally read `path` from its cached byte offset; update files+ids."""
    try:
        size = os.path.getsize(path)
        mtime = os.path.getmtime(path)
    except OSError:
        return  # vanished; keep whatever we already summed for it
    prev = files.get(path)
    off = 0
    if prev:
        if prev.get("size") == size and prev.get("mtime") == mtime:
            return  # unchanged
        off = prev.get("off", 0)
        if size < off:  # truncated / rotated
            off = 0
    try:
        with open(path, "rb") as f:
            f.seek(off)
            data = f.read()
    except OSError:
        return
    if data.endswith(b"\n"):
        complete = data.split(b"\n")[:-1]
        partial_len = 0
    else:
        parts = data.split(b"\n")
        complete = parts[:-1]
        partial_len = len(parts[-1])
    for raw in complete:
        if not raw.strip():
            continue
        try:
            obj = json.loads(raw)
        except Exception:
            continue
        if isinstance(obj, dict):
            add_usage(obj, ids)
    files[path] = {"off": off + (len(data) - partial_len), "size": size, "mtime": mtime}


def main():
    if len(sys.argv) < 4:
        return 0
    sid, tpath, cachedir = sys.argv[1], sys.argv[2], sys.argv[3]
    try:
        os.makedirs(cachedir, exist_ok=True)
    except OSError:
        return 0

    # Atomic mkdir lock; steal a stale one (a crashed prior updater).
    lockdir = os.path.join(cachedir, sid + ".lock")
    try:
        os.mkdir(lockdir)
    except FileExistsError:
        try:
            age = time.time() - os.path.getmtime(lockdir)
        except OSError:
            age = STALE_LOCK_SECS + 1
        if age < STALE_LOCK_SECS:
            return 0
        shutil.rmtree(lockdir, ignore_errors=True)
        try:
            os.mkdir(lockdir)
        except OSError:
            return 0
    except OSError:
        return 0
    atexit.register(lambda: shutil.rmtree(lockdir, ignore_errors=True))

    statefile = os.path.join(cachedir, sid + ".state")
    st = load_state(statefile)
    files, ids = st["files"], st["ids"]

    sources = [tpath]
    base = tpath[:-6] if tpath.endswith(".jsonl") else tpath
    sources.extend(sorted(glob.glob(os.path.join(base, "subagents", "agent-*.jsonl"))))
    for src in sources:
        process_file(src, files, ids)

    total = sum(v for v in ids.values() if isinstance(v, int))

    tmp = os.path.join(cachedir, sid + ".total.tmp")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(str(total) + "\n")
        os.replace(tmp, os.path.join(cachedir, sid + ".total"))
    except OSError:
        pass
    try:
        with open(statefile, "w", encoding="utf-8") as f:
            json.dump({"files": files, "ids": ids}, f)
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
