#!/usr/bin/env bash
# scripts/install-notify.sh
# Standalone installer for JUST the attention-notification subsystem, copied from
# this repo's source files into your home - for a machine that does NOT use the
# full chezmoi dotfiles. If you run `chezmoi apply`, notify is already installed
# (to ~/.zsh/custom/functions); do NOT also run this, or it loads twice. Pass
# --force to override that guard and to overwrite an existing notify.yaml.
#
# Installs to this layout:
#   ~/.config/notify/{notify.yaml,lib.sh,notify-process.zsh,sounds/*.mp3}
#   ~/.tmux/conf.d/notify.conf
#   ~/.claude/hooks/notify-{tmux,clear}.sh
#   ~/.codex/hooks/notify-tmux.sh        (only when the codex CLI is present)
# and wires ~/.zshrc, ~/.tmux.conf, ~/.claude/settings.json, ~/.codex/config.toml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# Guard against running alongside the chezmoi-managed install (which puts the zsh
# notifier at ~/.zsh/custom/functions and would double-load with this one).
if [[ -f "$HOME/.zsh/custom/functions/notify-process.zsh" && "$FORCE" -ne 1 ]]; then
    die "notify looks chezmoi-managed (~/.zsh/custom/functions/notify-process.zsh exists). Use 'chezmoi apply' instead, or pass --force to install the standalone copy anyway."
fi

os=$(os_detect)
[[ "$os" == unsupported ]] && die "unsupported OS $(uname -s); this targets macOS and Debian"
info "standalone notify installer: platform=$os"

ensure_yq

# --- copy from the repo's chezmoi-source files (single source of truth) --------
mkdir -p "$HOME/.config/notify/sounds" "$HOME/.tmux/conf.d" "$HOME/.claude/hooks"

# notify.yaml: preserve user edits unless --force.
if [[ -f "$HOME/.config/notify/notify.yaml" && "$FORCE" -ne 1 ]]; then
    info "kept existing notify.yaml (pass --force to overwrite)"
else
    palette="$REPO/.chezmoidata/palettes.yaml"
    template="$REPO/dot_config/notify/notify.yaml.tmpl"
    # Standalone installs use Dracula. Resolve the same canonical values without
    # requiring chezmoi to render the Go template.
    sed \
        -e '/{{- \$p :=/d' \
        -e "s@{{ \$p.notify.dark_red | quote }}@\"$(yq -r '.palettes.dracula.notify.dark_red' "$palette")\"@" \
        -e "s@{{ \$p.notify.dark_purple | quote }}@\"$(yq -r '.palettes.dracula.notify.dark_purple' "$palette")\"@" \
        -e "s@{{ \$p.notify.dark_green | quote }}@\"$(yq -r '.palettes.dracula.notify.dark_green' "$palette")\"@" \
        -e "s@{{ \$p.notify.dark_orange | quote }}@\"$(yq -r '.palettes.dracula.notify.dark_orange' "$palette")\"@" \
        -e "s@{{ \$p.notify.dark_cyan | quote }}@\"$(yq -r '.palettes.dracula.notify.dark_cyan' "$palette")\"@" \
        -e "s@{{ \$p.notify.dark_pink | quote }}@\"$(yq -r '.palettes.dracula.notify.dark_pink' "$palette")\"@" \
        -e "s@{{ \$p.colors.red | quote }}@\"$(yq -r '.palettes.dracula.colors.red' "$palette")\"@" \
        -e "s@{{ \$p.colors.purple | quote }}@\"$(yq -r '.palettes.dracula.colors.purple' "$palette")\"@" \
        -e "s@{{ \$p.colors.green | quote }}@\"$(yq -r '.palettes.dracula.colors.green' "$palette")\"@" \
        -e "s@{{ \$p.colors.orange | quote }}@\"$(yq -r '.palettes.dracula.colors.orange' "$palette")\"@" \
        -e "s@{{ \$p.colors.cyan | quote }}@\"$(yq -r '.palettes.dracula.colors.cyan' "$palette")\"@" \
        -e "s@{{ \$p.colors.pink | quote }}@\"$(yq -r '.palettes.dracula.colors.pink' "$palette")\"@" \
        "$template" > "$HOME/.config/notify/notify.yaml"
    info "installed notify.yaml"
