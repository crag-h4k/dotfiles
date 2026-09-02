#!/usr/bin/env python3
# ~/.claude/statusline-tokens.py
# Detached background updater for the Claude dotfiles statusline. Walks the main
# transcript plus every subagents/agent-*.jsonl beside it, dedups messages by
# message.id (fallback line uuid), and sums input+output+cache_creation+cache_read
# per deduped message. Writes the subagent-inclusive cumulative total to
# <cachedir>/<sid>.total (a single integer) and the subagent-inclusive cumulative
# USD cost to <cachedir>/<sid>.cost (a formatted string, no glyph). The render
# path reads only those files, so this cold start never touches render latency.
#
# Cost is priced per deduped message from message.model against PRICING_PER_MTOK
# (USD/MTok, hardcoded from https://platform.claude.com/docs/en/about-claude/pricing
# since Claude Code does not expose a subagent-inclusive cost anywhere - its own
# stdin cost.total_cost_usd covers only the orchestrator session). Cache writes
# split by TTL tier (message.usage.cache_creation.ephemeral_5m/1h_input_tokens)
# since the 5m and 1h rates differ; an unrecognized or missing model prices at $0
# rather than skew the total.
#
# Incremental: <cachedir>/<sid>.state remembers each source file's byte offset,
# size, mtime, and the running id->tokens/id->cost maps, so each run parses only
# new lines. Truncated files re-read from 0; new agent files full-read once. Lock
# is an atomic mkdir directory (macOS has no flock); a stale lock (updater
# crashed) is stolen.
#
# Usage: statusline-tokens.py <session_id> <transcript_path> <cache_dir>
import atexit
import glob
import json
import os
import re
import shutil
import sys
import time

STALE_LOCK_SECS = 30

# USD per million tokens, current as of 2026-09-02. cache_5m/cache_1h are cache
# *write* rates (1.25x/2x base input); cache_read is the cache *hit* rate (0.1x
# base input, except Fable/Mythos 5.1 at 0.025x). Keyed by the dateless model id;
# a trailing -YYYYMMDD snapshot suffix (pre-4.6-generation models) is stripped
# before lookup, so e.g. claude-sonnet-4-5-20250929 resolves to claude-sonnet-4-5.
PRICING_PER_MTOK = {
    "claude-fable-5-1":  {"input": 10.00, "output": 50.00, "cache_5m": 12.50, "cache_1h": 20.00, "cache_read": 0.25},
    "claude-mythos-5-1": {"input": 10.00, "output": 50.00, "cache_5m": 12.50, "cache_1h": 20.00, "cache_read": 0.25},
    "claude-fable-5":    {"input": 10.00, "output": 50.00, "cache_5m": 12.50, "cache_1h": 20.00, "cache_read": 1.00},
    "claude-mythos-5":   {"input": 10.00, "output": 50.00, "cache_5m": 12.50, "cache_1h": 20.00, "cache_read": 1.00},
    "claude-opus-5":     {"input": 5.00,  "output": 25.00, "cache_5m": 6.25,  "cache_1h": 10.00, "cache_read": 0.50},
    "claude-opus-4-8":   {"input": 5.00,  "output": 25.00, "cache_5m": 6.25,  "cache_1h": 10.00, "cache_read": 0.50},
    "claude-opus-4-7":   {"input": 5.00,  "output": 25.00, "cache_5m": 6.25,  "cache_1h": 10.00, "cache_read": 0.50},
    "claude-opus-4-6":   {"input": 5.00,  "output": 25.00, "cache_5m": 6.25,  "cache_1h": 10.00, "cache_read": 0.50},
    "claude-opus-4-5":   {"input": 5.00,  "output": 25.00, "cache_5m": 6.25,  "cache_1h": 10.00, "cache_read": 0.50},
    "claude-sonnet-5":   {"input": 2.00,  "output": 10.00, "cache_5m": 2.50,  "cache_1h": 4.00,  "cache_read": 0.20},
    "claude-sonnet-4-6": {"input": 3.00,  "output": 15.00, "cache_5m": 3.75,  "cache_1h": 6.00,  "cache_read": 0.30},
    "claude-sonnet-4-5": {"input": 3.00,  "output": 15.00, "cache_5m": 3.75,  "cache_1h": 6.00,  "cache_read": 0.30},
    "claude-haiku-4-5":  {"input": 1.00,  "output": 5.00,  "cache_5m": 1.25,  "cache_1h": 2.00,  "cache_read": 0.10},
    "claude-haiku-3-5":  {"input": 0.80,  "output": 4.00,  "cache_5m": 1.00,  "cache_1h": 1.60,  "cache_read": 0.08},
}
_SNAPSHOT_SUFFIX_RE = re.compile(r"-\d{8}$")


