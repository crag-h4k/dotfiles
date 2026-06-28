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

apt_deb822_repo_configured() {
    local wanted_uri="$1" file
    for file in /etc/apt/sources.list.d/*.sources; do
        [[ -r "$file" ]] || continue
        awk -v wanted_uri="$wanted_uri" '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*URIs:[[:space:]]*/ {
                sub(/^[[:space:]]*URIs:[[:space:]]*/, "")
                for (i = 1; i <= NF; i++) {
                    uri = $i
                    sub(/\/$/, "", uri)
                    if (uri == wanted_uri) {
                        found = 1
                    }
                }
            }
            END { exit found ? 0 : 1 }
        ' "$file" && return 0
    done
    return 1
}

# Add the GitHub CLI apt repo on Debian if gh is not already installed.
# Safe to call multiple times; no-ops if gh is already in PATH. The caller
# owns apt-get update so package installs can stay batched.
ensure_gh_apt_repo() {
    command -v gh >/dev/null 2>&1 && return 0
    require_cmd curl
    local repo_uri="https://cli.github.com/packages"
    if apt_deb822_repo_configured "$repo_uri"; then
        info "GitHub CLI apt repo already configured"
        return 0
    fi
    info "adding GitHub CLI apt repo"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    {
        printf 'Types: deb\n'
        printf 'URIs: %s\n' "$repo_uri"
        printf 'Suites: stable\n'
        printf 'Components: main\n'
        printf 'Architectures: %s\n' "$(dpkg --print-architecture)"
        printf 'Signed-By: /usr/share/keyrings/githubcli-archive-keyring.gpg\n'
    } | sudo tee /etc/apt/sources.list.d/github-cli.sources >/dev/null
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
    local tmp_json
    tmp_json=$(mktemp)
    # Guarded (not bare) so a 403/offline does not trip set -e before the
    # graceful return below; the unauthenticated GitHub API is 60 req/hr/IP.
    if ! curl -fsSL -o "$tmp_json" "https://api.github.com/repos/neovim/neovim/releases/latest"; then
        warn "could not reach the GitHub API for the latest neovim release"
        rm -f "$tmp_json"
        return 1
    fi
    tag=$(awk -F'"' '/tag_name/{print $4; exit}' "$tmp_json")
    rm -f "$tmp_json"
    [[ -n "$tag" ]] || { warn "could not determine latest neovim release tag"; return 1; }
    info "installing neovim ${tag} (${arch}) to /opt/nvim"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    if ! curl -fSL -o "$tmp_dir/nvim.tar.gz" \
        "https://github.com/neovim/neovim/releases/download/${tag}/nvim-linux-${arch}.tar.gz"; then
        warn "neovim ${tag} download failed; leaving the existing neovim in place"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Extract directly into /usr/local (strip the top-level nvim-linux-<arch>/ prefix).
    # This puts the binary at /usr/local/bin/nvim and the runtime at
    # /usr/local/share/nvim/runtime/ - the path the binary resolves at startup.
    # A symlink would cause neovim to compute the wrong runtime root.
    sudo tar -C /usr/local --strip-components=1 -xzf "$tmp_dir/nvim.tar.gz"

    # Clean up any leftovers from the previous /opt/nvim symlink approach.
    sudo rm -rf /opt/nvim

    # Remove any user-local nvim left by an earlier version of this script.
    rm -f "$HOME/.local/bin/nvim"

    rm -rf "$tmp_dir"
    info "neovim ${tag} installed: $(nvim --version 2>/dev/null | head -1)"
}

# True if a mikefarah yq is already on PATH. The `if`-condition placement is what
# keeps callers pipefail-safe: errexit is suppressed inside an `if`, so `grep -qi`
# finding no match (or SIGPIPE-ing the upstream yq) does not abort. Keep callers
# using this inside a conditional.
have_mikefarah_yq() {
    command -v yq >/dev/null 2>&1 && yq --version 2>/dev/null | grep -qi mikefarah
}

# Fetch the mikefarah/yq binary for <os> (linux|darwin) into ~/.local/bin. apt's
# 'yq' is a different tool (python kislyuk/yq) with incompatible syntax, so we
# fetch the official binary directly - the same approach as neovim. Downloads to
# a temp file and verifies it is a working mikefarah build BEFORE moving it live,
# so a proxy/transient failure (curl -o truncates on open, even with --fail) or a
# wrong-arch download never leaves a broken executable at ~/.local/bin/yq.
fetch_yq() {
    local os="$1" arch tmp
    case "$(uname -m)" in
        x86_64)        arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)
            warn "unsupported arch $(uname -m) for prebuilt yq; install manually"
            return 1
            ;;
    esac
    require_cmd curl
    mkdir -p "$HOME/.local/bin"
    tmp=$(mktemp)
    info "fetching mikefarah yq (${os}/${arch})"
    if ! curl -fsSL --fail -o "$tmp" \
        "https://github.com/mikefarah/yq/releases/latest/download/yq_${os}_${arch}"; then
        warn "yq download failed; install manually from https://github.com/mikefarah/yq"
        rm -f "$tmp"
        return 1
    fi
    chmod +x "$tmp"
    if ! "$tmp" --version 2>/dev/null | grep -qi mikefarah; then
        warn "downloaded yq is not a working mikefarah binary; leaving existing yq untouched"
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$HOME/.local/bin/yq"
    info "yq installed: $("$HOME/.local/bin/yq" --version 2>/dev/null)"
}

# Debian: ensure mikefarah yq (binary fetch). No-op if already present. Called by
# install.sh for the tmux/zsh components.
install_yq_debian() {
    if have_mikefarah_yq; then
        info "mikefarah yq already present: $(yq --version 2>/dev/null)"
        return 0
    fi
    fetch_yq linux
}

# Ensure a mikefarah yq for the current platform: brew on macOS (binary fallback
# when Homebrew is absent), binary fetch on Debian. No-op if already present.
# Used by the standalone notify installer (scripts/install-notify.sh).
ensure_yq() {
    if have_mikefarah_yq; then
        info "mikefarah yq already present: $(yq --version 2>/dev/null)"
        return 0
    fi
    case "$(os_detect)" in
        macos)
            if command -v brew >/dev/null 2>&1; then
                info "installing yq via brew"
                brew install yq
            else
                warn "Homebrew not found; fetching the yq binary to ~/.local/bin instead"
                fetch_yq darwin || warn "no yq: notifications fall back to built-in default colors until yq is installed"
            fi
            ;;
        debian)
            fetch_yq linux || warn "no yq: notifications fall back to built-in default colors until yq is installed"
            ;;
        *)
            warn "unsupported OS for automatic yq install; install mikefarah yq manually"
            ;;
    esac
}

# Append a line to a file once (idempotent; creates the file if missing).
ensure_line() {
    local line="$1" file="$2"
    [ -f "$file" ] || touch "$file"
    if grep -qF -- "$line" "$file"; then
        info "already present in $file"
    else
        printf '%s\n' "$line" >> "$file"
        info "added to $file"
    fi
}

# Platform-aware package install wrapper. Runs apt-get update before installing
# on Debian. For batch installs across multiple components, prefer pkg_install_many.
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

# Like pkg_install but skips apt-get update. Use when the caller has already
# run apt-get update (e.g. the batched install in install.sh).
# Usage: pkg_install_many pkg1 pkg2 ...
pkg_install_many() {
    local os
    os=$(os_detect)
    case "$os" in
        macos)
            require_cmd brew
            brew install "$@"
            ;;
        debian)
            sudo apt-get install -y "$@"
            ;;
        *)
            die "unsupported OS: $(uname -s)"
            ;;
    esac
}
