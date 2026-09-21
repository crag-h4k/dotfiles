#!/usr/bin/env bash
# Shared helpers for dotfiles install scripts. Source, do not exec.

set -euo pipefail

# Directory this lib lives in (scripts/), so helpers can locate sibling scripts
# (e.g. package-plan.sh) regardless of the caller's working directory.
_COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

die() { printf 'dotfiles: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

# Best-effort package runs keep independent failures visible without stopping
# later package sources. Call package_results_reset once per reporting scope,
# wrap each independent operation with package_try, then print one summary.
_package_results_ok=0
_package_results_failed=0
_package_results_skipped=0

package_results_reset() {
    _package_results_ok=0
    _package_results_failed=0
    _package_results_skipped=0
}

package_try() {
    local label="$1"
    shift
    if "$@"; then
        _package_results_ok=$((_package_results_ok + 1))
        info "$label: ok"
        return 0
    fi
    _package_results_failed=$((_package_results_failed + 1))
    warn "$label: failed; continuing"
    return 1
}

package_skip() {
    _package_results_skipped=$((_package_results_skipped + 1))
    info "$1: skipped"
}

package_results_summary() {
    local scope="${1:-packages}"
    info "$scope summary: ok=$_package_results_ok failed=$_package_results_failed skipped=$_package_results_skipped"
}

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
# "generic", gh "stable") do not need this; it is for any repo that keys its
# suite to the running codename.
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

github_latest_release_asset_sha256() {
    local repo="$1" asset="$2" tmp_json digest
    tmp_json=$(mktemp)
    if ! curl -fsSL -o "$tmp_json" "https://api.github.com/repos/${repo}/releases/latest"; then
        rm -f "$tmp_json"
        return 1
    fi
    digest=$(awk -F'"' -v asset="$asset" '
        $2 == "name" && $4 == asset { found = 1; next }
        found && $2 == "digest" && $4 ~ /^sha256:/ {
            sub(/^sha256:/, "", $4)
            print $4
            exit
        }
        found && $2 == "name" { found = 0 }
    ' "$tmp_json")
    rm -f "$tmp_json"
    [[ "$digest" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
    printf '%s\n' "$digest"
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

tree_sitter_cli_release_asset() {
    case "$1" in
        x86_64|amd64)  echo "tree-sitter-cli-linux-x64.zip" ;;
        aarch64|arm64) echo "tree-sitter-cli-linux-arm64.zip" ;;
        *) return 1 ;;
    esac
}

tree_sitter_cli_release_sha256() {
    case "$1" in
        x86_64|amd64)  echo "ff1b7f9863f2faafd78dc0e66d902ee85b37f709b314b22c009f51caf233eebd" ;;
        aarch64|arm64) echo "db28509fe6db8902f9d14c43c486858c7486b42c3a96b30e811e73f105762336" ;;
        *) return 1 ;;
    esac
}

sha256_file() {
    local file="$1" output
    if command -v sha256sum >/dev/null 2>&1; then
        output=$(sha256sum "$file") || return 1
        printf '%s\n' "${output%% *}"
        return 0
    fi
    if command -v shasum >/dev/null 2>&1; then
        output=$(shasum -a 256 "$file") || return 1
        printf '%s\n' "${output%% *}"
        return 0
    fi
    if command -v openssl >/dev/null 2>&1; then
        output=$(openssl dgst -sha256 "$file") || return 1
        printf '%s\n' "${output##* }"
        return 0
    fi
    warn "no SHA-256 implementation found (sha256sum, shasum, or openssl)"
    return 1
}

verify_sha256() {
    local file="$1" expected="$2" actual
    actual=$(sha256_file "$file") || return 1
    [[ "$actual" == "$expected" ]]
}

verify_release_checksum() {
    local dir="$1" checksums="$2" asset="$3" expected
    (
        cd "$dir"
        expected=$(awk -v asset="$asset" '$2 == asset || $2 == "*" asset { print $1; exit }' "$checksums")
        [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]]
        verify_sha256 "$asset" "$expected"
    )
}

verify_release_checksum_bsd() {
    local dir="$1" checksums="$2" asset="$3" expected
    (
        cd "$dir"
        expected=$(awk -v asset="$asset" \
            '$1 == "SHA256" && $2 == "(" asset ")" && $3 == "=" { print $4; exit }' \
            "$checksums")
        [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]]
        verify_sha256 "$asset" "$expected"
    )
}