def _price_for(model):
    """Per-MTok price row for a transcript model id, or None if unrecognized."""
    if not isinstance(model, str) or not model:
        return None
    return PRICING_PER_MTOK.get(_SNAPSHOT_SUFFIX_RE.sub("", model))


def fmt_cost(v):
    """0.00 / 0.0034 (sub-cent gets extra precision) / 1.23 - no '$' prefix; the
    renderer pairs this with its own dollar glyph, same as the bare Sigma total."""
    if v <= 0:
        return "0.00"
    if v < 0.01:
        return f"{v:.4f}"
    return f"{v:.2f}"


def load_state(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            st = json.load(f)
        if isinstance(st, dict) and "files" in st and "ids" in st:
            st.setdefault("costs", {})
            return st
    except Exception:
        pass
    return {"files": {}, "ids": {}, "costs": {}}


def add_usage(obj, ids, costs):
    """Record one transcript line's token usage + USD cost into the dedup maps."""
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

    price = _price_for(msg.get("model"))
    if price is None:
        costs[mid] = 0.0
        return

    cc = u.get("cache_creation")
    if isinstance(cc, dict):
        w5m = cc.get("ephemeral_5m_input_tokens", 0)
        w1h = cc.get("ephemeral_1h_input_tokens", 0)
        w5m = w5m if isinstance(w5m, int) else 0
        w1h = w1h if isinstance(w1h, int) else 0
    else:
        # No TTL split available: price the whole write at the cheaper 5m tier
        # rather than drop it (it's an approximation, not a skip).
        w5m, w1h = g("cache_creation_input_tokens"), 0

    costs[mid] = (
        g("input_tokens") * price["input"]
        + g("output_tokens") * price["output"]
        + w5m * price["cache_5m"]
        + w1h * price["cache_1h"]
        + g("cache_read_input_tokens") * price["cache_read"]
    ) / 1_000_000.0


def process_file(path, files, ids, costs):
    """Incrementally read `path` from its cached byte offset; update files+ids+costs."""
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
            add_usage(obj, ids, costs)
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
    files, ids, costs = st["files"], st["ids"], st["costs"]

    sources = [tpath]
    base = tpath[:-6] if tpath.endswith(".jsonl") else tpath
    sources.extend(sorted(glob.glob(os.path.join(base, "subagents", "agent-*.jsonl"))))
    for src in sources:
        process_file(src, files, ids, costs)

    total = sum(v for v in ids.values() if isinstance(v, int))
    total_cost = sum(v for v in costs.values() if isinstance(v, (int, float)))

    tmp = os.path.join(cachedir, sid + ".total.tmp")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(str(total) + "\n")
        os.replace(tmp, os.path.join(cachedir, sid + ".total"))
    except OSError:
        pass
    cost_tmp = os.path.join(cachedir, sid + ".cost.tmp")
    try:
        with open(cost_tmp, "w", encoding="utf-8") as f:
            f.write(fmt_cost(total_cost) + "\n")
        os.replace(cost_tmp, os.path.join(cachedir, sid + ".cost"))
    except OSError:
        pass
    try:
        with open(statefile, "w", encoding="utf-8") as f:
            json.dump({"files": files, "ids": ids, "costs": costs}, f)
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
