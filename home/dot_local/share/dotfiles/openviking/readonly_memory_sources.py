# home/dot_local/share/dotfiles/openviking/readonly_memory_sources.py
"""Plan and import file memories, or export OpenCode 2 history, for OpenViking."""
import argparse
import asyncio
import contextlib
import datetime
import difflib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import tempfile
import urllib.parse

TYPE_DIRECTORIES = {"feedback": "preferences/user", "project": "entities/project", "reference": "entities/reference"}
MAX_BYTES = 256 * 1024
FRONT_MATTER = re.compile(r"\A---\n(.*?)\n---\n", re.S)
FOOTER = re.compile(r"\n*<!-- MEMORY_FIELDS\b.*?-->\s*\Z", re.S)
PERSONAL = re.compile(r"\(\s*personal\b", re.I)
INDEX_LINK = re.compile(r"\[[^\]]*\]\(([^)]+?)\.md\)")
INDEX_BARE = re.compile(r"\s*[-*]\s+([\w.-]+)\s+-")
SAFE_NAME = re.compile(r"[^A-Za-z0-9_-]")
OPENVIKING = Path.home() / ".openviking"


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


def private_directory(path, create=False):
    if create:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if path.is_symlink() or not stat.S_ISDIR(info.st_mode):
        raise ValueError("expected a real directory, not a symlink: " + path.name)
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("directory must be owned by you with mode 700: " + path.name)


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
    values = {"url": endpoint, "api_key": key, "account": config.get("account") or None,
              "user": config.get("user") or None, "timeout": timeout, "extra_headers": {}, "auth_mode": "api_key"}
    binding = {name: values[name] for name in ("url", "account", "user")}
    binding["credential_sha256"] = hashlib.sha256(key.encode()).hexdigest()
    return values, binding


def create_client(values):
    from openviking import AsyncHTTPClient

    # The SDK reads a config file and the environment even with explicit arguments.
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


async def open_client(path, url=None):
    values, binding = target_config(path, url)
    client = create_client(values)
    await client.initialize()
    # An authenticated data read also rejects ROOT credentials.
    await client.ls("viking://~")
    return client, binding


def normalize(text):
    return text.replace("\r\n", "\n").rstrip() + "\n"


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def front_matter(text):
    match = FRONT_MATTER.match(text)
    fields = {}
    if match:
        for line in match.group(1).splitlines():
            key, separator, value = line.partition(":")
            if separator and key and not key[0].isspace():
                fields[key.strip()] = value.strip().strip("\"'")
    return fields


def memory_kind(name, fields):
    declared = fields.get("type")
    prefix = name.split("_", 1)[0]
    for candidate in (declared, prefix):
        if candidate in TYPE_DIRECTORIES or candidate == "user":
            return candidate
    return None


def personal_names(root):
    index = root / "MEMORY.md"
    names = set()
    if not index.is_file():
        return names
    for line in index.read_text(encoding="utf-8", errors="replace").splitlines():
        if PERSONAL.search(line):
            found = INDEX_LINK.search(line) or INDEX_BARE.match(line)
            if found:
                names.add(Path(found.group(1)).name + ".md")
    return names


def resolve_roots(sources):
    """Resolve source directories; two paths to the same directory count once."""
    roots, aliases = [], []
    for source in sources:
        try:
            real = Path(source).expanduser().resolve(strict=True)
        except (OSError, RuntimeError):
            raise ValueError("memory source does not exist or loops through links: " + str(source)) from None
        if not real.is_dir():
            raise ValueError("memory source is not a directory: " + str(source))
        if real in roots:
            aliases.append({"source": str(source), "alias_of": str(real)})
        else:
            roots.append(real)
    return roots, aliases


