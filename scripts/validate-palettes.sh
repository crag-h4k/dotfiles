#!/usr/bin/env bash
# scripts/validate-palettes.sh
# Render every palette consumer and validate its native file format.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

for palette in dracula catppuccin-mocha gruvbox-dark tokyo-night; do
    cfg="$TMP_DIR/$palette.toml"
    printf '[data]\npalette = "%s"\nzshTheme = "gud"\n' "$palette" > "$cfg"

    render() {
        chezmoi execute-template --config "$cfg" < "$REPO_DIR/$1"
    }

    render dot_config/ghostty/themes/dotfiles.conf.tmpl > "$TMP_DIR/ghostty.conf"
    [[ "$(grep -c '^palette = ' "$TMP_DIR/ghostty.conf")" -eq 16 ]]
    grep -q '^background = #[0-9a-fA-F]\{6\}$' "$TMP_DIR/ghostty.conf"

    render dot_config/notify/notify.yaml.tmpl > "$TMP_DIR/notify.yaml"
    yq '.' "$TMP_DIR/notify.yaml" >/dev/null

    render dot_config/iterm2/dotfiles.json.tmpl > "$TMP_DIR/iterm2.json"
    jq -e '.Profiles | length == 2' "$TMP_DIR/iterm2.json" >/dev/null
    jq -e '[.Profiles[].Name] == ["dotfiles", "dotfiles opaque"]' "$TMP_DIR/iterm2.json" >/dev/null

    render dot_codex/themes/dotfiles.tmTheme.tmpl > "$TMP_DIR/dotfiles.tmTheme"
    python3 -c 'import plistlib,sys; plistlib.load(open(sys.argv[1], "rb"))' "$TMP_DIR/dotfiles.tmTheme"

    render dot_config/statusline/palette.sh.tmpl > "$TMP_DIR/palette.sh"
    bash -n "$TMP_DIR/palette.sh"

    render dot_config/nvim/lua/dotfiles_palette.lua.tmpl > "$TMP_DIR/dotfiles_palette.lua"
    command -v luac >/dev/null 2>&1 && luac -p "$TMP_DIR/dotfiles_palette.lua"

    render dot_zsh/theme.zsh.tmpl > "$TMP_DIR/theme.zsh"
    zsh -n "$TMP_DIR/theme.zsh"

    render dot_tmux/conf.d/status.conf.tmpl > "$TMP_DIR/status.conf"
    grep -q '^set -g status-bg "#[0-9a-fA-F]\{6\}"$' "$TMP_DIR/status.conf"
done

printf 'validate-palettes: OK - 4 palettes render for Ghostty, notify, iTerm2, Codex, Claude, Neovim, Zsh, and tmux\n'
