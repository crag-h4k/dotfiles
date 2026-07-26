<!-- docs/palettes.md -->
# Palette catalog

One palette selection drives Ghostty, iTerm2, tmux, notifications, Claude,
Codex, and Neovim. The point is to change the colors once and avoid seven
nearly-matching copies.

## Table of Contents

- [How it works](#how-it-works)
- [What determines the palettes](#what-determines-the-palettes)
- [When to run the generator](#when-to-run-the-generator)
- [base16 to semantic mapping](#base16-to-semantic-mapping)
- [Add a scheme](#add-a-scheme)
- [Command line](#command-line)
- [Submodule setup](#submodule-setup)

## How it works

`home/.chezmoidata/palettes.yaml` is the committed catalog. Each entry contains
the raw base16 colors, semantic keys, a 16-color ANSI array, and notification
tints.

`scripts/build-palettes.py` generates it from the `tinted-theming/schemes`
collection in the `vendor/tinted-schemes` submodule.

The generator is an authoring tool. `chezmoi apply` consumes the committed
YAML, so a new machine can render colors without the submodule, Python, or a
network connection.

Neovim reads the same 16 colors through `RRethy/base16-nvim`, keeping its
syntax colors aligned with the terminal ANSI palette.

## What determines the palettes

The `CURATED` list in `scripts/build-palettes.py`. Each row is
`(output_id, display_name, source_scheme_file)`:

- `output_id` is what `data.palette` stores and what the picker shows.
- `display_name` is the label in the picker.
- `source_scheme_file` is the base16 or base24 YAML under the submodule.

The submodule contains hundreds of schemes. Only rows in `CURATED` are emitted
and validated. The first row, `dracula`, is the default.

`gruvbox-dark` and `tokyo-night` retain their historical IDs so existing
`data.palette` values keep working.

## When to run the generator

Authoring time only, never at `chezmoi apply` or `init`. Run it when you:

- edit the `CURATED` list (add, remove, or repoint a scheme), or
- bump the `vendor/tinted-schemes` submodule to a newer upstream commit.

There is no regeneration schedule. CI runs `build-palettes.py --check` and
fails when the committed catalog differs from fresh output. The same check runs
in pre-commit and skips itself if the submodule is not initialized.

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

ANSI normal 0–7 map to base00, base08, base0B, base0A, base0D, base0E, base0C,
and base05. ANSI bright 8–15 anchor the ends with base03 and base07.

Middle bright colors use base24 slots when available. For base16 sources, the
normal colors are lightened by about 12% in HLS.

Notification tints blend each accent toward base00, then darken until the
accent reaches roughly 3:1 contrast against the tint.

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