def inventory(roots, excluded=(), include_personal=False):
    """Read every eligible memory file once, whatever path or link reaches it."""
    items, skipped, seen = [], [], {}
    for root in roots:
        personal = set() if include_personal else personal_names(root)
        for entry in sorted(os.scandir(root), key=lambda item: (item.is_symlink(), item.name)):
            name = entry.name
            if not name.endswith(".md") or name.startswith(".") or name == "MEMORY.md":
                continue
            path = root / name
            if name in excluded:
                skipped.append({"name": name, "reason": "excluded"})
                continue
            if name in personal:
                skipped.append({"name": name, "reason": "personal-marker"})
                continue
            try:
                target = path.resolve(strict=True)
            except (OSError, RuntimeError):
                skipped.append({"name": name, "reason": "dangling-link" if entry.is_symlink() else "unreadable"})
                continue
            if entry.is_symlink() and not any(target.is_relative_to(other) for other in roots):
                skipped.append({"name": name, "reason": "link-outside-sources"})
                continue
            info = target.stat()
            if not stat.S_ISREG(info.st_mode):
                skipped.append({"name": name, "reason": "not-a-regular-file"})
                continue
            if info.st_size > MAX_BYTES:
                skipped.append({"name": name, "reason": "too-large"})
                continue
            identity = (info.st_dev, info.st_ino)
            if identity in seen:
                skipped.append({"name": name, "reason": "duplicate-of-" + seen[identity]})
                continue
            try:
                text = normalize(target.read_text(encoding="utf-8"))
            except UnicodeDecodeError:
                skipped.append({"name": name, "reason": "not-utf8"})
                continue
            seen[identity] = name
            fields = front_matter(text)
            kind = memory_kind(name, fields)
            if kind == "user":
                skipped.append({"name": name, "reason": "profile-singleton-review"})
                continue
            if kind is None:
                skipped.append({"name": name, "reason": "unclassified"})
                continue
            items.append({"name": name, "rel": TYPE_DIRECTORIES[kind] + "/" + name, "text": text,
                          "sha256": digest(text), "mtime": info.st_mtime, "path": str(target),
                          "linked": entry.is_symlink()})
    names = {}
    for item in items:
        names.setdefault(item["name"], []).append(item)
    clashes = {name for name, group in names.items() if len(group) > 1}
    kept = []
    for item in items:
        if item["name"] in clashes:
            skipped.append({"name": item["name"], "reason": "name-collision-between-sources"})
        else:
            kept.append(item)
    return kept, skipped


def classify(item, remote, elsewhere, entry):
    """Name the action for one file; nothing here changes OpenViking."""
    if remote is None:
        return ("present-elsewhere", "same name under another memory directory") if elsewhere else ("new", "not in OpenViking")
    current = digest(remote)
    if current == item["sha256"]:
        return "identical", "already in OpenViking"
    recorded = (entry or {}).get("sha256")
    if recorded and current == recorded:
        return "update", "file changed since the last import; OpenViking copy untouched"
    if recorded and item["sha256"] == recorded:
        return "openviking-ahead", "OpenViking copy changed after import; file untouched"
    return "conflict", "file and OpenViking copy both differ"


def iso(milliseconds):
    moment = datetime.datetime.fromtimestamp(milliseconds / 1000, tz=datetime.timezone.utc)
    return moment.isoformat().replace("+00:00", "Z")


def delta(old, new):
    lines = list(difflib.unified_diff(old.splitlines(), new.splitlines(), lineterm="", n=0))
    return {"added": sum(1 for line in lines if line.startswith("+") and not line.startswith("+++")),
            "removed": sum(1 for line in lines if line.startswith("-") and not line.startswith("---"))}


