# scripts/migrate-claude-skills.py
"""Safely make ~/.claude/skills a compatibility link to ~/.agents/skills."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile


EXPECTED_LINK = Path("../.agents/skills")
# Plan actions that never change the filesystem.
IDLE_ACTIONS = ("ready", "absent", "inaccessible")


def file_sha256(path: Path) -> str:
    # hashlib.file_digest needs Python 3.11; macOS ships 3.9.
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def entry_signature(path: Path) -> tuple:
    """Return a content signature without following symbolic links."""
    info = path.lstat()
    mode = info.st_mode
    if stat.S_ISLNK(mode):
        return ("link", os.readlink(path))
    if stat.S_ISREG(mode):
        return ("file", file_sha256(path))
    if not stat.S_ISDIR(mode):
        raise ValueError(f"unsupported skill entry type: {path}")

    members = []
    for member in sorted(path.rglob("*")):
        relative = str(member.relative_to(path))
        member_info = member.lstat()
        member_mode = member_info.st_mode
        if stat.S_ISLNK(member_mode):
            members.append(("link", relative, os.readlink(member)))
        elif stat.S_ISREG(member_mode):
            members.append(("file", relative, file_sha256(member)))
        elif stat.S_ISDIR(member_mode):
            members.append(("dir", relative))
        else:
            raise ValueError(f"unsupported skill entry type: {member}")
    return ("directory", tuple(members))


def same_entry(source: Path, destination: Path) -> bool:
    try:
        if os.path.samefile(source, destination):
            return True
    except FileNotFoundError:
        return False
    return entry_signature(source) == entry_signature(destination)


def existing(path: Path) -> bool:
    return path.exists() or path.is_symlink()


def writable_owner_directory(path: Path, label: str) -> None:
    info = path.lstat()
    if path.is_symlink() or not stat.S_ISDIR(info.st_mode):
        raise ValueError(label + " must be a real directory, not a symlink")
    if info.st_uid != os.getuid() or info.st_mode & 0o022:
        raise ValueError(label + " must be owned by you and not group or world writable")


def journal_path(home: Path) -> Path:
    return home / ".local/state/dotfiles/claude-skills-migration.json"


def read_journal(home: Path):
    path = journal_path(home)
    if not path.exists():
        return None
    info = path.lstat()
    if path.is_symlink() or not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("Claude skill migration journal must be a private regular file")
    return json.loads(path.read_text())


def write_journal(home: Path, status: str, plan: list[tuple[str, Path, Path | None]]) -> None:
    path = journal_path(home)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    payload = {
        "status": status,
        "actions": [
            {"action": action, "source": str(source), "destination": str(destination) if destination else None}
            for action, source, destination in plan
        ],
    }
    descriptor, temporary = tempfile.mkstemp(prefix=".claude-skills-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(payload, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def migration_plan(home: Path) -> list[tuple[str, Path, Path | None]]:
    """Return the reviewed migration steps without changing either skill root."""
    source_root = home / ".claude/skills"
    destination_root = home / ".agents/skills"

    journal = read_journal(home)
    if journal and journal.get("status") != "complete":
        raise ValueError("an earlier Claude skill migration is incomplete; inspect the private migration journal")
    # Claude Code may never have run here, and ~/.claude may not be traversable.
    # Path.exists() and Path.is_symlink() raise on EACCES before Python 3.14, so
    # inspect the root directly. Nothing to read means nothing to migrate.
    try:
        root_mode = source_root.lstat().st_mode
    except (FileNotFoundError, NotADirectoryError):
        return [("absent", source_root, None)]
    except OSError:
        return [("inaccessible", source_root, None)]
    if stat.S_ISLNK(root_mode):
        if source_root.resolve() == destination_root.resolve():
            return [("ready", source_root, None)]
        raise ValueError("~/.claude/skills is a symlink to an unexpected target")
    writable_owner_directory(source_root, "~/.claude/skills")

    plan: list[tuple[str, Path, Path | None]] = []
    if existing(destination_root):
        writable_owner_directory(destination_root, "~/.agents/skills")
    else:
        plan.append(("create", destination_root, None))
    # A directory this account cannot list has no entries to compare or move.
    if not os.access(source_root, os.R_OK | os.X_OK):
        return [("inaccessible", source_root, None)]
    for source in sorted(source_root.iterdir(), key=lambda path: path.name):
        if source.name == ".DS_Store":
            plan.append(("remove", source, None))
            continue
        destination = destination_root / source.name
        if existing(destination):
            if same_entry(source, destination):
                plan.append(("deduplicate", source, destination))
                continue
            raise ValueError(
                "skill name conflicts with a different ~/.agents/skills entry: " + source.name
            )
        plan.append(("move", source, destination))
    plan.append(("link", source_root, destination_root))
    return plan


def describe(plan: list[tuple[str, Path, Path | None]]) -> str:
    lines = []
    for action, source, destination in plan:
        if action == "ready":
            lines.append("Claude skills already use the canonical agent-skills root")
        elif action == "absent":
            lines.append("No legacy Claude skills directory exists")
        elif action == "inaccessible":
            lines.append("Claude skills directory is not accessible; skipping legacy migration")
        elif action == "create":
            lines.append("Create canonical Agent Skills directory " + str(source))
        elif action == "remove":
            lines.append("Remove macOS metadata " + str(source))
        elif action == "deduplicate":
            lines.append("Keep canonical " + str(destination) + "; remove duplicate " + str(source))
        elif action == "move":
            lines.append("Move " + str(source) + " to " + str(destination))
        else:
            lines.append("Replace " + str(source) + " with compatibility link to " + str(destination))
    return "\n".join(lines)


def apply(plan: list[tuple[str, Path, Path | None]], home: Path | None = None) -> None:
    mutating = any(action not in IDLE_ACTIONS for action, _, _ in plan)
    if mutating and home is not None:
        write_journal(home, "in_progress", plan)
    for action, source, destination in plan:
        if action in IDLE_ACTIONS:
            continue
        if action == "create":
            source.mkdir(mode=0o700, parents=True, exist_ok=False)
        if action in ("remove", "deduplicate"):
            if source.is_dir() and not source.is_symlink():
                shutil.rmtree(source)
            else:
                source.unlink()
        elif action == "move":
            assert destination is not None
            shutil.move(str(source), str(destination))
        elif action == "link":
            assert destination is not None
            source.rmdir()
            source.symlink_to(EXPECTED_LINK)
    if mutating and home is not None:
        write_journal(home, "complete", plan)


def humanizer_instructions_plan(home: Path) -> list[tuple[str, Path, Path | None]]:
    """Rename the managed upstream manifest so it is no longer discoverable."""
    upstream = home / ".local/share/agent-skills/humanizer/upstream"
    source = upstream / "SKILL.md"
    destination = upstream / "instructions.md"
    if not existing(source):
        return [("absent", source, None)]
    if existing(destination):
        if same_entry(source, destination):
            return [("deduplicate", source, destination)]
        raise ValueError("Humanizer upstream instructions conflict with a different instructions.md")
    return [("move", source, destination)]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--apply", action="store_true", help="perform the reviewed migration")
    parser.add_argument("--humanizer-instructions", action="store_true",
                        help="rename the upstream Humanizer manifest outside skill discovery")
    args = parser.parse_args(argv)
    home = args.home.expanduser().resolve()
    plan = humanizer_instructions_plan(home) if args.humanizer_instructions else migration_plan(home)
    print(describe(plan))
    if args.apply:
        apply(plan, home)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print("migrate-claude-skills: " + str(error), file=sys.stderr)
        raise SystemExit(1)
