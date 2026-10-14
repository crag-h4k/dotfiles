#!/usr/bin/env bash
# scripts/ai-setup-notice.sh
# Read-only post-apply reminder for selected AI services that still need private
# setup. It never configures or starts a service and never prints private values.
set -u

DOCS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs"
LOCAL_BIN="$HOME/.local/bin"
RED=$'\033[31m'
RESET=$'\033[0m'
if [[ -n "${NO_COLOR:-}" ]]; then
    RED=""
    RESET=""
fi

notice() {
    printf '%sdotfiles: %s%s\n' "$RED" "$1" "$RESET" >&2
}

json_field() {
    command -v python3 >/dev/null 2>&1 || return 1
    python3 -c 'import json, sys
value = json.load(open(sys.argv[1]))[sys.argv[2]]
print(str(value).lower() if isinstance(value, bool) else str(value).rstrip("/"))' "$1" "$2" 2>/dev/null
}

check_openviking() {
    local url
    if [[ ! -f "$HOME/.openviking/ov.conf" || ! -f "$HOME/.openviking/ovcli.conf" ]]; then
        notice "OpenViking is selected but not set up. Run $LOCAL_BIN/openvikingctl setup; see $DOCS_DIR/openviking.md"
        return
    fi
    if ! url=$(json_field "$HOME/.openviking/ovcli.conf" url) ||
        ! curl --fail --silent --max-time 3 "$url/ready" >/dev/null 2>&1; then
        notice "OpenViking is configured but its service is not ready. Run $LOCAL_BIN/openvikingctl enable; see $DOCS_DIR/openviking.md"
    fi
}

check_caveman() {
    local settings="$HOME/.caveman/oc2/settings.json" enabled url
    if [[ ! -f "$settings" ]]; then
        notice "Caveman is installed with OpenCode but has no private route. Run $LOCAL_BIN/cavemanctl init with your provider and upstream; see $DOCS_DIR/caveman.md"
        return
    fi
    enabled=$(json_field "$settings" enabled) || enabled=""
    # A configured but disabled proxy is a deliberate choice, not missing setup.
    [[ "$enabled" == false ]] && return
    if ! url=$(json_field "$settings" url) ||
        ! curl --fail --silent --max-time 3 "$url/health/ready" >/dev/null 2>&1; then
        notice "Caveman is configured but its proxy is not ready. Run $LOCAL_BIN/cavemanctl enable, or $LOCAL_BIN/cavemanctl disable; see $DOCS_DIR/caveman.md"
    fi
}

[[ "${INSTALL_AI_OPENVIKING:-false}" == true ]] && check_openviking
[[ "${INSTALL_AI_CAVEMAN:-false}" == true ]] && check_caveman
exit 0