def newer_side(file_mtime, remote_time):
    """Compare the file's mtime with OpenViking's modTime; close or missing is unknown."""
    try:
        remote = datetime.datetime.fromisoformat(remote_time.replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        return "unknown"
    if abs(file_mtime - remote) < 2:
        return "unknown"
    return "file" if file_mtime > remote else "openviking"


async def remote_index(client, root):
    from openviking_cli.exceptions import NotFoundError

    try:
        uris = await client.ls(root, simple=True, recursive=True, node_limit=10000)
    except NotFoundError:
        return {}, {}
    rel = {}
    names = {}
    for uri in uris:
        tail = uri.split("/memories/", 1)[-1] if "/memories/" in uri else None
        if tail and tail.endswith(".md") and not Path(tail).name.startswith("."):
            rel[tail] = uri
            names.setdefault(Path(tail).name, []).append(tail)
    return rel, names


async def plan_files(client, root, items, manifest):
    from openviking_cli.exceptions import NotFoundError

    present, names = await remote_index(client, root)
    rows = []
    for item in items:
        uri = root + "/" + item["rel"]
        remote = None
        if item["rel"] in present:
            try:
                remote = normalize(FOOTER.sub("", await client.read(uri)))
            except NotFoundError:
                remote = None
        elsewhere = [other for other in names.get(item["name"], []) if other != item["rel"]]
        action, reason = classify(item, remote, elsewhere, manifest.get("files", {}).get(item["rel"]))
        row = {"name": item["name"], "action": action, "reason": reason, "to": item["rel"],
               "link": item["linked"], "sha256": item["sha256"], "_item": item, "_remote": remote}
        if action in ("update", "conflict", "openviking-ahead"):
            try:
                row["newer"] = newer_side(item["mtime"], (await client.stat(uri)).get("modTime"))
            except NotFoundError:
                row["newer"] = "unknown"
            row["change"] = delta(remote, item["text"])
        rows.append(row)
    return rows, present


async def apply_files(client, root, rows, present, updates, manifest, persist):
    from openviking_cli.exceptions import NotFoundError

    written = []
    for row in rows:
        item = row["_item"]
        if row["action"] == "identical":
            manifest["files"][item["rel"]] = {"sha256": item["sha256"], "adopted": True}
        elif row["action"] == "new" or (row["action"] in ("update", "conflict") and item["name"] in updates):
            target = root + "/" + item["rel"]
            try:
                current = normalize(FOOTER.sub("", await client.read(target)))
            except NotFoundError:
                current = None
            if row["action"] == "new" and current is not None:
                row["action"], row["reason"] = "appeared-since-plan", "OpenViking gained this file after the plan; not overwritten"
                continue
            if row["action"] != "new" and current != row["_remote"]:
                row["action"], row["reason"] = "changed-since-plan", "OpenViking copy changed after the plan; not overwritten"
                continue
            parent = root + "/" + item["rel"].rsplit("/", 1)[0]
            if not any(path.startswith(item["rel"].rsplit("/", 1)[0] + "/") for path in present):
                await client.mkdir(parent)
            await client.write(target, item["text"], mode="replace")
            written.append(row)
    if written:
        await client.wait_processed()
    for row in written:
        item = row["_item"]
        try:
            stored = normalize(FOOTER.sub("", await client.read(root + "/" + item["rel"])))
        except NotFoundError:
            stored = None
        if stored != item["text"]:
            row["action"], row["reason"] = "write-unverified", "read-back differs from the file"
            continue
        row["action"] = "written"
        manifest["files"][item["rel"]] = {"sha256": item["sha256"]}
    persist()
    return len(written)


def run_files(args):
    roots, aliases = resolve_roots(args.source)
    items, skipped = inventory(roots, set(args.exclude or ()), args.include_personal)
    state_dir = args.state_root / args.name
    state_path = state_dir / "state.json"

    async def go():
        client, binding = await open_client(args.client_config, args.url)
        try:
            manifest = {"files": {}}
            if state_path.exists():
                manifest = read_private(state_path)
                if manifest.get("target", binding) != binding:
                    raise ValueError("import destination changed; review the existing state before continuing")
            manifest.setdefault("files", {})
            rows, present = await plan_files(client, "viking://~/memories", items, manifest)
            unknown = set(args.update or ()) - {row["name"] for row in rows if row["action"] in ("update", "conflict")}
            if unknown:
                raise ValueError("--update names files that have no pending change: " + ", ".join(sorted(unknown)))
            written = 0
            if args.apply:
                private_directory(state_dir, create=True)
                with open(state_dir / ".lock", "w") as lock:
                    try:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except OSError:
                        raise ValueError("another memory import is running") from None
                    manifest["target"] = binding
                    written = await apply_files(client, "viking://~/memories", rows, present, set(args.update or ()),
                                                manifest, lambda: save(state_path, manifest))
            return rows, written
        finally:
            await client.close()

    rows, written = asyncio.run(go())
    counts = {}
    for row in rows:
        counts[row["action"]] = counts.get(row["action"], 0) + 1
    needs = [row for row in rows if row["action"] in ("new", "update", "conflict")]
    shown = set(args.show_diff or ())
    result = {
        "mode": "apply" if args.apply else "plan",
        "sources": [str(root) for root in roots], "aliases": aliases,
        "summary": counts, "skipped": len(skipped), "written": written,
        "files": [{key: value for key, value in row.items() if not key.startswith("_") and key != "sha256"}
                  for row in rows if row["action"] != "identical"],
        "skipped_files": skipped,
        "next": None if not needs or args.apply else "rerun with --apply; add --update NAME for each changed file you approve",
    }
    if shown:
        result["diffs"] = {row["name"]: "\n".join(difflib.unified_diff(
            row["_remote"].splitlines(), row["_item"]["text"].splitlines(), "openviking", "file", lineterm=""))
            for row in rows if row["name"] in shown and row.get("_remote") is not None}
    print(json.dumps(result, indent=2))


def oc2_messages(connection, session):
    records = []
    rows = connection.execute(
        "SELECT type, time_created, data FROM session_message WHERE session_id = ? "
        "AND type IN ('user', 'assistant') ORDER BY seq", (session,)).fetchall()
    for kind, created, raw in rows:
        try:
            data = json.loads(raw)
        except ValueError:
            continue
        if kind == "user":
            text = (data.get("text") or "").strip()
            message = {"role": "user", "content": text}
        else:
            blocks = [item.get("text", "").strip() for item in data.get("content", [])
                      if isinstance(item, dict) and item.get("type") == "text"]
            text = "\n".join(block for block in blocks if block)
            model = (data.get("model") or {}).get("id")
            message = {"role": "assistant", "content": [{"type": "text", "text": text}]}
            if model:
                message["model"] = model
        if text:
            records.append({"type": kind, "sessionId": session, "timestamp": iso(created), "message": message})
    return records


def imported_ids(imports_root):
    seen = set()
    if imports_root.is_dir():
        for state in sorted(imports_root.glob("*/state/progress.json")):
            seen.update(read_private(state).get("files", {}))
    return seen


async def session_present(client, session):
    from openviking_cli.exceptions import NotFoundError

    try:
        await client.get_session("oc-" + session)
        return True
    except NotFoundError:
        return False


def run_oc2(args):
    try:
        database = Path(args.db).expanduser().resolve(strict=True)
    except (OSError, RuntimeError):
        raise ValueError("OpenCode database not found: " + str(args.db)) from None
    if not database.is_file():
        raise ValueError("OpenCode database path is not a regular file")
    with contextlib.closing(sqlite3.connect(f"file:{database}?mode=ro", uri=True, timeout=5.0)) as connection:
        tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        if not {"session_v2", "session_message"} <= tables:
            raise ValueError("no OpenCode 2 session tables (session_v2, session_message) in this database")
        sessions = connection.execute(
            "SELECT id, project_id, parent_id, time_created, time_updated FROM session_v2 ORDER BY time_created").fetchall()
        elsewhere = imported_ids(args.imports_root)
        cutoff = (datetime.datetime.now(datetime.timezone.utc).timestamp() - args.min_idle_hours * 3600) * 1000
        since = None
        if args.since:
            since = datetime.datetime.fromisoformat(args.since).replace(tzinfo=datetime.timezone.utc).timestamp() * 1000

        async def live_ids():
            if args.no_ov_check:
                return set()
            client, _ = await open_client(args.client_config, args.url)
            try:
                return {session[0] for session in sessions if await session_present(client, session[0])}
            finally:
                await client.close()

        live = asyncio.run(live_ids())
        reasons, eligible = {}, []
        for session, project, parent, created, updated in sessions:
            reason = None
            if SAFE_NAME.search(session):
                reason = "unsafe-session-id"
            elif parent and not args.include_children:
                reason = "child-session"
            elif updated > cutoff:
                reason = "recently-active"
            elif since and created < since:
                reason = "before-since"
            elif session in live:
                reason = "already-in-openviking"
            elif session in elsewhere:
                reason = "imported-elsewhere"
            else:
                records = oc2_messages(connection, session)
                if not records:
                    reason = "no-conversation-text"
                else:
                    eligible.append((session, project, records))
            if reason:
                reasons[reason] = reasons.get(reason, 0) + 1
        summary = {"sessions": len(sessions), "eligible": len(eligible), "skipped": reasons,
                   "messages": sum(len(records) for _, _, records in eligible)}
        result = {"mode": "export" if args.apply else "plan", "database": str(database), "summary": summary,
                  "eligible_sessions": [session for session, _, _ in eligible]}
        if args.apply:
            if not args.out:
                raise ValueError("--out is required with --apply")
            if args.out.exists() and any(args.out.iterdir()):
                raise ValueError("use a new, empty --out directory for every batch; a changed snapshot cannot resume an import")
            private_directory(args.out, create=True)
            for session, project, records in eligible:
                folder = args.out / (SAFE_NAME.sub("_", project)[:64] or "project")
                private_directory(folder, create=True)
                descriptor = os.open(folder / (session + ".jsonl"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(descriptor, "w") as stream:
                    for record in records:
                        stream.write(json.dumps(record, ensure_ascii=False) + "\n")
            result["snapshot"] = str(args.out)
            result["next"] = "openvikingctl import-claude --source " + str(args.out) + " --name oc2-<date>   (preview first, then --apply)"
        else:
            result["next"] = "rerun with --apply --out <new empty directory> to write the snapshot" if eligible else None
        print(json.dumps(result, indent=2))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    shared = argparse.ArgumentParser(add_help=False)
    shared.add_argument("--client-config", type=Path, default=OPENVIKING / "ovcli.conf")
    shared.add_argument("--url", help="override the endpoint without modifying private configuration")
    shared.add_argument("--apply", action="store_true", help="write; the default is a read-only plan")
    files = commands.add_parser("files", parents=[shared], help="import file memories")
    default_agents = Path(os.environ.get("DOTFILES_AGENTS_DIR") or Path.home() / "agents")
    files.add_argument("--source", action="append", type=Path, help="memory directory; repeat for several (default: agents dir /memory)")
    files.add_argument("--name", default="default", help="state name under the memory import state root")
    files.add_argument("--state-root", type=Path, default=OPENVIKING / "memory-imports")
    files.add_argument("--update", action="append", help="approve replacing the OpenViking copy of this file name")
    files.add_argument("--show-diff", action="append", help="include the OpenViking-to-file diff for this file name in the plan")
    files.add_argument("--exclude", action="append", help="skip this file name")
    files.add_argument("--include-personal", action="store_true", help="include files the index marks (personal)")
    oc2 = commands.add_parser("oc2", parents=[shared], help="export OpenCode 2 history as a private snapshot")
    oc2.add_argument("--db", type=Path, default=Path.home() / ".local/share/opencode/opencode.db")
    oc2.add_argument("--out", type=Path, help="new snapshot directory (required with --apply)")
    oc2.add_argument("--since", help="only sessions created on or after YYYY-MM-DD")
    oc2.add_argument("--include-children", action="store_true", help="include sub-agent sessions")
    oc2.add_argument("--min-idle-hours", type=float, default=24, help="skip sessions active more recently than this")
    oc2.add_argument("--no-ov-check", action="store_true", help="do not ask OpenViking which sessions it already holds")
    oc2.add_argument("--imports-root", type=Path, default=OPENVIKING / "imports")
    args = parser.parse_args(argv)
    if args.command == "files":
        args.source = args.source or [default_agents / "memory"]
        if args.update and not args.apply:
            parser.error("--update only applies with --apply")
        run_files(args)
    else:
        run_oc2(args)


if __name__ == "__main__":
    import logging

    # Upstream HTTP errors can carry returned content; report only the class.
    logging.disable(logging.CRITICAL)
    try:
        main()
    except ValueError as error:
        raise SystemExit("OpenViking memory import: " + str(error))
    except Exception as error:
        raise SystemExit("OpenViking memory import failed (" + type(error).__name__ + ")")
