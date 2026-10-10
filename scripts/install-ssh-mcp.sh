#!/usr/bin/env bash
# Install the pinned SSH MCP binary; host profiles stay private and unmanaged.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[[ "${INSTALL_AI_SSH_MCP:-false}" == true ]] || exit 0
[[ "${DOTFILES_NODE_READY:-true}" == true ]] || die "SSH MCP requires Node.js 24+"
command -v npm >/dev/null 2>&1 || die "SSH MCP requires npm"

target=$(package_target npm ssh-mcp)
[[ "$target" == 2.18.0 ]] || die "SSH MCP expected pinned version 2.18.0"
npm install -g --prefix "$HOME/.local" "ssh-mcp@$target"
