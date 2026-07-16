# tests/test_statusline_tokens.py
"""Tests for dot_claude/executable_statusline-tokens.py (the detached token walker).

The source is loaded by file path with importlib (its name carries a hyphen and the
chezmoi `executable_` prefix, so it cannot be imported as a normal module). It is
importable as-is: the logic already lives in load_state / add_usage / process_file /
main behind an `if __name__ == "__main__"` guard, so no refactor was needed.

main() takes a stale-lock (atomic mkdir) that is only released via atexit, which does
not fire between in-process calls. run_main() therefore removes the lock dir after
each call, emulating the process exit that a real detached run would give.
"""
import importlib.util
import json
import shutil
import sys
from pathlib import Path

SRC = Path(__file__).parent.parent / "dot_claude" / "executable_statusline-tokens.py"
FIXTURES = Path(__file__).parent / "fixtures" / "statusline"


def _load():
    spec = importlib.util.spec_from_file_location("statusline_tokens", SRC)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


mod = _load()


# --- builders --------------------------------------------------------------
def line(mid=None, uuid=None, inp=0, out=0, cc=0, cr=0):
    """A transcript line with a full usage block; total = inp+out+cc+cr."""
    msg = {
        "usage": {
            "input_tokens": inp,
            "output_tokens": out,
            "cache_creation_input_tokens": cc,
            "cache_read_input_tokens": cr,
        }
    }
    if mid is not None:
        msg["id"] = mid
    obj = {"message": msg}
    if uuid is not None:
        obj["uuid"] = uuid
    return json.dumps(obj)


def write_lines(path, lines, trailing_newline=True):
    text = "\n".join(lines)
    if trailing_newline and lines:
        text += "\n"
    Path(path).write_text(text, encoding="utf-8")


def append_lines(path, lines):
    with open(path, "a", encoding="utf-8") as f:
        for ln in lines:
            f.write(ln + "\n")


def run_main(sid, tpath, cachedir):
    """Invoke main() with a fabricated argv, then release the lock as exit would."""
    argv = ["statusline-tokens.py", sid, str(tpath), str(cachedir)]
    old = sys.argv
    sys.argv = argv
    try:
        return mod.main()
    finally:
        sys.argv = old
        shutil.rmtree(Path(cachedir) / (sid + ".lock"), ignore_errors=True)


def read_total(cachedir, sid):
    return int(Path(cachedir, sid + ".total").read_text(encoding="utf-8").strip())


def read_state(cachedir, sid):
    return json.loads(Path(cachedir, sid + ".state").read_text(encoding="utf-8"))


# --- total math ------------------------------------------------------------
def test_total_sums_all_four_usage_fields():
    ids = {}
    mod.add_usage(json.loads(line(mid="m", inp=1, out=2, cc=4, cr=8)), ids)
    assert ids["m"] == 15


def test_main_total_is_sum_across_messages(tmp_path):
    tpath = tmp_path / "t.jsonl"
    cachedir = tmp_path / "cache"
    write_lines(tpath, [line(mid="a", inp=100, cr=50), line(mid="b", out=25)])
    run_main("s", tpath, cachedir)
    assert read_total(cachedir, "s") == 175


# --- dedup by message.id ---------------------------------------------------
def test_dedup_last_seen_usage_wins(tmp_path):
    tpath = tmp_path / "t.jsonl"
    cachedir = tmp_path / "cache"
    # Two lines share id "m1": counted once, last value (250) wins.
    write_lines(
        tpath,
        [line(mid="m1", inp=100), line(mid="m1", inp=250), line(mid="m2", inp=50)],
    )
    run_main("s", tpath, cachedir)
    # 250 (m1, last-seen) + 50 (m2) = 300, NOT 100+250+50.
    assert read_total(cachedir, "s") == 300


def test_add_usage_falls_back_to_uuid_when_no_message_id():
    ids = {}
    mod.add_usage(json.loads(line(uuid="u-1", inp=7)), ids)
    assert ids["u-1"] == 7


# --- subagent inclusion ----------------------------------------------------
def test_subagents_folded_into_total(tmp_path):
    tpath = tmp_path / "conv.jsonl"
    cachedir = tmp_path / "cache"
    subdir = tmp_path / "conv" / "subagents"
    subdir.mkdir(parents=True)
    write_lines(tpath, [line(mid="main", inp=100)])
    write_lines(subdir / "agent-1.jsonl", [line(mid="a1", inp=40)])
    write_lines(subdir / "agent-2.jsonl", [line(mid="a2", inp=10)])
    run_main("s", tpath, cachedir)
    assert read_total(cachedir, "s") == 150


def test_fixture_transcript_plus_subagents(tmp_path):
    # Fixture: transcript 220 (main-1 200 + main-2 20; blank + broken lines
    # skipped) + agent-1 40 + agent-2 10 = 270.
    cachedir = tmp_path / "cache"
    run_main("fx", FIXTURES / "transcript.jsonl", cachedir)
    assert read_total(cachedir, "fx") == 270


