#!/usr/bin/env bash
# Install neovim + toolchains the LSPs/linters/formatters configured in
# ~/.config/nvim/init.lua need. Neovim plugins themselves come from
# lazy.nvim at first launch.
#
# luacheck (the repo's pre-commit lua linter) is installed here onto PATH:
# luacheck 1.2.0 does not run on Lua 5.5 (Homebrew's default), so on macOS it is
# built against lua@5.4. The pre-commit hook runs it as language:system. StyLua
# needs nothing here: its hook (stylua-github) downloads its own prebuilt binary.
#
# When the `ai` component is selected (exported as INSTALL_AI by
# run_once_after_00-install.sh), the Claude Code ACP bridge `claude-agent-acp`
# is installed too - CodeCompanion's chat adapter spawns it.
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

# Off by default (and for standalone runs); turned on by the configure menu.
INSTALL_AI="${INSTALL_AI:-false}"

main() {
    local os
    os=$(os_detect)
    info "install-neovim: $os"

    # Packages are installed by the batched call in install.sh. tflint (macOS tap)
    # and install_neovim_debian (Debian binary) are also called from install.sh.

    # On Debian: markdownlint-cli2 is not in apt; install via npm.
    if [[ "$os" == "debian" ]]; then
        warn "tflint and hadolint not installed on Debian by this script; install separately if needed"
        npm install -g --prefix "$HOME/.local" markdownlint-cli2
    fi

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

    # luacheck for the pre-commit lua linter (runs as language:system, so it must
    # be on PATH). luacheck 1.2.0 does not run on Lua 5.5; on macOS build it
    # against lua@5.4. Installed to the user rock tree and symlinked into
    # ~/.local/bin (already on PATH per the zsh config).
    if ! command -v luacheck >/dev/null 2>&1; then
        info "installing luacheck"
        mkdir -p "$HOME/.local/bin"
        case "$os" in
            macos)
                luarocks --lua-version=5.4 --lua-dir "$(brew --prefix lua@5.4)" install --local luacheck
                ;;
            debian)
                # apt luarocks pairs with a Lua that luacheck supports (<= 5.4).
                luarocks install luacheck
                ;;
        esac
        ln -sf "$HOME/.luarocks/bin/luacheck" "$HOME/.local/bin/luacheck"
    else
        info "luacheck already on PATH: $(command -v luacheck)"
    fi

    # CodeCompanion's Claude Code ACP adapter spawns `claude-agent-acp`. Install
    # it (npm comes from the node install above) to ~/.local/bin so no sudo is
    # needed and it lands on PATH. Gated on the ai component.
    if [[ "$INSTALL_AI" == true ]] && ! command -v claude-agent-acp >/dev/null 2>&1; then
        info "installing claude-agent-acp (CodeCompanion ACP bridge)"
        npm install -g --prefix "$HOME/.local" @agentclientprotocol/claude-agent-acp
    fi

    # Pre-warm lazy.nvim plugins (non-fatal if it fails, e.g. no network).
    if command -v nvim >/dev/null 2>&1 && [[ -f "$nvim_dir/init.lua" ]]; then
        info "pre-warming lazy.nvim plugins (headless)"
        nvim --headless "+Lazy! sync" +qa 2>&1 | tail -5 || warn "lazy sync did not complete cleanly"
    fi
}

main "$@"
