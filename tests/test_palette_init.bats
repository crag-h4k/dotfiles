#!/usr/bin/env bats
# tests/test_palette_init.bats
# Exercise the palette selection + validation in .chezmoi.toml.tmpl the way a real
# `chezmoi init` renders it: via `chezmoi execute-template --init` (the same engine
# init uses, and the pattern scripts/validate-templates.sh already relies on). A
# full `chezmoi init` cannot run headless here - its component promptStringOnce
# opens /dev/tty on first init with no persisted value - so execute-template --init
# is the deterministic, side-effect-free way to drive the same template logic.
# DOTFILES_INSTALL_MODE=configs always, so no path can reach a real package install.

CHEZMOI_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
CONFIG_TMPL="${CHEZMOI_DIR}/.chezmoi.toml.tmpl"

setup() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  SEED="${BATS_TEST_TMPDIR}/seed.toml"
}

# render_palette <DOTFILES_PALETTE value> [seed palette in config]
# componentSelection is pre-seeded so the component promptStringOnce returns it
# instead of trying to open a TTY; DOTFILES_NO_TUI keeps the palette prompt off.
render_palette() {
  {
    printf '[data]\n    componentSelection = "1 2 3"\n'
    if [ -n "${2:-}" ]; then
      printf '    palette = "%s"\n' "$2"
    fi
  } > "$SEED"
  run env DOTFILES_NO_TUI=1 DOTFILES_INSTALL_MODE=configs DOTFILES_PALETTE="$1" \
    chezmoi execute-template --init --config "$SEED" < "$CONFIG_TMPL"
}

@test "palette: valid ID renders as-is" {
  render_palette "catppuccin-mocha"
  [ "$status" -eq 0 ]
  [[ "$output" == *'palette = "catppuccin-mocha"'* ]]
}

@test "palette: friendly name with spaces/casing normalizes to the ID" {
  render_palette "Tokyo Night"
  [ "$status" -eq 0 ]
  [[ "$output" == *'palette = "tokyo-night"'* ]]
}

@test "palette: mixed-case ID with underscores normalizes" {
  render_palette "Gruvbox_Dark"
  [ "$status" -eq 0 ]
  [[ "$output" == *'palette = "gruvbox-dark"'* ]]
}

@test "palette: invalid input fails loudly (no silent fallback)" {
  render_palette "boguspalette"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown palette"* ]]
  [[ "$output" != *'palette = "dracula"'* ]]
}

@test "palette: no input with no persisted value falls back to dracula" {
  render_palette ""
  [ "$status" -eq 0 ]
  [[ "$output" == *'palette = "dracula"'* ]]
}

@test "palette: no input falls back to the persisted value" {
  render_palette "" "gruvbox-dark"
  [ "$status" -eq 0 ]
  [[ "$output" == *'palette = "gruvbox-dark"'* ]]
}
