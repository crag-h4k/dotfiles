#!/usr/bin/env bash
# scripts/install-notify.sh
# Standalone installer for JUST the attention-notification subsystem, copied from
# this repo's source files into your home - for a machine that does NOT use the
# full chezmoi dotfiles. If you run `chezmoi apply`, notify is already installed
# (to ~/.zsh/custom/functions); do NOT also run this, or it loads twice. Pass
# --force to override that guard and to overwrite an existing notify.yaml.
#
# Installs to the same layout as the beholder coworker package:
#   ~/.config/notify/{notify.yaml,lib.sh,notify-process.zsh,sounds/*.mp3}
#   ~/.tmux/conf.d/notify.conf
#   ~/.claude/hooks/notify-{tmux,clear}.sh
# and wires ~/.zshrc, ~/.tmux.conf, ~/.claude/settings.json.
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
    cp "$REPO/dot_config/notify/notify.yaml" "$HOME/.config/notify/notify.yaml"
    info "installed notify.yaml"
fi

cp "$REPO/dot_config/notify/lib.sh"                       "$HOME/.config/notify/lib.sh"
cp "$REPO/dot_zsh/custom/functions/notify-process.zsh"    "$HOME/.config/notify/notify-process.zsh"
cp "$REPO/dot_tmux/conf.d/notify.conf"                    "$HOME/.tmux/conf.d/notify.conf"
cp "$REPO"/dot_config/notify/sounds/*.mp3                 "$HOME/.config/notify/sounds/" 2>/dev/null || warn "no sound files copied"
cp "$REPO/dot_claude/hooks/executable_notify-tmux.sh"     "$HOME/.claude/hooks/notify-tmux.sh"
cp "$REPO/dot_claude/hooks/executable_notify-clear.sh"    "$HOME/.claude/hooks/notify-clear.sh"
chmod +x "$HOME/.claude/hooks/notify-tmux.sh" "$HOME/.claude/hooks/notify-clear.sh"
info "copied lib + zsh notifier + tmux render + sounds + claude hooks"

# --- wire-ups (idempotent) ----------------------------------------------------
ensure_line '[ -f ~/.config/notify/notify-process.zsh ] && source ~/.config/notify/notify-process.zsh' "$HOME/.zshrc"
ensure_line 'source-file ~/.tmux/conf.d/notify.conf' "$HOME/.tmux.conf"
warn "notify.conf overrides window-status-format / pane-border-format. If you customize your tmux status bar, review ~/.tmux/conf.d/notify.conf and reconcile."

# --- Claude settings merge (reuse the chezmoi modify_ merger; validate first) --
SETTINGS="$HOME/.claude/settings.json"
MERGE="$REPO/dot_claude/modify_settings.json"
if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found; skipped Claude settings merge. Run later: python3 $MERGE < $SETTINGS > tmp && mv tmp $SETTINGS"
elif [[ -f "$SETTINGS" ]]; then
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SETTINGS" >/dev/null 2>&1; then
        warn "$SETTINGS is not valid JSON; skipped the hook merge (fix it, then re-run)."
    else
        cp "$SETTINGS" "$SETTINGS.bak"
        tmp=$(mktemp)
        if python3 "$MERGE" < "$SETTINGS" > "$tmp"; then
            mv "$tmp" "$SETTINGS"
            info "merged notify hooks into ~/.claude/settings.json (backup at settings.json.bak)"
        else
            rm -f "$tmp"
            warn "settings merge failed; left ~/.claude/settings.json unchanged"
        fi
    fi
else
    if printf '{}\n' | python3 "$MERGE" > "$SETTINGS"; then
        info "created ~/.claude/settings.json with notify hooks"
    else
        rm -f "$SETTINGS"
        warn "could not create ~/.claude/settings.json"
    fi
fi

cat <<'EOF'

Done. Next steps:
  - Reload tmux:        tmux source-file ~/.tmux.conf
  - Open a new shell    (so the zsh notifier loads its tables)
  - Restart Claude Code (so it re-reads ~/.claude/settings.json)

Notes:
  - tmux-only by design: notifications fire only inside a tmux session.
  - Edit ~/.config/notify/notify.yaml to change colors, sounds, groups, thresholds.
  - Debug: set "debug: true" in notify.yaml (or export NOTIFY_DEBUG=1), then
    tail -f ~/.config/notify/notify.log  (self-caps at ~1 MB).
EOF