# Replace a user-local executable only after its downloaded candidate has been
# verified. The temporary file lives beside the destination, so mv is atomic.
atomic_install_binary() {
    local source="$1" destination="$2" tmp
    mkdir -p "$(dirname "$destination")"
    tmp=$(mktemp "${destination}.tmp.XXXXXX") || return 1
    if ! install -m 0755 "$source" "$tmp" || ! mv -f "$tmp" "$destination"; then
        rm -f "$tmp"
        return 1
    fi
}

install_tree_sitter_cli_debian() {
    local version_line installed=""
    if command -v tree-sitter >/dev/null 2>&1; then
        version_line=$(tree-sitter --version 2>/dev/null || true)
        if [[ "$version_line" =~ tree-sitter[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            installed="${BASH_REMATCH[1]}"
        fi
        if [[ "$installed" == 0.26.11 ]]; then
            info "tree-sitter CLI 0.26.11 pin already installed; reasserted"
            return 0
        fi
        info "tree-sitter CLI ${installed:-unknown} differs from pinned 0.26.11; reasserting the pin"
    fi

    require_cmd curl
    require_cmd unzip
    local tag="v0.26.11" asset expected_sha tmp_dir
    asset=$(tree_sitter_cli_release_asset "$(uname -m)") \
        || { warn "unsupported arch $(uname -m) for tree-sitter CLI"; return 1; }
    expected_sha=$(tree_sitter_cli_release_sha256 "$(uname -m)") \
        || { warn "no tree-sitter CLI checksum for $(uname -m)"; return 1; }
    tmp_dir=$(mktemp -d)
    info "fetching tree-sitter CLI ${tag} ($(uname -m))"
    if ! curl -fsSL -o "$tmp_dir/$asset" \
        "https://github.com/tree-sitter/tree-sitter/releases/download/${tag}/${asset}" \
        || ! verify_sha256 "$tmp_dir/$asset" "$expected_sha"; then
        warn "tree-sitter CLI download or checksum verification failed"
        rm -rf "$tmp_dir"
        return 1
    fi
    mkdir -p "$tmp_dir/unpack" "$HOME/.local/bin"
    unzip -oq "$tmp_dir/$asset" -d "$tmp_dir/unpack"
    [[ -x "$tmp_dir/unpack/tree-sitter" ]] \
        || { warn "tree-sitter CLI archive did not contain the expected binary"; rm -rf "$tmp_dir"; return 1; }
    if ! atomic_install_binary "$tmp_dir/unpack/tree-sitter" "$HOME/.local/bin/tree-sitter"; then
        warn "tree-sitter CLI atomic replacement failed"
        rm -rf "$tmp_dir"
        return 1
    fi
    rm -rf "$tmp_dir"
    info "tree-sitter CLI installed: $("$HOME/.local/bin/tree-sitter" --version 2>/dev/null)"
}

install_tflint_debian() {
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
    if ! atomic_install_binary "$tmp_dir/unpack/tflint" "$HOME/.local/bin/tflint"; then
        warn "tflint atomic replacement failed"
        rm -rf "$tmp_dir"
        return 1
    fi
    rm -rf "$tmp_dir"
    info "tflint installed: $("$HOME/.local/bin/tflint" --version 2>/dev/null | head -1)"
}

install_tenv_debian() {
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
    if ! atomic_install_binary "$tmp_dir/unpack/tenv" "$HOME/.local/bin/tenv" \
        || ! atomic_install_binary "$tmp_dir/unpack/terraform" "$HOME/.local/bin/terraform"; then
        warn "tenv atomic replacement failed"
        rm -rf "$tmp_dir"
        return 1
    fi
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

# NodeSource is needed for every selected feature that installs an npm CLI, not
# only for Neovim. Keep this predicate shared by planning, repository setup, and
# post-install verification so an AI-only Debian host gets Node.js 24 too.
node_runtime_selected() {
    [[ "${INSTALL_NEOVIM:-false}" == true \
        || "${INSTALL_AI_CODECOMPANION:-false}" == true \
        || "${INSTALL_AI_OPENCODE:-false}" == true \
        || "${INSTALL_AI_COPILOT:-false}" == true ]]
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

_neovim_tree_health() {
    local tree="$1"
    [[ -x "$tree/bin/nvim" && -d "$tree/share/nvim/runtime" ]] || return 1
    VIMRUNTIME="$tree/share/nvim/runtime" \
        "$tree/bin/nvim" --headless -u NONE -i NONE '+quitall' >/dev/null 2>&1
}

# Replace one path with another using rename(2) semantics. Unlike `mv -f`,
# os.replace does not follow a destination symlink that points at a directory.
# That distinction is required for atomic `current` pointer updates on macOS.
atomic_replace_path() {
    local source="$1" destination="$2" python
    python=$(command -v python3) || { warn "python3 is required for an atomic path switch"; return 1; }
    "$python" -c 'import os, sys; os.replace(sys.argv[1], sys.argv[2])' \
        "$source" "$destination"
}

sudo_atomic_replace_path() {
    local source="$1" destination="$2" python
    python=$(command -v python3) || { warn "python3 is required for an atomic path switch"; return 1; }
    sudo "$python" -c 'import os, sys; os.replace(sys.argv[1], sys.argv[2])' \
        "$source" "$destination"
}

_restore_neovim_pointer() {
    local root="$1" old_target="$2" tmp_link
    tmp_link="$root/.current-rollback.$$"
    if [[ -n "$old_target" ]]; then
        sudo rm -f "$tmp_link"
        sudo ln -s "$old_target" "$tmp_link" \
            && sudo_atomic_replace_path "$tmp_link" "$root/current"
    else
        sudo rm -f "$root/current"
    fi
}

activate_neovim_tree() {
    local root="$1" public_bin="$2" tag="$3" stage="$4"
    local releases release
    local old_target="" pointer_tmp="$root/.current-new.$$"
    local wrapper_tmp wrapper_stage="${public_bin}.dotfiles-new" public_backup="${public_bin}.previous"
    local had_public=false
    releases="$root/releases"
    release="$releases/$tag"

    _neovim_tree_health "$stage" || { warn "neovim staged tree failed its headless health check"; return 1; }
    sudo mkdir -p "$releases" "$(dirname "$public_bin")"
    if [[ -e "$release" ]]; then
        if _neovim_tree_health "$release"; then
            sudo rm -rf "$stage"
        else
            sudo mv "$release" "${release}.invalid.$(date +%s).$$"
            sudo mv "$stage" "$release"
        fi
    else
        sudo mv "$stage" "$release"
    fi

    if [[ -e "$root/current" || -L "$root/current" ]]; then
        [[ -L "$root/current" ]] || { warn "neovim current pointer is not a symlink"; return 1; }
        old_target=$(readlink "$root/current") || { warn "could not inspect neovim current pointer"; return 1; }
    fi

    wrapper_tmp=$(mktemp)
    {
        printf '#!/bin/sh\n'
        printf 'export VIMRUNTIME=%s\n' "$(printf '%q' "$root/current/share/nvim/runtime")"
        printf 'exec %s "\$@"\n' "$(printf '%q' "$root/current/bin/nvim")"
    } >"$wrapper_tmp"
    sudo install -m 0755 "$wrapper_tmp" "$wrapper_stage" || { rm -f "$wrapper_tmp"; return 1; }
    rm -f "$wrapper_tmp"

    if [[ -e "$public_bin" || -L "$public_bin" ]]; then
        had_public=true
        sudo cp -pP "$public_bin" "$public_backup" || return 1
    fi
    sudo rm -f "$pointer_tmp"
    sudo ln -s "releases/$tag" "$pointer_tmp" || return 1
    sudo_atomic_replace_path "$pointer_tmp" "$root/current" || return 1
    if ! sudo mv -f "$wrapper_stage" "$public_bin"; then
        _restore_neovim_pointer "$root" "$old_target"
        return 1
    fi
    if ! "$public_bin" --headless -u NONE -i NONE '+quitall' >/dev/null 2>&1; then
        _restore_neovim_pointer "$root" "$old_target"
        if [[ -e "$public_backup" || -L "$public_backup" ]]; then
            sudo mv -f "$public_backup" "$public_bin"
        elif [[ "$had_public" == false ]]; then
            sudo rm -f "$public_bin"
        fi
        warn "neovim activated tree failed through the public wrapper; rolled back"
        return 1
    fi
}

# Install the latest tagged Neovim release as one versioned binary/runtime/lib
# tree. The current pointer changes only after a headless health check passes.
install_neovim_debian() {
    require_cmd curl
    local root="${DOTFILES_NVIM_ROOT:-/opt/dotfiles-neovim}"
    local public_bin="${DOTFILES_NVIM_BIN:-/usr/local/bin/nvim}"
    local tag latest installed="" arch tmp_dir asset expected_sha stage

    info "fetching latest neovim release tag from GitHub"
    tag=$(github_latest_release_tag neovim/neovim) \
        || { warn "could not determine latest neovim release tag"; return 1; }
    latest="${tag#v}"
    if [[ -x "$root/current/bin/nvim" ]] && _neovim_tree_health "$root/current"; then
        installed=$("$root/current/bin/nvim" --version 2>/dev/null | head -1)
        installed=${installed#NVIM v}
        if [[ "$installed" == "$latest" ]]; then
            info "neovim ${installed} versioned tree is current"
            if command -v dpkg-query >/dev/null 2>&1 \
                && [[ "$(dpkg-query -W -f='${Status}' neovim 2>/dev/null || true)" == "install ok installed" ]]; then
                sudo apt-get remove -y neovim || warn "could not remove the conflicting APT neovim package"
            fi
            return 0
        fi
    fi

    case "$(uname -m)" in
        x86_64)        arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) warn "unsupported arch $(uname -m) for prebuilt neovim"; return 1 ;;
    esac

    tmp_dir=$(mktemp -d)
    asset="nvim-linux-${arch}.tar.gz"
    expected_sha=$(github_latest_release_asset_sha256 neovim/neovim "$asset") \
        || { warn "neovim ${tag} release metadata has no SHA256 digest for $asset"; rm -rf "$tmp_dir"; return 1; }
    if ! curl -fSL -o "$tmp_dir/$asset" \
        "https://github.com/neovim/neovim/releases/download/${tag}/${asset}" \
        || ! verify_sha256 "$tmp_dir/$asset" "$expected_sha"; then
        warn "neovim ${tag} download or checksum verification failed"
        rm -rf "$tmp_dir"
        return 1
    fi

    stage="$root/releases/.${tag}.stage.$$"
    sudo mkdir -p "$stage"
    if ! sudo tar -C "$stage" --strip-components=1 -xzf "$tmp_dir/$asset" \
        || ! _neovim_tree_health "$stage"; then
        warn "neovim ${tag} staged tree failed extraction or health check"
        sudo rm -rf "$stage"
        rm -rf "$tmp_dir"
        return 1
    fi
    rm -rf "$tmp_dir"

    activate_neovim_tree "$root" "$public_bin" "$tag" "$stage" || return 1
    if command -v dpkg-query >/dev/null 2>&1 \
        && [[ "$(dpkg-query -W -f='${Status}' neovim 2>/dev/null || true)" == "install ok installed" ]]; then
        sudo apt-get remove -y neovim || warn "could not remove the conflicting APT neovim package"
    fi
    rm -f "$HOME/.local/bin/nvim"
    info "neovim ${tag} activated at $root/current"
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
    local os="$1" arch asset tag tmp_dir
    case "$(uname -m)" in
        x86_64)        arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)
            warn "unsupported arch $(uname -m) for prebuilt yq; install manually"
            return 1
            ;;
    esac
    require_cmd curl
    tag=$(github_latest_release_tag mikefarah/yq) \
        || { warn "could not determine the latest yq release"; return 1; }
    asset="yq_${os}_${arch}"
    tmp_dir=$(mktemp -d)
    info "fetching mikefarah yq ${tag} (${os}/${arch})"
    if ! curl -fsSL --fail -o "$tmp_dir/$asset" \
        "https://github.com/mikefarah/yq/releases/download/${tag}/${asset}" \
        || ! curl -fsSL --fail -o "$tmp_dir/checksums-bsd" \
        "https://github.com/mikefarah/yq/releases/download/${tag}/checksums-bsd" \
        || ! verify_release_checksum_bsd "$tmp_dir" checksums-bsd "$asset"; then
        warn "yq download or checksum verification failed; leaving the existing binary untouched"
        rm -rf "$tmp_dir"
        return 1
    fi
    chmod +x "$tmp_dir/$asset"
    if ! "$tmp_dir/$asset" --version 2>/dev/null | grep -qi mikefarah; then
        warn "downloaded yq is not a working mikefarah binary; leaving existing yq untouched"
        rm -rf "$tmp_dir"
        return 1
    fi
    if ! atomic_install_binary "$tmp_dir/$asset" "$HOME/.local/bin/yq"; then
        warn "yq atomic replacement failed; leaving the existing binary untouched"
        rm -rf "$tmp_dir"
        return 1
    fi
    rm -rf "$tmp_dir"
    info "yq installed: $("$HOME/.local/bin/yq" --version 2>/dev/null)"
}

# Debian: ensure mikefarah yq (binary fetch). No-op if already present. Called by
# install.sh for the tmux/zsh components.
install_yq_debian() {
    if [[ "${1:-missing-only}" != update ]] && have_mikefarah_yq; then
        info "mikefarah yq already present: $(yq --version 2>/dev/null)"
        return 0
    fi
    fetch_yq linux
}

canonical_git_url() {
    local url="$1" path dir base
    url="${url%/}"
    url="${url%.git}"
    case "$url" in
        file://*) path="${url#file://}" ;;
        /*|./*|../*) path="$url" ;;
        git@*:*)
            printf '%s\n' "${url#git@}" | sed 's/:/\//'
            return 0
            ;;
        ssh://git@*) printf '%s\n' "${url#ssh://git@}"; return 0 ;;
        https://*) printf '%s\n' "${url#https://}"; return 0 ;;
        *) printf '%s\n' "$url"; return 0 ;;
    esac
    dir=$(dirname "$path")
    base=$(basename "$path")
    dir=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
    printf 'file://%s/%s\n' "${dir%/}" "$base"
}

# Chezmoi materializes selected missing externals as configuration payloads.
# Package mode refreshes only an existing clean checkout whose configured
# tracking remote still matches the declared URL.
update_git_external() {
    local label="$1" url="$2" path="$3"
    local inside status branch upstream remote remote_url declared_url
    local head remote_head base

    if [[ ! -e "$path" ]]; then
        warn "$label: checkout is missing; chezmoi must materialize it; skipped"
        return 2
    fi
    if ! inside=$(git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null) \
        || [[ "$inside" != true ]]; then
        warn "$label: $path exists but is not a git repository; skipped"
        return 2
    fi
    if ! status=$(git -C "$path" status --porcelain 2>/dev/null); then
        warn "$label: could not inspect checkout status; skipped"
        return 2
    fi
    if [[ -n "$status" ]]; then
        warn "$label: local changes present; skipped"
        return 2
    fi
    if ! branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null); then
        warn "$label: detached HEAD; skipped"
        return 2
    fi
    if ! upstream=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null); then
        warn "$label: branch $branch has no upstream; skipped"
        return 2
    fi
    if ! remote=$(git -C "$path" config --get "branch.$branch.remote" 2>/dev/null) \
        || [[ -z "$remote" || "$remote" == . ]]; then
        warn "$label: could not resolve a tracking remote for $branch; skipped"
        return 2
    fi
    if ! remote_url=$(git -C "$path" remote get-url "$remote" 2>/dev/null) \
        || ! remote_url=$(canonical_git_url "$remote_url") \
        || ! declared_url=$(canonical_git_url "$url"); then
        warn "$label: could not inspect or canonicalize remote URLs; skipped"
        return 2
    fi
    if [[ "$remote_url" != "$declared_url" ]]; then
        warn "$label: tracking remote $remote URL does not match the declared external; skipped"
        return 2
    fi
    if ! git -C "$path" fetch --quiet "$remote"; then
        warn "$label: fetch from tracking remote $remote failed; skipped"
        return 1
    fi
    if ! head=$(git -C "$path" rev-parse HEAD 2>/dev/null) \
        || ! remote_head=$(git -C "$path" rev-parse "$upstream" 2>/dev/null); then
        warn "$label: could not inspect local or upstream HEAD; skipped"
        return 2
    fi
    if [[ "$head" == "$remote_head" ]]; then
        info "$label: already current"
        return 0
    fi
    if ! base=$(git -C "$path" merge-base HEAD "$upstream" 2>/dev/null); then
        warn "$label: could not inspect branch ancestry; skipped"
        return 2
    fi
    if [[ "$base" == "$head" ]]; then
        git -C "$path" merge --ff-only "$upstream"
        return
    fi
    if [[ "$base" == "$remote_head" ]]; then
        warn "$label: local branch is ahead of $upstream; skipped"
        return 2
    fi
    warn "$label: local branch diverged from $upstream; skipped"
    return 2
}

# Installer-owned Git runtime. Missing repositories are cloned only after the
# package confirmation; existing repositories use the same dirty/divergence and
# remote-integrity checks as other floating Git dependencies.
install_or_update_git_runtime() {
    local label="$1" url="$2" path="$3"
    if [[ ! -e "$path" ]]; then
        mkdir -p "$(dirname "$path")"
        if ! git clone --depth=1 -- "$url" "$path"; then
            warn "$label: clone failed"
            return 1
        fi
        return 0
    fi
    update_git_external "$label" "$url" "$path"
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
        plan="$(DOTFILES_PLAN_APPROVED=0 "$_COMMON_SH_DIR/package-plan.sh" --display 2>/dev/null || true)"
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