fi

cp "$REPO/dot_config/notify/lib.sh"                       "$HOME/.config/notify/lib.sh"
cp "$REPO/dot_config/notify/executable_clear-pane.sh"     "$HOME/.config/notify/clear-pane.sh"
cp "$REPO/dot_zsh/custom/functions/notify-process.zsh"    "$HOME/.config/notify/notify-process.zsh"
cp "$REPO/dot_tmux/conf.d/notify.conf"                    "$HOME/.tmux/conf.d/notify.conf"
cp "$REPO"/dot_config/notify/sounds/*.mp3                 "$HOME/.config/notify/sounds/" 2>/dev/null || warn "no sound files copied"
cp "$REPO/dot_claude/hooks/executable_notify-tmux.sh"     "$HOME/.claude/hooks/notify-tmux.sh"
cp "$REPO/dot_claude/hooks/executable_notify-clear.sh"    "$HOME/.claude/hooks/notify-clear.sh"
chmod +x "$HOME/.claude/hooks/notify-tmux.sh" "$HOME/.claude/hooks/notify-clear.sh"
chmod +x "$HOME/.config/notify/clear-pane.sh"
info "copied lib + zsh notifier + tmux render + sounds + claude hooks"

# --- wire-ups (idempotent) ----------------------------------------------------
ensure_line '[ -f ~/.config/notify/notify-process.zsh ] && source ~/.config/notify/notify-process.zsh' "$HOME/.zshrc"
ensure_line 'source-file ~/.tmux/conf.d/notify.conf' "$HOME/.tmux.conf"
warn "notify.conf overrides window-status-format / pane-border-format. If you customize your tmux status bar, review ~/.tmux/conf.d/notify.conf and reconcile."

# The two modify_ mergers are chezmoi Go templates (modify_*.tmpl) whose notify
# blocks are gated on ai > claude_hooks / codex_hooks and whose statusline block is
# gated on ai > statusline. Standalone has no chezmoi to render them, so resolve the
# gates here for the notify path (hooks ON, statusline OFF) with a tiny line-based
# renderer, then run the resulting Python merge script exactly as before.
render_modify() { # $1 = modify_*.tmpl -> rendered Python merge script on stdout
    python3 - "$1" <<'PY'
import re, sys
GATES = {"claude_hooks": True, "codex_hooks": True, "statusline": False}
if_re = re.compile(r'\{\{-?\s*if\s+dig\s+"components"\s+"ai"\s+"(\w+)".*?\}\}')
end_re = re.compile(r'\{\{-?\s*end\s*-?\}\}')
stack, skip, out = [], 0, []
with open(sys.argv[1]) as f:
    for line in f:
        m = if_re.search(line)
        if m:
            on = GATES.get(m.group(1), False)
            stack.append(on)
            if not on:
                skip += 1
            continue
        if end_re.search(line):
            if stack and not stack.pop():
                skip -= 1
            continue
        if skip == 0:
            out.append(line)
sys.stdout.write("".join(out))
PY
}

# --- Claude settings merge (render the chezmoi modify_ template; validate first) --
SETTINGS="$HOME/.claude/settings.json"
MERGE_TMPL="$REPO/dot_claude/modify_settings.json.tmpl"
if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found; skipped Claude settings merge (the merger is a chezmoi template that needs python to render + run)."
elif [[ -f "$SETTINGS" ]] && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SETTINGS" >/dev/null 2>&1; then
    warn "$SETTINGS is not valid JSON; skipped the hook merge (fix it, then re-run)."
else
    MERGE=$(mktemp)
    render_modify "$MERGE_TMPL" > "$MERGE"
    if [[ -f "$SETTINGS" ]]; then
        cp "$SETTINGS" "$SETTINGS.bak"
        tmp=$(mktemp)
        if python3 "$MERGE" < "$SETTINGS" > "$tmp"; then
            mv "$tmp" "$SETTINGS"
            info "merged notify hooks into ~/.claude/settings.json (backup at settings.json.bak)"
        else
            rm -f "$tmp"
            warn "settings merge failed; left ~/.claude/settings.json unchanged"
        fi
    else
        if printf '{}\n' | python3 "$MERGE" > "$SETTINGS"; then
            info "created ~/.claude/settings.json with notify hooks"
        else
            rm -f "$SETTINGS"
            warn "could not create ~/.claude/settings.json"
        fi
    fi
    rm -f "$MERGE"
fi

# --- Codex hook + config merge (only when the codex CLI is present) ------------
# Codex's external notify program only ever receives agent-turn-complete, so this
# is the turn-complete color+sound flag. The merge also adds tui.notifications
# (Codex's built-in approval alert; a no-op under tmux today per openai/codex#16855,
# active once that lands). config.toml is merged, not overwritten, so Codex's
# [projects.*] trust and [tui.*] entries survive; mode stays 600.
if command -v codex >/dev/null 2>&1; then
    mkdir -p "$HOME/.codex/hooks"
    cp "$REPO/dot_codex/hooks/executable_notify-tmux.sh" "$HOME/.codex/hooks/notify-tmux.sh"
    chmod +x "$HOME/.codex/hooks/notify-tmux.sh"
    info "installed codex notify hook (~/.codex/hooks/notify-tmux.sh)"
    CODEX_CFG="$HOME/.codex/config.toml"
    CODEX_MERGE_TMPL="$REPO/dot_codex/modify_private_config.toml.tmpl"
    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 not found; skipped Codex config merge (the merger is a chezmoi template that needs python to render + run)."
    else
        CODEX_MERGE=$(mktemp)
        render_modify "$CODEX_MERGE_TMPL" > "$CODEX_MERGE"
        tmpc=$(mktemp)
        if [[ -f "$CODEX_CFG" ]]; then
            ok=$(python3 "$CODEX_MERGE" < "$CODEX_CFG" > "$tmpc" && echo 1 || echo 0)
        else
            ok=$(python3 "$CODEX_MERGE" < /dev/null > "$tmpc" && echo 1 || echo 0)
        fi
        if [[ "$ok" == 1 ]]; then
            [[ -f "$CODEX_CFG" ]] && cp "$CODEX_CFG" "$CODEX_CFG.bak"
            mv "$tmpc" "$CODEX_CFG"
            chmod 600 "$CODEX_CFG"
            info "merged notify + tui.notifications into ~/.codex/config.toml (mode 600)"
        else
            rm -f "$tmpc"
            warn "codex config merge failed; left ~/.codex/config.toml unchanged"
        fi
        rm -f "$CODEX_MERGE"
    fi
else
    info "codex CLI not found; skipped Codex notify wiring"
fi

cat <<'EOF'

Done. Next steps:
  - Reload tmux:        tmux source-file ~/.tmux.conf
  - Open a new shell    (so the zsh notifier loads its tables)
  - Restart Claude Code (so it re-reads ~/.claude/settings.json)
  - Restart Codex      (so it re-reads ~/.codex/config.toml), if installed

Notes:
  - tmux-only by design: notifications fire only inside a tmux session.
  - Edit ~/.config/notify/notify.yaml to change colors, sounds, groups, thresholds.
  - Debug: set "debug: true" in notify.yaml (or export NOTIFY_DEBUG=1), then
    tail -f ~/.config/notify/notify.log  (self-caps at ~1 MB).
EOF
