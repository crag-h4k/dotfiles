<!-- docs/palettes.md -->
# Palette catalog

The shared color palette that themes every terminal surface. One selection
(`data.palette`) drives Ghostty, iTerm2, tmux, notify, the Claude statusline, the
Codex theme, and Neovim, so they stay in lockstep.

## Table of Contents

- [How it works](#how-it-works)
- [What determines the palettes](#what-determines-the-palettes)
- [When to run the generator](#when-to-run-the-generator)
- [base16 to semantic mapping](#base16-to-semantic-mapping)
- [Add a scheme](#add-a-scheme)
- [Command line](#command-line)
- [Submodule setup](#submodule-setup)

## How it works

`home/.chezmoidata/palettes.yaml` is the committed catalog. Each entry holds the raw 16
base16 colors, the semantic keys the consumers read, a 16-entry ANSI array, and the
notify tints. `scripts/build-palettes.py` generates that file from the
`tinted-theming/schemes` collection, vendored as the `vendor/tinted-schemes` git
submodule.

The generator runs at authoring time and its output is committed. `chezmoi apply` only
renders the committed YAML, so it works on a bare machine that never fetched the submodule
or ran the generator. Neovim reads the same 16 colors through `RRethy/base16-nvim`, so its
syntax matches the terminal ANSI byte for byte.

## What determines the palettes

The `CURATED` list in `scripts/build-palettes.py`. Each row is
`(output_id, display_name, source_scheme_file)`:

- `output_id` is what `data.palette` stores and what the picker shows.
- `display_name` is the label in the picker.
- `source_scheme_file` is the base16 or base24 YAML under the submodule.

The submodule carries the full collection (hundreds of schemes); only the rows in
`CURATED` are materialized into the catalog and validated. The first row is the
default (`dracula`). `gruvbox-dark` and `tokyo-night` keep their historical ids so a
persisted `data.palette` never breaks, while sourcing from the tinted-theming files
named in the list.

## When to run the generator

Authoring time only, never at `chezmoi apply` or `init`. Run it when you:

- edit the `CURATED` list (add, remove, or repoint a scheme), or
- bump the `vendor/tinted-schemes` submodule to a newer upstream commit.

There is no schedule. CI runs `build-palettes.py --check` on every push and fails if
the committed catalog drifted from a fresh generation, so a stale commit is caught
without regenerating on every host. The same `--check` runs as a local pre-commit
hook and skips itself when the submodule is not initialized.

## base16 to semantic mapping

| Semantic key | base16 source | Notes |
| --- | --- | --- |
| background | base00 | |
| surface | base01 | falls back to base02 when base01 is darker than base00 |
| selection | base02 | |
| comment | base03 | |
| foreground / cursor / white | base05 | |
| black | base00 | |
| red / green / yellow | base08 / base0B / base0A | |
| blue / cyan | base0D / base0C | |
| purple / pink | base0E | base16 has no separate pink |
| orange | base09 | |

ANSI normal 0-7 map to base00, base08, base0B, base0A, base0D, base0E, base0C,
base05. ANSI bright 8-15 anchor the ends with base03 and base07; the middle brights
use the base24 bright slots when the source is base24, otherwise the normals
lightened about 12% in HLS. Notify tints blend each accent toward base00 and darken
until the accent clears roughly 3:1 contrast against the tint.

## Add a scheme

1. Find the scheme id under `vendor/tinted-schemes/base16/` or `base24/`.
2. Add a row to `CURATED` in `scripts/build-palettes.py`.
3. Regenerate, then commit the changed `home/.chezmoidata/palettes.yaml` and
   `home/.chezmoi.toml.tmpl`:

   ```sh
   python3 scripts/build-palettes.py
   ```

Removing a scheme is the same edit in reverse. `validate-palettes.sh` renders every
catalog entry across all consumers, so a broken scheme fails pre-commit.

## Command line

```sh
# regenerate after editing CURATED or bumping the submodule
python3 scripts/build-palettes.py

# CI drift gate (skips if the submodule is absent)
python3 scripts/build-palettes.py --check

# generate from a checkout outside the submodule path
python3 scripts/build-palettes.py --schemes-dir /path/to/tinted-theming-schemes
```

`--out` and `--toml` override the catalog and the config template the picker list is
written into. `python3 scripts/build-palettes.py --help` prints the same examples.

## Submodule setup

```sh
git -C ~/.local/share/chezmoi submodule add \
  https://github.com/tinted-theming/schemes vendor/tinted-schemes
python3 ~/.local/share/chezmoi/scripts/build-palettes.py
```

`vendor/` is ignored by chezmoi (never written into `~`) and excluded from lint. CI
checks out submodules so `--check` can verify the catalog.
