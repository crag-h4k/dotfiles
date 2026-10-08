# scripts/normalize-zshrc.py
"""Remove one redundant installer PATH tail after its pre-apply backup."""
import argparse
import os
from pathlib import Path
import re
import stat
import tempfile

PATH_GUARD = 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'


def normalize(source, target, backup):
    if target.is_symlink() or not target.is_file():
        return False
    canonical = source.read_bytes()
    current = target.read_bytes()
    if current == canonical or not current.startswith(canonical):
        return False
    # A local zshenv edit must not lose the only hook providing this PATH entry.
    source_env = source.with_name("dot_zshenv")
    target_env = target.with_name(".zshenv")
    if not source_env.is_file() or not target_env.is_file() or source_env.read_bytes() != target_env.read_bytes():
        return False
    if b'export PATH=$HOME/.local/bin:$PATH' not in source_env.read_bytes():
        return False
    lines = current[len(canonical):].decode("utf-8").splitlines()
    tail = [line for line in lines if line.strip()]
    known_tail = tail == [PATH_GUARD] or (
        len(tail) == 2 and re.fullmatch(r"# [^\r\n]+ command", tail[0]) and tail[1] == PATH_GUARD
    )
    if not known_tail:
        return False
    snapshot = backup / ".zshrc"
    if not snapshot.is_file() or snapshot.read_bytes() != current:
        raise ValueError("refusing PATH-tail migration without a matching pre-apply backup")
    info = target.stat()
    if info.st_uid != os.getuid():
        raise ValueError("refusing to change a zshrc owned by another user")
    fd, temporary = tempfile.mkstemp(prefix=".zshrc-", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), stat.S_IMODE(info.st_mode))
            stream.write(canonical)
        if target.read_bytes() != current:
            raise ValueError("zshrc changed during PATH-tail migration")
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    parser.add_argument("backup", type=Path)
    args = parser.parse_args()
    if normalize(args.source, args.target, args.backup):
        print("dotfiles: removed backed-up redundant .zshrc PATH tail (already supplied by .zshenv)")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit("dotfiles: zshrc migration: " + str(error))
