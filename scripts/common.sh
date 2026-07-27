#!/usr/bin/env bash
# Shared helpers for dotfiles install scripts. Source, do not exec.

set -euo pipefail

# Directory this lib lives in (scripts/), so helpers can locate sibling scripts
# (e.g. package-plan.sh) regardless of the caller's working directory.
_COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

die() { printf 'dotfiles: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

# os_detect → "macos" | "debian" | "unsupported"
os_detect() {
    # Shared with package-plan tests so installer paths can be exercised with
    # stubbed package managers without mutating the host platform.
    if [[ -n "${DOTFILES_PLAN_OS:-}" ]]; then
        printf '%s\n' "$DOTFILES_PLAN_OS"
        return
    fi
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

# debian_codename → the running Debian/Ubuntu suite codename (e.g. "trixie").
# Order: explicit override (tests/containers), /etc/os-release VERSION_CODENAME,
# lsb_release, then a "trixie" default so a codename-less minimal image still
# targets a real suite. Repos with a fixed suite (NodeSource "nodistro", Trivy
# "generic", gh "stable") do not need this; deb.griffo.io keys its suite to the
# codename, so it does.
debian_codename() {
    if [[ -n "${DOTFILES_DEBIAN_CODENAME:-}" ]]; then
        printf '%s\n' "$DOTFILES_DEBIAN_CODENAME"
        return 0
    fi
    local os_release codename
    os_release=$(_apt_root_path /etc/os-release)
    if [[ -r "$os_release" ]]; then
        codename=$(awk -F= '$1 == "VERSION_CODENAME" {
            gsub(/"/, "", $2); print $2; exit
        }' "$os_release")
        if [[ -n "$codename" ]]; then
            printf '%s\n' "$codename"
            return 0
        fi
    fi
    if command -v lsb_release >/dev/null 2>&1; then
        codename=$(lsb_release -sc 2>/dev/null) || codename=""
        if [[ -n "$codename" ]]; then
            printf '%s\n' "$codename"
            return 0
        fi
    fi
    printf 'trixie\n'
}

_apt_root_path() {
    printf '%s%s\n' "${DOTFILES_APT_ROOT:-}" "$1"
}

_apt_source_file_has_uri() {
    local file="$1" wanted_uri="${2%/}"
    case "$file" in
        *.sources)
            awk -v wanted_uri="$wanted_uri" '
                function finish_stanza() {
                    if (has_uri && enabled) {
                        active = 1
                    }
                    has_uri = 0
                    enabled = 1
                }
                BEGIN { enabled = 1 }
                /^[[:space:]]*$/ {
                    finish_stanza()
                    next
                }
                /^[[:space:]]*#/ { next }
                /^[[:space:]]*Enabled:[[:space:]]*/ {
                    value = $0
                    sub(/^[[:space:]]*Enabled:[[:space:]]*/, "", value)
                    if (tolower(value) == "no") {
                        enabled = 0
                    }
                    next
                }
                /^[[:space:]]*URIs:[[:space:]]*/ {
                    value = $0
                    sub(/^[[:space:]]*URIs:[[:space:]]*/, "", value)
                    count = split(value, uris, /[[:space:]]+/)
                    for (i = 1; i <= count; i++) {
                        uri = uris[i]
                        sub(/\/+$/, "", uri)
                        if (uri == wanted_uri) {
                            has_uri = 1
                        }
                    }
                }
                END {
                    finish_stanza()
                    exit active ? 0 : 1
                }
            ' "$file"
            ;;
        *)
            awk -v wanted_uri="$wanted_uri" '
                /^[[:space:]]*#/ { next }
                /^[[:space:]]*deb(-src)?[[:space:]]/ {
                    for (i = 1; i <= NF; i++) {
                        uri = $i
                        sub(/\/+$/, "", uri)
                        if (uri == wanted_uri) {
                            found = 1
                        }
                    }
                }
                END { exit found ? 0 : 1 }
            ' "$file"
            ;;
    esac
}

apt_repo_configured_elsewhere() {
    local uri="$1" managed_source="$2" managed_target file
    managed_target=$(_apt_root_path "$managed_source")
    for file in \
        "$(_apt_root_path /etc/apt/sources.list)" \
        "$(_apt_root_path /etc/apt/sources.list.d)"/*.list \
        "$(_apt_root_path /etc/apt/sources.list.d)"/*.sources; do
        [[ -r "$file" && "$file" != "$managed_target" ]] || continue
        _apt_source_file_has_uri "$file" "$uri" && return 0
    done
    return 1
}

render_deb822_source() {
    local uri="$1" suite="$2" keyring="$3"
    local arch="${4:-${DOTFILES_APT_ARCH:-$(dpkg --print-architecture)}}"
    printf 'Types: deb\n'
    printf 'URIs: %s\n' "$uri"
    printf 'Suites: %s\n' "$suite"
    printf 'Components: main\n'
    printf 'Architectures: %s\n' "$arch"
    printf 'Signed-By: %s\n' "$keyring"
}

# Confirm before adding a NEW apt repository. install_debian_apt_repo calls this
# only when it is about to write a key + source, never when the repo is already
# present. Only gates on Debian (where we actually mutate apt). Bypassed by
# DOTFILES_ASSUME_YES, which CI and containers export. With neither an opt-in nor
# a usable terminal it declines, so an unattended host never silently gains a
# third-party repo. Returns 0 to proceed, non-zero to skip.
apt_repo_confirm() {
    local label="$1" uri="$2" dev resp
    [[ "$(os_detect)" == debian ]] || return 0
    if _is_truthy "${DOTFILES_ASSUME_YES:-}"; then
        return 0
    fi
    dev="${DOTFILES_TTY:-/dev/tty}"
    if [[ -e "$dev" ]] && (: <"$dev") 2>/dev/null; then
        printf 'dotfiles: add apt repository %s (%s)? [y/N] ' "$label" "$uri" >>"$dev"
        IFS= read -r resp <"$dev" || resp=""
        case "$resp" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            *) return 1 ;;
        esac
    fi
    return 1
}

install_debian_apt_repo() {
    local label="$1" uri="$2" suite="$3" key_url="$4" keyring="$5" source_file="$6"
    local keyring_target source_target tmp_dir key_tmp source_tmp
    keyring_target=$(_apt_root_path "$keyring")
    source_target=$(_apt_root_path "$source_file")
    tmp_dir=$(mktemp -d)
    key_tmp="$tmp_dir/repo-key"
    source_tmp="$tmp_dir/repo.sources"
    render_deb822_source "$uri" "$suite" "$keyring" >"$source_tmp"

    # Respect an equivalent repository owned by the host (including a stanza
    # embedded in a shared Deb822 file). If an earlier dotfiles run created our
    # canonical file alongside it, remove only that duplicate to resolve APT's
    # conflicting Signed-By error; leave the external source and both keyrings
    # untouched.
    if apt_repo_configured_elsewhere "$uri" "$source_file"; then
        if [[ -e "$source_target" || -L "$source_target" ]]; then
            info "$label apt repo configured elsewhere; removing duplicate managed source"
            if ! sudo rm -f -- "$source_target"; then
                rm -rf "$tmp_dir"
                return 1
            fi
        else
            info "$label apt repo already configured elsewhere"
        fi
        rm -rf "$tmp_dir"
        return 0
    fi

    if [[ -r "$keyring_target" && -r "$source_target" ]] \
        && cmp -s "$source_tmp" "$source_target"; then
        info "$label apt repo already configured"
        rm -rf "$tmp_dir"
        return 0
    fi

    if ! apt_repo_confirm "$label" "$uri"; then
        warn "declined to add the $label apt repo"
        rm -rf "$tmp_dir"
        return 1
    fi

    require_cmd curl
    info "adding $label apt repo"
    if ! curl -fsSL -o "$key_tmp" "$key_url"; then
        warn "could not download the $label signing key"
        rm -rf "$tmp_dir"
        return 1
    fi
    if ! sudo install -d -m 0755 "$(dirname "$keyring_target")" "$(dirname "$source_target")" \
        || ! sudo install -m 0644 "$key_tmp" "$keyring_target" \
        || ! sudo install -m 0644 "$source_tmp" "$source_target"; then
        rm -rf "$tmp_dir"
        return 1
    fi
    rm -rf "$tmp_dir"
}

ensure_nodesource_apt_repo() {
    install_debian_apt_repo \
        "NodeSource Node.js 24" \
        "https://deb.nodesource.com/node_24.x" \
        "nodistro" \
        "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
        "/etc/apt/keyrings/nodesource.asc" \
        "/etc/apt/sources.list.d/nodesource.sources"
}

ensure_trivy_apt_repo() {
    install_debian_apt_repo \
        "Aqua Security Trivy" \
        "https://aquasecurity.github.io/trivy-repo/deb" \
        "generic" \
        "https://aquasecurity.github.io/trivy-repo/deb/public.key" \
        "/etc/apt/keyrings/trivy.asc" \
        "/etc/apt/sources.list.d/trivy.sources"
}

# Manage the canonical GitHub CLI Deb822 repository. The caller owns apt-get
# update so package installs can stay batched.
ensure_gh_apt_repo() {
    install_debian_apt_repo \
        "GitHub CLI" \
        "https://cli.github.com/packages" \
        "stable" \
        "https://cli.github.com/packages/githubcli-archive-keyring.gpg" \
        "/etc/apt/keyrings/githubcli-archive-keyring.gpg" \
        "/etc/apt/sources.list.d/github-cli.sources"
}

# Manage the deb.griffo.io Deb822 repository (current neovim/fzf/ghostty/zoxide
# for Debian). Unlike the fixed-suite repos above, its suite is the running
# codename, so it resolves debian_codename() at call time.
ensure_griffo_apt_repo() {
    install_debian_apt_repo \
        "deb.griffo.io" \
        "https://deb.griffo.io/apt" \
        "$(debian_codename)" \
        "https://deb.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc" \
        "/etc/apt/keyrings/deb.griffo.io.asc" \
        "/etc/apt/sources.list.d/deb.griffo.io.sources"
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

github_latest_release_tag() {
    local repo="$1" tmp_json tag
    tmp_json=$(mktemp)
    if ! curl -fsSL -o "$tmp_json" "https://api.github.com/repos/${repo}/releases/latest"; then
        rm -f "$tmp_json"
        return 1
    fi
    tag=$(awk -F'"' '/"tag_name":/{print $4; exit}' "$tmp_json")
    rm -f "$tmp_json"
    [[ -n "$tag" ]] || return 1
    printf '%s\n' "$tag"
}

tflint_release_arch() {
    case "$1" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) return 1 ;;
    esac
}

tenv_release_arch() {
    case "$1" in
        x86_64|amd64)  echo "x86_64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) return 1 ;;
    esac
}

verify_release_checksum() {
    local dir="$1" checksums="$2" asset="$3"
    (
        cd "$dir"
        awk -v asset="$asset" '$2 == asset || $2 == "*" asset' "$checksums" \
            > selected-checksum.txt
        [[ -s selected-checksum.txt ]]
        sha256sum -c selected-checksum.txt
    )
}

install_tflint_debian() {
    if command -v tflint >/dev/null 2>&1; then
        info "tflint already on PATH: $(command -v tflint)"
        return 0
    fi
    require_cmd curl
    require_cmd unzip
    local arch tag asset tmp_dir
    arch=$(tflint_release_arch "$(uname -m)") \
        || { warn "unsupported arch $(uname -m) for tflint"; return 1; }
    tag=$(github_latest_release_tag terraform-linters/tflint) \
        || { warn "could not determine the latest tflint release"; return 1; }
    asset="tflint_linux_${arch}.zip"
    tmp_dir=$(mktemp -d)
    info "fetching tflint ${tag} (${arch})"
    if ! curl -fsSL -o "$tmp_dir/$asset" \
        "https://github.com/terraform-linters/tflint/releases/download/${tag}/${asset}" \
        || ! curl -fsSL -o "$tmp_dir/checksums.txt" \
        "https://github.com/terraform-linters/tflint/releases/download/${tag}/checksums.txt" \
        || ! verify_release_checksum "$tmp_dir" checksums.txt "$asset"; then
        warn "tflint download or checksum verification failed"
        rm -rf "$tmp_dir"
        return 1
    fi
    unzip -oq "$tmp_dir/$asset" -d "$tmp_dir/unpack"
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$tmp_dir/unpack/tflint" "$HOME/.local/bin/tflint"
    rm -rf "$tmp_dir"
    info "tflint installed: $("$HOME/.local/bin/tflint" --version 2>/dev/null | head -1)"
}

install_tenv_debian() {
    if command -v tenv >/dev/null 2>&1 && [[ -x "$HOME/.local/bin/terraform" ]]; then
        info "tenv and its terraform proxy already present"
        return 0
    fi
    require_cmd curl
    local arch tag asset checksums tmp_dir
    arch=$(tenv_release_arch "$(uname -m)") \
        || { warn "unsupported arch $(uname -m) for tenv"; return 1; }
    tag=$(github_latest_release_tag tofuutils/tenv) \
        || { warn "could not determine the latest tenv release"; return 1; }
    asset="tenv_${tag}_Linux_${arch}.tar.gz"
    checksums="tenv_${tag}_checksums.txt"
    tmp_dir=$(mktemp -d)
    info "fetching tenv ${tag} (${arch})"
    if ! curl -fsSL -o "$tmp_dir/$asset" \
        "https://github.com/tofuutils/tenv/releases/download/${tag}/${asset}" \
        || ! curl -fsSL -o "$tmp_dir/$checksums" \
        "https://github.com/tofuutils/tenv/releases/download/${tag}/${checksums}" \
        || ! verify_release_checksum "$tmp_dir" "$checksums" "$asset"; then
        warn "tenv download or checksum verification failed"
        rm -rf "$tmp_dir"
        return 1
    fi
    mkdir -p "$tmp_dir/unpack" "$HOME/.local/bin"
    tar -xzf "$tmp_dir/$asset" -C "$tmp_dir/unpack"
    [[ -x "$tmp_dir/unpack/tenv" && -x "$tmp_dir/unpack/terraform" ]] \
        || { warn "tenv archive did not contain the expected proxies"; rm -rf "$tmp_dir"; return 1; }
    install -m 0755 "$tmp_dir/unpack/tenv" "$HOME/.local/bin/tenv"
    install -m 0755 "$tmp_dir/unpack/terraform" "$HOME/.local/bin/terraform"
    rm -rf "$tmp_dir"
    info "tenv installed: $("$HOME/.local/bin/tenv" --version 2>/dev/null | head -1)"
}

verify_node_major() {
    local wanted="$1" version major
    command -v node >/dev/null 2>&1 || return 1
    version=$(node --version 2>/dev/null) || return 1
    major=${version#v}
    major=${major%%.*}
    [[ "$major" == "$wanted" ]]
}

bootstrap_tenv_terraform() {
    local tenv_bin
    if [[ -x "$HOME/.local/bin/tenv" ]]; then
        tenv_bin="$HOME/.local/bin/tenv"
    else
        tenv_bin=$(command -v tenv 2>/dev/null) || return 1
    fi
    info "installing the latest stable Terraform fallback with tenv"
    TENV_AUTO_INSTALL=true TENV_VALIDATION=signature "$tenv_bin" tf install latest
    TENV_AUTO_INSTALL=true TENV_VALIDATION=signature "$tenv_bin" tf use latest
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

# True when $1 is an affirmative value (1/true/yes/y), case-insensitive. Bash 3.2
# safe (case globs, no ${x,,}).
_is_truthy() {
    case "$1" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Yy]) return 0 ;;
        *) return 1 ;;
    esac
}

# Select an owned, writable runtime directory for the one-shot package
# confirmation. XDG_RUNTIME_DIR is trusted only when it belongs to this user;
# stale sudo-exported values such as /run/user/0 therefore fall back to a
# UID-specific directory under TMPDIR (or /tmp).
_pkg_confirm_runtime_dir() {
    local candidate="${XDG_RUNTIME_DIR:-}" uid base
    if [[ -n "$candidate" && -d "$candidate" && ! -L "$candidate" \
        && -O "$candidate" && -w "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    uid=$(id -u)
    for base in "${TMPDIR:-}" /tmp; do
        [[ -n "$base" ]] || continue
        candidate="${base%/}/dotfiles-runtime-${uid}"
        [[ -L "$candidate" ]] && continue
        if (umask 077; mkdir -p "$candidate") 2>/dev/null \
            && [[ -d "$candidate" && -O "$candidate" && -w "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# Resolve the one-shot "packages confirmed at init" sentinel path. An explicit
# override remains available for automation and tests.
_pkg_confirm_sentinel() {
    if [[ -n "${DOTFILES_PKG_CONFIRM_SENTINEL:-}" ]]; then
        printf '%s\n' "$DOTFILES_PKG_CONFIRM_SENTINEL"
        return 0
    fi
    local runtime_dir
    runtime_dir=$(_pkg_confirm_runtime_dir) || return 1
    printf '%s/dotfiles-pkg-confirm\n' "$runtime_dir"
}

# Confirm before any package-manager mutation. One checkpoint per independent
# entry path (install.sh's packages branch, install-notify.sh), matching the grain
# where DOTFILES_INSTALL_MODE already gates a whole branch as a unit - not one
# prompt per brew/apt/npm/pip call. Returns 0 to proceed, non-zero to decline.
#
# Decision order:
#   1. DOTFILES_ASSUME_YES truthy (1/true/yes/y)       -> proceed silently.
#   2. one-shot sentinel present and younger than ~10m -> proceed, consume it
#      (confirm-install.sh writes it when "packages" is chosen at init, so the
#      apply immediately following an interactive init does not re-prompt).
#   3. a usable controlling terminal                   -> show the package plan,
#      prompt [y/N] (default N); only y/yes proceeds.
#   4. no terminal and no opt-in                        -> decline.
#
# Reads the answer from ${DOTFILES_TTY:-/dev/tty} and writes the plan + prompt to
# the same device with append (>>). On a real tty append is an ordinary write; on
# a plain file (test) it preserves a preloaded answer on line 1 that a truncating
# write would clobber.
# $1 (optional): a short context label shown in the prompt.
pkg_confirm() {
    local label="${1:-package install/update}"
    local sentinel dev plan resp

    if _is_truthy "${DOTFILES_ASSUME_YES:-}"; then
        return 0
    fi

    sentinel=""
    sentinel=$(_pkg_confirm_sentinel) || true
    if [[ -n "$sentinel" && -f "$sentinel" ]]; then
        if [[ -n "$(find "$sentinel" -mmin -10 2>/dev/null)" ]]; then
            rm -f "$sentinel"
            info "package install pre-confirmed at init; proceeding"
            return 0
        fi
        # Stale sentinel (past the window): never trust it, clean it up.
        rm -f "$sentinel"
    fi

    dev="${DOTFILES_TTY:-/dev/tty}"
    if [[ -e "$dev" ]] && (: <"$dev") 2>/dev/null; then
        plan="$("$_COMMON_SH_DIR/package-plan.sh" --display 2>/dev/null || true)"
        {
            if [[ -n "$plan" ]]; then
                printf '%s\n\n' "$plan"
            fi
            printf 'dotfiles: %s. Install/update packages now? [y/N] ' "$label"
        } >>"$dev"
        IFS= read -r resp <"$dev" || resp=""
        case "$resp" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            *) return 1 ;;
        esac
    fi

    return 1
}