# --- incremental tail-read -------------------------------------------------
def test_incremental_offset_reads_only_new_lines(tmp_path):
    tpath = tmp_path / "t.jsonl"
    cachedir = tmp_path / "cache"
    write_lines(tpath, [line(mid="m1", inp=100)])
    run_main("s", tpath, cachedir)
    assert read_total(cachedir, "s") == 100

    # Tamper the persisted dedup value for the already-read line. If run 2 re-read
    # line 1 (which sits before the saved offset) it would reset m1 to 100 and the
    # sentinel would vanish. It must not: only the appended line is parsed.
    st = read_state(cachedir, "s")
    st["ids"]["m1"] = 777
    Path(cachedir, "s.state").write_text(json.dumps(st), encoding="utf-8")

    append_lines(tpath, [line(mid="m2", inp=50)])
    run_main("s", tpath, cachedir)
    assert read_total(cachedir, "s") == 827  # 777 (untouched) + 50 (new)


def test_truncation_rereads_from_zero(tmp_path):
    tpath = tmp_path / "t.jsonl"
    cachedir = tmp_path / "cache"
    # A long first line so its byte offset exceeds the rotated file's size.
    write_lines(tpath, [line(mid="long", inp=100000000)])
    run_main("s", tpath, cachedir)
    assert read_total(cachedir, "s") == 100000000

    # Rotate: replace with a much shorter file (size < saved offset). The updater
    # must detect the shrink, reset the offset to 0, and read the new line.
    write_lines(tpath, [line(mid="fresh", inp=5)])
    run_main("s", tpath, cachedir)
    total = read_total(cachedir, "s")
    # "fresh" (5) is read from offset 0; the stale "long" id survives in the map
    # (truncation does not clear it), so the total is 100000000 + 5, and crucially
    # it is NOT still 100000000 (which is what a seek past EOF would leave).
    assert total == 100000005


def test_new_agent_file_picked_up_on_later_run(tmp_path):
    tpath = tmp_path / "conv.jsonl"
    cachedir = tmp_path / "cache"
    write_lines(tpath, [line(mid="main", inp=100)])
    run_main("s", tpath, cachedir)
    assert read_total(cachedir, "s") == 100

    subdir = tmp_path / "conv" / "subagents"
    subdir.mkdir(parents=True)
    write_lines(subdir / "agent-1.jsonl", [line(mid="a1", inp=40)])
    run_main("s", tpath, cachedir)
    assert read_total(cachedir, "s") == 140


# --- cache files -----------------------------------------------------------
def test_cold_run_writes_total_and_state(tmp_path):
    tpath = tmp_path / "t.jsonl"
    cachedir = tmp_path / "cache"
    write_lines(tpath, [line(mid="m1", inp=30), line(mid="m2", inp=12)])
    run_main("s", tpath, cachedir)

    # .total is a single integer with a trailing newline.
    total_raw = Path(cachedir, "s.total").read_text(encoding="utf-8")
    assert total_raw == "42\n"

    # .state carries the per-file offsets and the dedup id->tokens map.
    st = read_state(cachedir, "s")
    assert set(st) == {"files", "ids"}
    assert st["ids"] == {"m1": 30, "m2": 12}
    entry = st["files"][str(tpath)]
    assert entry["off"] == tpath.stat().st_size
    assert entry["size"] == tpath.stat().st_size
    assert "mtime" in entry


def test_load_state_defaults_when_missing(tmp_path):
    st = mod.load_state(str(tmp_path / "nope.state"))
    assert st == {"files": {}, "ids": {}}


# --- defensiveness ---------------------------------------------------------
def test_missing_usage_fields_default_to_zero():
    ids = {}
    obj = {"message": {"id": "m", "usage": {"input_tokens": 10}}}
    mod.add_usage(obj, ids)
    assert ids["m"] == 10  # the three absent fields contribute 0


def test_non_int_usage_values_are_ignored():
    ids = {}
    obj = {
        "message": {
            "id": "m",
            "usage": {"input_tokens": "5", "output_tokens": None, "cache_read_input_tokens": 3},
        }
    }
    mod.add_usage(obj, ids)
    assert ids["m"] == 3  # only the genuine int counts


def test_add_usage_ignores_malformed_shapes():
    ids = {}
    mod.add_usage({"message": "not-a-dict"}, ids)
    mod.add_usage({"message": {"id": "m"}}, ids)  # no usage
    mod.add_usage({"message": {"usage": {"input_tokens": 1}}}, ids)  # no id/uuid
    assert ids == {}


def test_partial_trailing_line_deferred_until_completed(tmp_path):
    tpath = tmp_path / "t.jsonl"
    cachedir = tmp_path / "cache"
    # Complete first line + a partial second line with NO trailing newline.
    Path(tpath).write_text(line(mid="a", inp=10) + "\n" + line(mid="b", inp=20), encoding="utf-8")
    run_main("s", tpath, cachedir)
    assert read_total(cachedir, "s") == 10  # partial "b" not counted yet

    # Terminating the partial line completes it on the next run.
    with open(tpath, "a", encoding="utf-8") as f:
        f.write("\n")
    run_main("s", tpath, cachedir)
    assert read_total(cachedir, "s") == 30


def test_empty_file_totals_zero(tmp_path):
    tpath = tmp_path / "t.jsonl"
    cachedir = tmp_path / "cache"
    Path(tpath).write_text("", encoding="utf-8")
    run_main("s", tpath, cachedir)
    assert read_total(cachedir, "s") == 0


def test_malformed_lines_skipped_valid_lines_counted(tmp_path):
    tpath = tmp_path / "t.jsonl"
    cachedir = tmp_path / "cache"
    write_lines(
        tpath,
        ["{ broken", "", line(mid="ok", inp=15), "also not json"],
    )
    run_main("s", tpath, cachedir)
    assert read_total(cachedir, "s") == 15
