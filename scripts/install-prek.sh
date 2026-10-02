# shellcheck shell=bash
# scripts/install-prek.sh
# Install the pinned prek hook runner on Debian through Astral uv.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

PREK_VERSION="${PREK_VERSION:-0.5.4}"

if [[ "$(os_detect)" != debian ]]; then
    exit 0
fi

if [[ -x "$HOME/.local/bin/prek" ]] && \
    [[ "$("$HOME/.local/bin/prek" --version 2>/dev/null | awk '{print $2}')" == "$PREK_VERSION" ]]; then
    info "prek $PREK_VERSION is current"
    exit 0
fi

install_uv_debian
uv_bin="$(command -v uv)"
"$uv_bin" tool install --force "prek==$PREK_VERSION"

have="$("$HOME/.local/bin/prek" --version 2>/dev/null | awk '{print $2}')"
[[ "$have" == "$PREK_VERSION" ]] || {
    warn "prek version ${have:-unknown} does not match required $PREK_VERSION"
    exit 1
}
