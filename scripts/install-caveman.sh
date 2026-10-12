#!/usr/bin/env bash
# Install the pinned CLI and its signed runtime bundle without enabling routing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[[ "${INSTALL_AI_CAVEMAN:-false}" == true ]] || exit 0
[[ "${DOTFILES_NODE_READY:-true}" == true ]] || die "Caveman requires Node.js 24+"
target=$(package_target npm @caveman-ai/cli)
[[ "$target" == 2.1.0 ]] || die "Caveman expected pinned CLI version 2.1.0"
npm install -g --prefix "$HOME/.local" "@caveman-ai/cli@$target"
# CLI 2.1.0 pins bin-v2.1.0 and verifies the signed manifest and asset checksums.
DO_NOT_TRACK=1 "$HOME/.local/bin/caveman" setup --install
for binary in caveman-proxy caveman-engine caveman-mcp; do
    [[ -x "$HOME/.caveman/bin/$binary" ]] || die "Caveman runtime missing: $binary"
done
