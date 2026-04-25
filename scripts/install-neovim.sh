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
                neovim cmake llvm \
                go rust rust-analyzer rustfmt \
                python3 node \
                hadolint tflint yamllint shellcheck
            ;;
        debian)
            pkg_install \
                neovim \
                python3 python3-pip python3-venv \
                nodejs npm \
                golang cargo \
                yamllint shellcheck
            # tflint / hadolint / rust-analyzer are not reliably in apt;
            # install via their own installers if present, else skip.
            warn "tflint and hadolint not installed on Debian by this script; install separately if needed"
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
