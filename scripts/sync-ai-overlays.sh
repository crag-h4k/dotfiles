#!/usr/bin/env bash
# Re-scan ~/ai/overlays.conf and link each configured entry into Claude/Codex.

set -euo pipefail

invoked_path="${BASH_SOURCE[0]}"
ai_dir="${DOTFILES_AI_DIR:-}"
if [[ -z "$ai_dir" && -L "$invoked_path" ]]; then
    ai_dir="$(cd "$(dirname "$invoked_path")/.." && pwd)"
fi
ai_dir="${ai_dir:-$HOME/ai}"

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'sync-ai-overlays: required command not found: %s\n' "$1" >&2
        exit 1
    }
}

require_command chezmoi
source_root="$(chezmoi source-path)"
repo_dir="$(cd "$source_root/.." && pwd)"
installer="$repo_dir/scripts/install-ai-workspace.sh"
[[ -f "$installer" ]] || {
    printf 'sync-ai-overlays: installer not found: %s\n' "$installer" >&2
    exit 1
}

export DOTFILES_AI_DIR="$ai_dir"
export AI_OVERLAY_SYNC_ONLY=true
bash "$installer"
