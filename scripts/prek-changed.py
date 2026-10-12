"""Run prek on files changed from the local main branch, including staged edits."""

import os
import subprocess


root = subprocess.check_output(
    ["git", "rev-parse", "--show-toplevel"], text=True
).strip()
changed = subprocess.check_output(
    ["git", "diff", "--name-only", "--diff-filter=ACMR", "-z", "main", "--"],
    cwd=root,
).split(b"\0")
files = [os.fsdecode(path) for path in changed if path]

if files:
    raise SystemExit(subprocess.call(["prek", "run", "--files", *files], cwd=root))

print("No files differ from main.")
