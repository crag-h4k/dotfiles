# pbvar

Set an environment variable in the current shell from the clipboard.

```sh
pbvar TOKEN          # export $TOKEN with the clipboard contents
pbvar --raw MULTI    # keep the clipboard bytes exactly (no newline strip)
```

Handy for pasting a copied token, ARN, or URL into an env var without it landing
in shell history or echoing on screen.

## How it works

A child process cannot change its parent shell's environment, so `pbvar` is two
pieces:

- A Go binary (`~/.local/bin/pbvar`) that reads the clipboard, validates the
  name, shell-escapes the value, and prints `export NAME='...'` to stdout. Its
  confirmation line and any error go to stderr, so stdout carries only the
  statement to evaluate and the value never mixes with noise.
- A one-line zsh function in `~/.zsh/aliases` that runs `eval "$(pbvar ...)"`,
  injecting the export into the interactive shell.

The name must match `[A-Za-z_][A-Za-z0-9_]*`; anything else is rejected, and the
value is single-quote escaped, so clipboard contents cannot inject shell code.

## Clipboard read

- macOS: reads the local clipboard with `pbpaste`.
- Everywhere else, and as a macOS fallback: queries the terminal over OSC 52.
  This needs no system packages and works over SSH into a headless host, because
  the terminal that answers the query is your local one, so `pbvar` returns the
  clipboard of the machine you are sitting at.

The OSC 52 read needs a terminal that answers clipboard-read queries. Ghostty
(`clipboard-read = allow`) and iTerm2 (`AllowClipboardAccess`) do. Under tmux,
the server needs `allow-passthrough on`. A terminal that refuses returns a clear
timeout error rather than hanging.

## Trailing newline

By default `pbvar` strips one trailing newline (`\n` or `\r\n`), the usual case
of a value copied with a stray line break. `--raw` keeps the clipboard bytes
exactly.

## Install and build

No install script, no binaries in git. CI (`.github/workflows/pbvar-build.yaml`)
cross-compiles the three arches and publishes them as GitHub Release assets when a
`pbvar-v*` tag is pushed. chezmoi then fetches the arch-matched asset to
`~/.local/bin/pbvar` via `home/.chezmoiexternal.toml` (gated on the zsh component);
the wrapper lives in `home/dot_zsh/aliases`. No Go toolchain is needed on the
target machine.

Release flow: push a `pbvar-v<x.y.z>` tag, let CI publish the release, then bump
`$pbvarTag` in `home/.chezmoiexternal.toml` and run `chezmoi apply`. To cross-build
locally (into the gitignored `dist/`):

```sh
bash tools/pbvar/build.sh     # -> tools/pbvar/dist/pbvar_<os>_<arch>
go test ./...                 # from tools/pbvar
```

## Limits

A headless machine with no OSC 52-capable terminal has no clipboard to read;
`pbvar` reports that rather than pretending to succeed. There is no copy
direction and no explicit-value mode: this is clipboard-to-env-var only.
