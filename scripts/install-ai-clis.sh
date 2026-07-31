#!/usr/bin/env bash
# Install the two terminal agents configured by the shared AI workspace.
# Both vendor installers are user-local and require neither root nor sudo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

install_vendor_cli() {
    local label="$1" command_name="$2" url="$3" interpreter="$4"
    local temp_dir installer

    if command -v "$command_name" >/dev/null 2>&1; then
        info "$label: already installed; keeping the existing installation"
        return 0
    fi

    require_cmd curl
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ai-cli.XXXXXXXX")
    installer="$temp_dir/install.sh"

    info "installing $label from its official standalone installer"
    if ! curl -fsSL "$url" -o "$installer"; then
        rm -f "$installer"
        rmdir "$temp_dir" 2>/dev/null || true
        warn "$label installer download failed"
        return 1
    fi
    if ! "$interpreter" "$installer"; then
        rm -f "$installer"
        rmdir "$temp_dir" 2>/dev/null || true
        warn "$label installer failed"
        return 1
    fi
    rm -f "$installer"
    rmdir "$temp_dir" 2>/dev/null || true
}

failed=0

install_vendor_cli \
    "Claude Code" \
    claude \
    "https://claude.ai/install.sh" \
    bash || failed=1

install_vendor_cli \
    "Codex CLI" \
    codex \
    "https://chatgpt.com/codex/install.sh" \
    sh || failed=1

exit "$failed"
