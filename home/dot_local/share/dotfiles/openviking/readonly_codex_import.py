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
    refs = list(source.discover_sessions())
    if not refs:
        raise ValueError("no Codex rollout logs found under YEAR/MONTH/DAY")
    selected = []
    seen = set()
    requested = set(sessions or [])
    if requested - {ref.native_session_id for ref in refs}:
        raise ValueError("a requested session is absent from the snapshot")
    complete = 0
    for ref in refs:
        sid = ref.native_session_id
        if sid in seen:
            raise ValueError("duplicate Codex session id; review the snapshot before importing")
        seen.add(sid)
        if requested and sid not in requested:
            continue
        if since and (not ref.started_at or ref.started_at < since):
            continue
        path = Path(ref.locator)
        if path.is_symlink():
            raise ValueError("rollout files must be regular files, not symlinks")
        validate_rollout(path)
        fingerprint = digest(path)
        previous = state.get("files", {}).get(sid, {})
        if previous and (previous["sha256"] != fingerprint or previous["path"] != str(path)):
            raise ValueError("a previously imported rollout changed; retain the original snapshot and state")
        if previous.get("complete"):
            complete += 1
            continue
        if limit is None or len(selected) < limit:
            selected.append((ref, fingerprint))
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
    values = {"url": endpoint, "api_key": key,
              "account": config.get("account") or None, "user": config.get("user") or None}
    binding = dict(values)
    binding.pop("api_key")
    binding["credential_sha256"] = hashlib.sha256(key.encode()).hexdigest()
    return values, binding


async def wait_for_task(client, task_id, timeout):
    deadline = time.monotonic() + timeout
    while True:
        task = await client.get_task(task_id)
        if not task:
            raise ValueError("import task is missing or expired; inspect the session archive before recovery")
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
    record["memories_extracted"] = await wait_for_task(client, record["task_id"], timeout)


async def replay(source, selected, state, persist, store, client, prefix, timeout):
    from openviking.ingest.models import Cursor
    from openviking.ingest.replay import ConversationReplayClient, SessionReplayer
    from openviking_cli.exceptions import NotFoundError

    replayer = SessionReplayer(ConversationReplayClient(client), store, session_id_prefix=prefix)
    for index, (ref, fingerprint) in enumerate(selected, 1):
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
            await replayer.reconcile("codex", ref)
            previous = store.get("codex", native_id)
            if previous and previous.pending_count:
                raise ValueError("append reconciliation failed; rerun when the server is available")
            cursor = store.get_cursor("codex", native_id, source.cursor_kind)
            if cursor:
                # Equal content hashes permit resuming a restored copy at its old offset.
                cursor = Cursor(cursor.kind, {**cursor.value, "inode": Path(ref.locator).stat().st_ino})
            while True:
                messages, advanced = source.read_messages(ref, cursor)
                if messages:
                    await replayer.append_batch("codex", ref, messages,
                                                cursor or Cursor.zero(source.cursor_kind), advanced)
                elif advanced != cursor:
                    store.advance_cursor("codex", native_id, sid, advanced, locator=ref.locator)
                if advanced == cursor:
                    break
                cursor = advanced
            # Never silently restart from offset zero if a copied snapshot is replaced.
            if digest(Path(ref.locator)) != fingerprint:
                raise ValueError("rollout changed during replay; stop and inspect the private session")
        progress = store.get("codex", native_id)
        if progress and progress.last_appended_count:
            await finish_commit(client, sid, record, persist, timeout)
        store.mark_committed("codex", native_id)
        record["complete"] = True
        record["messages"] = progress.last_appended_count if progress else 0
        persist()
        status = "extraction verified" if record["messages"] else "empty conversation"
        print(f"Completed: {record['messages']} messages; {status}", flush=True)


async def apply(source, args, state_path):
    from openviking import AsyncHTTPClient
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
        client = AsyncHTTPClient(**values)
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
