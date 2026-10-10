"""Import a reviewed Codex log snapshot with OpenViking's native replay pipeline."""
import argparse
import asyncio
from datetime import date
import hashlib
import json
import logging
import os
from pathlib import Path
import re
import tempfile
import time
import urllib.parse


def read_private(path):
    info = path.lstat()
    if path.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("import configuration and state must be owned by you, private, and not symlinked")
    return json.loads(path.read_text())


def save(path, value):
    fd, temporary = tempfile.mkstemp(prefix=".import-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def validate_rollout(path):
    with path.open("rb") as stream:
        for line in stream:
            if not line.endswith(b"\n"):
                raise ValueError("snapshot has an incomplete final record; finish copying it before importing")
            if line.strip():
                try:
                    record = json.loads(line)
                except ValueError:
                    raise ValueError("snapshot contains malformed JSON; review it before importing") from None
                if not isinstance(record, dict):
                    raise ValueError("snapshot contains a non-object JSON record")


def source_for(root):
    from openviking.ingest.sources.codex import CodexSource
    from openviking_cli.utils.config.ingest_config import IngestHarnessConfig

    class ImportedCodex(CodexSource):
        def user_peer(self, **kwargs):
            # A historical cwd may name a different repository on this machine.
            # Import human facts into the authenticated user's space, without a peer.
            return None

    return ImportedCodex(IngestHarnessConfig(paths=[str(root)]))


def inventory(source, state, since=None, limit=None, sessions=None):
    if state.get("invalid"):
        raise ValueError("import state is invalid; inspect the server and restore matching state before recovery")
    refs = list(source.discover_sessions())
    if not refs:
        raise ValueError("no Codex rollout logs found under YEAR/MONTH/DAY")
    snapshot = {}
    requested = set(sessions or [])
    if requested - {ref.native_session_id for ref in refs}:
        raise ValueError("a requested session is absent from the snapshot")
    for ref in refs:
        sid = ref.native_session_id
        if sid in snapshot:
            raise ValueError("duplicate Codex session id; review the snapshot before importing")
        path = Path(ref.locator)
        if path.is_symlink():
            raise ValueError("rollout files must be regular files, not symlinks")
        validate_rollout(path)
        fingerprint = digest(path)
        snapshot[sid] = {"path": str(path), "sha256": fingerprint}
    if "snapshot" in state:
        if snapshot != state["snapshot"]:
            raise ValueError("reviewed snapshot changed, added, or lost files; restore the bound snapshot before resuming")
    elif state.get("files"):
        raise ValueError("legacy progress has no complete snapshot manifest; explicit state recovery is required")
    else:
        state["snapshot"] = snapshot
    selected = []
    complete = 0
    for ref in refs:
        sid = ref.native_session_id
        if requested and sid not in requested:
            continue
        if since and (not ref.started_at or ref.started_at < since):
            continue
        expected = snapshot[sid]
        previous = state.get("files", {}).get(sid, {})
        if previous and any(previous[key] != expected[key] for key in ("sha256", "path")):
            raise ValueError("a previously imported rollout changed; retain the original snapshot and state")
        if previous.get("complete"):
            complete += 1
            continue
        if limit is None or len(selected) < limit:
            selected.append((ref, expected["sha256"]))
    return selected, complete


def count_messages(source, ref):
    count = characters = 0
    cursor = None
    while True:
        messages, advanced = source.read_messages(ref, cursor)
        count += len(messages)
        characters += sum(len(message.text or "") for message in messages)
        if advanced == cursor:
            break
        cursor = advanced
    return count, characters


def target_config(path, url=None):
    config = read_private(path)
    endpoint = (url or config.get("url", "")).rstrip("/")
    parsed = urllib.parse.urlparse(endpoint)
    if (parsed.scheme not in ("http", "https") or not parsed.hostname or
            parsed.username or parsed.password or parsed.query or parsed.fragment):
        raise ValueError("client URL must be HTTP(S), without credentials, query, or fragment")
    if parsed.scheme == "http" and parsed.hostname not in ("127.0.0.1", "localhost", "::1"):
        raise ValueError("use HTTPS for remote imports, or --url with a loopback endpoint")
    key = config.get("api_key")
    if not isinstance(key, str) or not key or "${" in key:
        raise ValueError("a private authenticated USER client configuration is required")
    if config.get("auth_mode") not in (None, "api_key") or any(
        config.get(name) for name in ("extra_headers", "extra_header", "gateway_token")
    ):
        raise ValueError("imports require a dedicated API-key client config without extra authentication headers")
    timeout = config.get("timeout", 180)
    if type(timeout) not in (int, float) or not 0 < timeout <= 3600:
        raise ValueError("client timeout must be a positive number no greater than 3600 seconds")
    values = {"url": endpoint, "api_key": key,
              "account": config.get("account"), "user": config.get("user"),
              "timeout": timeout, "extra_headers": {}, "auth_mode": "api_key"}
    for name in ("account", "user"):
        if values[name] is not None and not isinstance(values[name], str):
            raise ValueError("client account and user must be strings when supplied")
        values[name] = values[name] or None
    binding = {name: values[name] for name in ("url", "account", "user")}
    binding["credential_sha256"] = hashlib.sha256(key.encode()).hexdigest()
    return values, binding


def create_client(values):
    from openviking import AsyncHTTPClient

    # The SDK always reads a config file and environment, even with explicit args.
    # Resolve only this invocation's supported settings, then restore the process.
    inherited = {key: value for key, value in os.environ.items() if key.startswith("OPENVIKING_")}
    with tempfile.TemporaryDirectory(prefix="openviking-import-client-") as directory:
        config = Path(directory) / "ovcli.conf"
        fd = os.open(config, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(values, stream)
        try:
            for key in inherited:
                os.environ.pop(key)
            os.environ["OPENVIKING_CLI_CONFIG_FILE"] = str(config)
            return AsyncHTTPClient(**values)
        finally:
            for key in list(os.environ):
                if key.startswith("OPENVIKING_"):
                    os.environ.pop(key)
            os.environ.update(inherited)


def invalidate(state, persist, reason, ref):
    state["invalid"] = {"reason": reason, "session": ref.native_session_id}
    persist()
    raise ValueError("import state marked invalid; inspect the server and restore matching state before recovery")


def source_stamp(path):
    info = path.stat()
    return info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


def guard_source(ref, expected, stamp, state, persist):
    path = Path(ref.locator)
    try:
        matches = not path.is_symlink() and source_stamp(path) == stamp
        if expected is not None:
            matches = matches and digest(path) == expected and source_stamp(path) == stamp
    except OSError:
        matches = False
    if not matches:
        invalidate(state, persist, "source_changed", ref)


async def reconcile_counts(client, store, sid, ref, state, persist):
    from openviking_cli.exceptions import NotFoundError

    try:
        info = await client.get_session(sid)
    except NotFoundError:
        invalidate(state, persist, "server_session_missing", ref)
    count = info.get("message_count")
    row = store.get("codex", ref.native_session_id)
    confirmed = row.last_appended_count if row else 0
    pending = row.pending_count if row else 0
    if row:
        size = Path(ref.locator).stat().st_size
        for cursor in (row.cursor, row.pending_cursor):
            if cursor is not None:
                offset = cursor.value.get("offset")
                if type(offset) is not int or not 0 <= offset <= size:
                    invalidate(state, persist, "cursor_out_of_bounds", ref)
    if (type(count) is not int or count < 0 or confirmed < 0 or pending < 0 or
            (pending and (row.pending_baseline != confirmed or row.pending_cursor is None)) or
            count not in (confirmed, confirmed + pending)):
        invalidate(state, persist, "server_count_mismatch", ref)
    if pending:
        if count == confirmed + pending:
            store.confirm_append("codex", ref.native_session_id, row.pending_cursor, pending)
        else:
            store.clear_pending("codex", ref.native_session_id)


def guard_committed_progress(source, ref, sid, row, state, persist):
    if (row is None or row.ov_session_id != sid or row.pending_count or
            row.last_appended_count <= 0):
        invalidate(state, persist, "committed_cursor_mismatch", ref)
    try:
        stamp = source_stamp(Path(ref.locator))
    except OSError:
        invalidate(state, persist, "source_changed", ref)
    guard_source(ref, state["snapshot"][ref.native_session_id]["sha256"], stamp, state, persist)
    try:
        messages, _ = count_messages(source, ref)
    except OSError:
        invalidate(state, persist, "source_changed", ref)
    guard_source(ref, None, stamp, state, persist)
    if (row.cursor.value.get("offset") != stamp[1] or
            row.last_appended_count != messages):
        invalidate(state, persist, "committed_cursor_mismatch", ref)


async def wait_for_task(client, task_id, timeout, session_id=None):
    deadline = time.monotonic() + timeout
    while True:
        task = await client.get_task(task_id)
        if not task:
            raise ValueError("import task is missing or expired; inspect the session archive before recovery")
        if session_id is not None and (task.get("task_type") != "session_commit" or
                                       task.get("resource_id") != session_id):
            raise ValueError("extraction task does not match the imported session; inspect private task state")
        status = task.get("status")
        if status == "completed":
            result = task.get("result") or {}
            if (result.get("memory_extraction") or {}).get("skipped"):
                raise ValueError("extraction skipped memory operations; inspect the private task before continuing")
            return result.get("memories_extracted")
        if status in ("failed", "cancelled"):
            raise ValueError("import extraction " + status + "; inspect the private task before recovery")
        if time.monotonic() >= deadline:
            raise TimeoutError("extraction is still pending; rerun the same import to resume waiting")
        await asyncio.sleep(2)


async def finish_commit(client, sid, record, persist, timeout):
    if record.get("commit_started") and not record.get("task_id"):
        tasks = await client.list_tasks(task_type="session_commit", resource_id=sid, limit=10)
        tasks = [task for task in tasks if task["task_id"] not in record["previous_tasks"]]
        if len(tasks) != 1:
            raise ValueError("commit reply was lost; inspect the session and task history before retrying")
        record["task_id"] = tasks[0]["task_id"]
        persist()
    if not record.get("task_id"):
        tasks = await client.list_tasks(task_type="session_commit", resource_id=sid, limit=10)
        record["previous_tasks"] = [task["task_id"] for task in tasks]
        record["commit_started"] = time.time()
        persist()
        reply = await client.commit_session(sid, keep_recent_count=0)
        if not reply.get("task_id"):
            raise ValueError("commit returned no extraction task; inspect the session before recovery")
        record["task_id"] = reply["task_id"]
        persist()
    record["memories_extracted"] = await wait_for_task(client, record["task_id"], timeout, session_id=sid)


async def replay(source, selected, state, persist, store, client, prefix, timeout):
    from openviking.ingest.models import Cursor
    from openviking.ingest.replay import ConversationReplayClient, SessionReplayer
    from openviking_cli.exceptions import NotFoundError

    replayer = SessionReplayer(ConversationReplayClient(client), store, session_id_prefix=prefix)
    for index, (ref, fingerprint) in enumerate(selected, 1):
        if state.get("invalid"):
            raise ValueError("import state is invalid; explicit recovery is required")
        native_id = ref.native_session_id
        sid = replayer.ov_session_id("codex", native_id)
        record = state["files"].get(native_id)
        existing = None
        try:
            existing = await client.get_session(sid)
        except NotFoundError:
            pass
        if record is None:
            if existing is not None:
                raise ValueError("import session already exists without local state; recover its state before replaying")
            record = {"path": ref.locator, "sha256": fingerprint, "complete": False}
            state["files"][native_id] = record
            persist()
        if existing is None:
            if store.get("codex", native_id) or record.get("commit_started"):
                raise ValueError("server session disappeared but local progress exists; restore matching state")
            await client.create_session(session_id=sid, options={"auto_commit_policy": None})
        elif existing.get("auto_commit_policy"):
            raise ValueError("automatic commits are enabled on an import session; inspect before continuing")
        print(f"Session {index}/{len(selected)}: {sid}", flush=True)
        if not record.get("commit_started"):
            try:
                stamp = source_stamp(Path(ref.locator))
            except OSError:
                invalidate(state, persist, "source_changed", ref)
            guard_source(ref, fingerprint, stamp, state, persist)
            await reconcile_counts(client, store, sid, ref, state, persist)
            cursor = store.get_cursor("codex", native_id, source.cursor_kind)
            if cursor:
                # Equal content hashes permit resuming a restored copy at its old offset.
                cursor = Cursor(cursor.kind, {**cursor.value, "inode": Path(ref.locator).stat().st_ino})
            while True:
                guard_source(ref, None, stamp, state, persist)
                try:
                    messages, advanced = source.read_messages(ref, cursor)
                except OSError:
                    invalidate(state, persist, "source_changed", ref)
                guard_source(ref, None, stamp, state, persist)
                if messages:
                    await replayer.append_batch("codex", ref, messages,
                                                cursor or Cursor.zero(source.cursor_kind), advanced)
                elif advanced != cursor:
                    store.advance_cursor("codex", native_id, sid, advanced, locator=ref.locator)
                guard_source(ref, None, stamp, state, persist)
                await reconcile_counts(client, store, sid, ref, state, persist)
                if advanced == cursor:
                    break
                cursor = advanced
            guard_source(ref, fingerprint, stamp, state, persist)
        progress = store.get("codex", native_id)
        if record.get("commit_started"):
            guard_committed_progress(source, ref, sid, progress, state, persist)
        if progress and progress.last_appended_count:
            await finish_commit(client, sid, record, persist, timeout)
        store.mark_committed("codex", native_id)
        record["complete"] = True
        record["messages"] = progress.last_appended_count if progress else 0
        persist()
        status = "extraction verified" if record["messages"] else "empty conversation"
        print(f"Completed: {record['messages']} messages; {status}", flush=True)


async def apply(source, args, state_path):
    from openviking.ingest.cursor_store import CursorStore, SingleInstanceLock

    state_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if state_path.parent.is_symlink() or state_path.parent.stat().st_mode & 0o077:
        raise ValueError("import state directory must be private and not symlinked")
    with SingleInstanceLock(state_path.parent):
        state = read_private(state_path) if state_path.exists() else {"files": {}}
        values, binding = target_config(args.client_config, args.url)
        identity = {"source": str(args.source), "target": binding}
        if state.get("identity", identity) != identity:
            raise ValueError("import source or destination changed; review existing state before continuing")
        selected, complete = inventory(source, state, args.since, args.limit, args.session)
        state["identity"] = identity
        if state["files"] and not (state_path.parent / "state.db").exists():
            raise ValueError("import cursor database is missing; restore it alongside progress.json")
        store = CursorStore(state_path.parent)
        client = create_client(values)
        try:
            await client.initialize()
            # An authenticated data read also rejects ROOT credentials.
            await client.ls("viking://~")
            save(state_path, state)
            await replay(source, selected, state, lambda: save(state_path, state),
                         store, client, "codex-" + args.name, args.wait_timeout)
        finally:
            await client.close()
            store.close()
        print(json.dumps({"completed": len(selected), "already_complete": complete}))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="reviewed snapshot of Codex sessions/")
    parser.add_argument("--name", required=True, help="stable import name, reused for every batch and rerun")
    parser.add_argument("--apply", action="store_true", help="write sessions and wait for memory extraction")
    parser.add_argument("--limit", type=int, help="maximum unfinished sessions in this run")
    parser.add_argument("--session", action="append", help="select a native Codex session id; repeat for multiple sessions")
    parser.add_argument("--since", help="include sessions starting on/after YYYY-MM-DD")
    parser.add_argument("--client-config", type=Path, default=Path.home() / ".openviking/ovcli.conf")
    parser.add_argument("--url", help="override the endpoint without modifying private configuration")
    parser.add_argument("--wait-timeout", type=int, default=900, help="seconds to wait per extraction task")
    args = parser.parse_args(argv)
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}", args.name):
        parser.error("name must be 1-64 letters, digits, underscores, or hyphens")
    if (args.limit is not None and args.limit < 1) or args.wait_timeout < 1:
        parser.error("limit and wait-timeout must be positive")
    if args.since:
        date.fromisoformat(args.since)
    args.source = args.source.expanduser().resolve(strict=True)
    if not args.source.is_dir():
        parser.error("source must be a Codex sessions directory")
    os.umask(0o077)
    source = source_for(args.source)
    state_path = Path.home() / ".openviking/imports" / args.name / "state/progress.json"
    if args.apply:
        asyncio.run(apply(source, args, state_path))
    else:
        state = read_private(state_path) if state_path.exists() else {}
        selected, complete = inventory(source, state, args.since, args.limit, args.session)
        totals = [count_messages(source, ref) for ref, _ in selected]
        print(json.dumps({"mode": "preview", "selected": len(selected), "already_complete": complete,
                          "messages": sum(n for n, _ in totals), "characters": sum(n for _, n in totals)}))


if __name__ == "__main__":
    # Upstream HTTP exceptions can contain returned content. Report the failure
    # class here; session/task details remain in the authenticated server.
    logging.disable(logging.CRITICAL)
    try:
        main()
    except (ValueError, TimeoutError) as error:
        raise SystemExit("Codex import: " + str(error))
    except Exception as error:
        raise SystemExit("Codex import failed (" + type(error).__name__ + "); inspect private state and server diagnostics")
