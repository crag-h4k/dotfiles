#!/usr/bin/env bash
# Install neovim + toolchains the LSPs/linters/formatters configured in
# ~/.config/nvim/init.lua need. Neovim plugins themselves come from
# lazy.nvim at first launch.

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
                rust \
                rust-analyzer \
                rustfmt \
                shellcheck \
                yamllint
            # Need to install taps seperately
            pkg_install terraform-linters/tap/tflint
            ;;
        debian)
            pkg_install \
                golang \
                jq \
                nodejs \
                npm \
                python3 \
                python3-pip \
                python3-venv \
                shellcheck \
                yamllint
            # Install Rust toolchain via rustup (apt cargo is too old and lacks rust-analyzer).
            if ! command -v rustup >/dev/null 2>&1; then
                require_cmd curl
                info "installing rustup"
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
                    | sh -s -- -y --no-modify-path
            fi
            # Source cargo env so rustup commands are available in this script.
            # shellcheck source=/dev/null
            [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
            rustup component add rust-analyzer 2>/dev/null || warn "rust-analyzer component not available yet; run: rustup component add rust-analyzer"
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

    # Create the Python venv used as the py3 provider.
    local nvim_dir="$HOME/.config/nvim"
    if [[ -d "$nvim_dir" ]]; then
        if [[ ! -d "$nvim_dir/venv" ]]; then
            info "creating $nvim_dir/venv and installing pynvim"
            python3 -m venv "$nvim_dir/venv"
            "$nvim_dir/venv/bin/pip" install --quiet --upgrade pip
            "$nvim_dir/venv/bin/pip" install --quiet pynvim neovim
        else
            info "$nvim_dir/venv already exists"
        fi
    else
        warn "$nvim_dir not found yet (chezmoi apply hasn't placed it); skipping venv setup"
    fi

    # Pre-warm lazy.nvim plugins (non-fatal if it fails, e.g. no network).
    if command -v nvim >/dev/null 2>&1 && [[ -f "$nvim_dir/init.lua" ]]; then
        info "pre-warming lazy.nvim plugins (headless)"
        nvim --headless "+Lazy! sync" +qa 2>&1 | tail -5 || warn "lazy sync did not complete cleanly"
    fi
}

main "$@"
