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
# When the ai > codecompanion sub-feature is selected (exported as
# INSTALL_AI_CODECOMPANION by
# home/.chezmoiscripts/run_once_after_00-install.sh.tmpl), the Claude Code ACP
# bridge `claude-agent-acp` is installed too - CodeCompanion's chat adapter spawns it.
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

# Off by default (and for standalone runs); turned on by the ai > codecompanion
# sub-feature in the configure menu.
INSTALL_AI_CODECOMPANION="${INSTALL_AI_CODECOMPANION:-false}"
DOTFILES_NODE_READY="${DOTFILES_NODE_READY:-true}"

_nvim_venv_health() {
    local venv="$1"
    [[ -x "$venv/bin/python" ]] || return 1
    "$venv/bin/python" -c 'import pynvim' >/dev/null 2>&1
}

update_nvim_venv() {
    local target="$1" releases
    local stage release_id release link_tmp previous="" old_link=""
    releases="${target}-releases"
    mkdir -p "$releases"
    stage=$(mktemp -d "$releases/.stage.XXXXXX") || return 1
    if ! python3 -m venv "$stage" \
        || ! "$stage/bin/python" -m pip install --quiet --upgrade pynvim neovim \
        || ! _nvim_venv_health "$stage"; then
        warn "Neovim Python provider staging failed; keeping the current venv"
        rm -rf "$stage"
        return 1
    fi

    release_id="$(date +%s).$$"
    release="$releases/$release_id"
    mv "$stage" "$release" || { rm -rf "$stage"; return 1; }
    link_tmp="${target}.new.$$"
    rm -f "$link_tmp"
    ln -s "$release" "$link_tmp" || return 1

    if [[ -L "$target" ]]; then
        old_link=$(readlink "$target") || { rm -f "$link_tmp"; return 1; }
    elif [[ -e "$target" ]]; then
        previous="$releases/previous-$release_id"
        if ! mv "$target" "$previous"; then
            rm -f "$link_tmp"
            return 1
        fi
    fi
    if ! mv -f "$link_tmp" "$target"; then
        rm -f "$link_tmp"
        if [[ -n "$previous" && ! -e "$target" ]]; then
            mv "$previous" "$target" || true
        fi
        return 1
    fi
    if ! _nvim_venv_health "$target"; then
        rm -f "$target"
        if [[ -n "$old_link" ]]; then
            ln -s "$old_link" "$target" || true
        elif [[ -n "$previous" ]]; then
            mv "$previous" "$target" || true
        fi
        return 1
    fi
}

main() {
    local os
    os=$(os_detect)
    info "install-neovim: $os"
    package_results_reset

    # Packages and standalone binaries are installed by install.sh before this
    # post-install step runs.

    # On Debian: markdownlint-cli2 is not in apt; install via npm.
    if [[ "$os" == "debian" && "$DOTFILES_NODE_READY" == true ]]; then
        package_try "markdownlint-cli2 latest npm release" \
            npm install -g --prefix "$HOME/.local" markdownlint-cli2@latest || true
    elif [[ "$os" == "debian" ]]; then
        package_skip "markdownlint-cli2 npm update; Node.js 24 unavailable"
    fi

    # prettierd: persistent Prettier daemon that conform.nvim shells out to for
    # json/jsonc/yaml formatting. npm-only (no Homebrew formula), so install on
    # both platforms; node comes from the selected package set. The dist-tag is
    # floating, so every approved package run checks and advances it.
    if [[ "$DOTFILES_NODE_READY" == true ]]; then
        package_try "prettierd latest npm release" \
            npm install -g --prefix "$HOME/.local" @fsouza/prettierd@latest || true
    else
        package_skip "prettierd npm update; Node.js 24 unavailable"
    fi

    # Python provider updates stage in a sibling release directory. The stable
    # nvim-venv symlink moves only after pynvim imports successfully.
    local nvim_dir="$HOME/.config/nvim"
    local nvim_venv="$HOME/.local/share/nvim-venv"
    package_try "Neovim Python provider transaction" update_nvim_venv "$nvim_venv" || true

    # luacheck for the pre-commit lua linter (runs as language:system, so it must
    # be on PATH). luacheck 1.2.0 does not run on Lua 5.5; on macOS build it
    # against lua@5.4. Installed to the user rock tree and symlinked into
    # ~/.local/bin (already on PATH per the zsh config).
    mkdir -p "$HOME/.local/bin"
    case "$os" in
        macos)
            package_try "Luacheck latest LuaRocks release" \
                luarocks --lua-version=5.4 --lua-dir "$(brew --prefix lua@5.4)" install --local luacheck || true
            ;;
        debian)
            # apt luarocks pairs with a Lua that luacheck supports (<= 5.4).
            package_try "Luacheck latest LuaRocks release" luarocks install luacheck || true
            ;;
    esac
    # Only symlink if the rock actually installed (guards against a dangling link).
    [[ -e "$HOME/.luarocks/bin/luacheck" ]] && ln -sf "$HOME/.luarocks/bin/luacheck" "$HOME/.local/bin/luacheck"

    # CodeCompanion's Claude Code ACP adapter spawns `claude-agent-acp`. Install
    # it (npm comes from the node install above) to ~/.local/bin so no sudo is
    # needed and it lands on PATH. Gated on the ai > codecompanion sub-feature.
    if [[ "$INSTALL_AI_CODECOMPANION" == true && "$DOTFILES_NODE_READY" == true ]]; then
        package_try "claude-agent-acp latest npm release" \
            npm install -g --prefix "$HOME/.local" @agentclientprotocol/claude-agent-acp@latest || true
    elif [[ "$INSTALL_AI_CODECOMPANION" == true ]]; then
        package_skip "claude-agent-acp npm update; Node.js 24 unavailable"
    fi

    # Pre-warm lazy.nvim plugins (non-fatal if it fails, e.g. no network).
    if command -v nvim >/dev/null 2>&1 && [[ -f "$nvim_dir/init.lua" ]]; then
        package_try "Lazy plugin sync" nvim --headless "+Lazy! sync" +qa || true
        package_try "Treesitter parser and Mason package updates" \
            nvim --headless -l "$SCRIPT_DIR/update-neovim-packages.lua" || true
    else
        package_skip "Neovim plugin updates; nvim or init.lua unavailable"
    fi

    package_results_summary "Neovim package run"
    [[ "$_package_results_failed" -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
