#!/usr/bin/env bash
# Shared helpers for dotfiles install scripts. Source, do not exec.

set -euo pipefail

die() { printf 'dotfiles: %s\n' "$*" >&2; exit 1; }
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

# Install chezmoi to ~/.local/bin if it is not already in PATH.
ensure_chezmoi() {
    if command -v chezmoi >/dev/null 2>&1; then
        info "chezmoi already in PATH: $(command -v chezmoi)"
        return 0
    fi
    info "chezmoi not found - installing to ~/.local/bin"
    mkdir -p "$HOME/.local/bin"
    local os
    os=$(os_detect)
    case "$os" in
        macos)
            require_cmd brew
            brew install chezmoi
            ;;
        debian)
            require_cmd curl
            sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
            ;;
        *)
            warn "unsupported OS: $(uname -s) - install chezmoi manually"
            return 1
            ;;
    esac
}

# Install the latest tagged neovim release from GitHub, system-wide.
# Removes the apt package if an older version is installed.
# Installs to /opt/nvim with a symlink at /usr/local/bin/nvim (all users).
install_neovim_debian() {
    local major=0 minor=0
    if command -v nvim >/dev/null 2>&1; then
        local ver_line
        ver_line=$(nvim --version 2>/dev/null | head -1)
        if [[ "$ver_line" =~ NVIM[[:space:]]v([0-9]+)\.([0-9]+) ]]; then
            major="${BASH_REMATCH[1]}"
            minor="${BASH_REMATCH[2]}"
        fi
        if (( major > 0 || minor >= 11 )); then
            info "neovim ${major}.${minor} already >= 0.11, skipping"
            return 0
        fi
        info "neovim ${major}.${minor} < 0.11; removing apt package"
        sudo apt-get remove -y neovim 2>/dev/null || true
    fi

    local arch
    case "$(uname -m)" in
        x86_64)        arch="x86_64" ;;
        aarch64|arm64) arch="arm64"  ;;
        *)
            warn "unsupported arch $(uname -m) for prebuilt neovim; install manually"
            return 1
            ;;
    esac

    require_cmd curl
    info "fetching latest neovim release tag from GitHub"
    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/neovim/neovim/releases/latest" \
        | awk -F'"' '/tag_name/{print $4; exit}')
    [[ -n "$tag" ]] || { warn "could not determine latest neovim release tag"; return 1; }
    info "installing neovim ${tag} (${arch}) to /opt/nvim"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    curl -L --fail -o "$tmp_dir/nvim.tar.gz" \
        "https://github.com/neovim/neovim/releases/download/${tag}/nvim-linux-${arch}.tar.gz"
    tar -xzf "$tmp_dir/nvim.tar.gz" -C "$tmp_dir"

    sudo rm -rf /opt/nvim
    sudo mv "$tmp_dir/nvim-linux-${arch}" /opt/nvim
    sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim

    # Remove any user-local nvim left by a previous version of this script.
    rm -f "$HOME/.local/bin/nvim"

    rm -rf "$tmp_dir"
    info "neovim ${tag} installed: $(nvim --version 2>/dev/null | head -1)"
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
