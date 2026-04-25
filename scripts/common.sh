#!/usr/bin/env bash
# Shared helpers for tilde's install scripts. Source, do not exec.

set -euo pipefail

die() { printf 'tilde: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

# os_detect → "macos" | "debian" | "unsupported"
os_detect() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                echo "debian"
            else
                echo "unsupported"
            fi
            ;;
        *) echo "unsupported" ;;
    esac
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# Platform-aware package install wrapper.
# Usage: pkg_install pkg1 pkg2 ...
pkg_install() {
    local os
    os=$(os_detect)
    case "$os" in
        macos)
            require_cmd brew
            brew install "$@"
            ;;
        debian)
            sudo apt-get update
            sudo apt-get install -y "$@"
            ;;
        *)
            die "unsupported OS: $(uname -s)"
            ;;
    esac
}
