#!/usr/bin/env bash
# Install neovim + toolchains the LSPs/linters/formatters configured in
# ~/.config/nvim/init.lua need. Neovim plugins themselves come from
# lazy.nvim at first launch.
#
# Rust support is intentionally not installed here (the rustup/brew toolchain
# was the slowest step and is only needed occasionally). To restore it: add
# "rust_analyzer" back to the servers list in init.lua, and install the
# toolchain (macOS: brew install rust rust-analyzer rustfmt; Debian:
# curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

main() {
    local os
    os=$(os_detect)
    info "install-neovim: $os"

    case "$os" in
        macos)
            pkg_install \
                cmake \
                go \
                hadolint \
                llvm \
                markdownlint-cli2 \
                neovim \
                node \
                python3 \
                shellcheck \
                yamllint
            # Need to install taps seperately
            pkg_install terraform-linters/tap/tflint
            ;;
        debian)
            pkg_install \
                build-essential \
                cmake \
                golang \
                jq \
                nodejs \
                npm \
                python3 \
                python3-pip \
                python3-venv \
                shellcheck \
                yamllint
            # tflint / hadolint are not reliably in apt;
            # install via their own installers if present, else skip.
            warn "tflint and hadolint not installed on Debian by this script; install separately if needed"
            # markdownlint-cli2 is not in apt; install via npm to ~/.local/bin (no sudo needed).
            npm install -g --prefix "$HOME/.local" markdownlint-cli2
            # apt neovim is typically <0.11; install from GitHub releases instead.
            install_neovim_debian
            ;;
        *)
            die "unsupported OS for install-neovim"
            ;;
    esac

    # Python venv used as the py3 provider. Kept OUTSIDE the chezmoi-managed
    # ~/.config/nvim tree so `chezmoi apply`/purge never collides with it, and
    # created unconditionally (init.lua points python3_host_prog here).
    local nvim_dir="$HOME/.config/nvim"
    local nvim_venv="$HOME/.local/share/nvim-venv"
    if [[ ! -d "$nvim_venv" ]]; then
        info "creating $nvim_venv and installing pynvim"
        python3 -m venv "$nvim_venv"
        "$nvim_venv/bin/pip" install --quiet --upgrade pip
        "$nvim_venv/bin/pip" install --quiet pynvim neovim
    else
        info "$nvim_venv already exists"
    fi

    # Pre-warm lazy.nvim plugins (non-fatal if it fails, e.g. no network).
    if command -v nvim >/dev/null 2>&1 && [[ -f "$nvim_dir/init.lua" ]]; then
        info "pre-warming lazy.nvim plugins (headless)"
        nvim --headless "+Lazy! sync" +qa 2>&1 | tail -5 || warn "lazy sync did not complete cleanly"
    fi
}

main "$@"
