#!/usr/bin/env bash
# scripts/package-plan.sh
# Build the deduped download plan used by both chezmoi init and install.sh.

set -euo pipefail

INSTALL_ZSH="${INSTALL_ZSH:-false}"
INSTALL_TMUX="${INSTALL_TMUX:-false}"
INSTALL_NEOVIM="${INSTALL_NEOVIM:-false}"
INSTALL_NOTIFY="${INSTALL_NOTIFY:-false}"
INSTALL_AI_CODECOMPANION="${INSTALL_AI_CODECOMPANION:-false}"
INSTALL_AI_STATUSLINE="${INSTALL_AI_STATUSLINE:-false}"
INSTALL_TERMINAL_GHOSTTY="${INSTALL_TERMINAL_GHOSTTY:-false}"
INSTALL_TERMINAL_ITERM2="${INSTALL_TERMINAL_ITERM2:-false}"
_plan_mode="${1:---records}"
_status_result=planned
_brew_inventory_loaded=0
_brew_formulae=$'\n'
_brew_casks=$'\n'

_plan_os() {
    if [[ -n "${DOTFILES_PLAN_OS:-}" ]]; then
        printf '%s\n' "$DOTFILES_PLAN_OS"
        return
    fi
    case "$(uname -s)" in
        Darwin) printf 'macos\n' ;;
        Linux)
            command -v apt-get >/dev/null 2>&1 && printf 'debian\n' || printf 'unsupported\n'
            ;;
        *) printf 'unsupported\n' ;;
    esac
}

_load_brew_inventory() {
    local output
    [[ "$_brew_inventory_loaded" -eq 1 ]] && return 0
    _brew_inventory_loaded=1
    command -v brew >/dev/null 2>&1 || return 0

    output=$(brew list --formula 2>/dev/null || true)
    _brew_formulae=$'\n'"$output"$'\n'
    output=$(brew list --cask 2>/dev/null || true)
    _brew_casks=$'\n'"$output"$'\n'
}

_status() {
    local source="$1" name="$2" probe="${3:-}"
    local lookup="${name##*/}"
    _status_result=planned
    [[ "${DOTFILES_PLAN_ASSUME_MISSING:-0}" == 1 ]] && return 0
    [[ "$_plan_mode" == --names ]] && return 0
    case "$source" in
        brew-formula)
            _load_brew_inventory
            [[ "$_brew_formulae" == *$'\n'"$lookup"$'\n'* ]] && _status_result=installed
            ;;
        brew-cask)
            if [[ "$name" == ghostty && -d /Applications/Ghostty.app ]]; then
                _status_result=installed
                return 0
            fi
            _load_brew_inventory
            [[ "$_brew_casks" == *$'\n'"$lookup"$'\n'* ]] && _status_result=installed
            ;;
        apt)
            if command -v dpkg-query >/dev/null 2>&1 &&
                [[ "$(dpkg-query -W -f='${Status}' "$name" 2>/dev/null || true)" == "install ok installed" ]]; then
                _status_result=installed
            fi
            ;;
        github-release)
            command -v "$probe" >/dev/null 2>&1 && _status_result=installed
            ;;
        npm)
            if command -v npm >/dev/null 2>&1 &&
                npm list -g --depth=0 --prefix "$HOME/.local" "$name" >/dev/null 2>&1; then
                _status_result=installed
            fi
            ;;
        pip)
            if [[ -x "$HOME/.local/share/nvim-venv/bin/python" ]] &&
                "$HOME/.local/share/nvim-venv/bin/python" -m pip show "$name" >/dev/null 2>&1; then
                _status_result=installed
            fi
            ;;
        luarocks)
            if command -v luarocks >/dev/null 2>&1 && luarocks show "$name" >/dev/null 2>&1; then
                _status_result=installed
            fi
            ;;
        git-external)
            [[ -e "$probe" ]] && _status_result=installed
            ;;
        neovim-plugin)
            [[ -d "$probe" ]] && _status_result=installed
            ;;
    esac
    # _status communicates only through $_status_result; its exit code is
    # meaningless. Return 0 explicitly: otherwise a not-installed probe leaves the
    # final `[[ ... ]] && ...` short-circuiting to 1, and under `set -e` that aborts
    # _build at the first uninstalled package (e.g. on a fresh machine where git is
    # not yet installed) - which would take confirm-install's plan capture with it.
    return 0
}

_records=()
_seen=()

_add() {
    local source="$1" name="$2" origin="$3" probe="${4:-$2}"
    local key="$source:$name" existing
    if (( ${#_seen[@]} > 0 )); then
        for existing in "${_seen[@]}"; do
            [[ "$existing" == "$key" ]] && return 0
        done
    fi
    _seen+=("$key")
    _status "$source" "$name" "$probe"
    _records+=("$source"$'\t'"$name"$'\t'"$_status_result"$'\t'"$origin")
}

_build() {
    local os
    os=$(_plan_os)
    case "$os" in
        macos)
            _add brew-formula git "Homebrew core"
            _add brew-formula make "Homebrew core"
            _add brew-formula curl "Homebrew core"
            _add brew-formula gum "Homebrew core"
            _add brew-formula chezmoi "Homebrew core"
            if [[ "$INSTALL_ZSH" == true ]]; then
                _add brew-formula zsh "Homebrew core"
                _add brew-formula gh "Homebrew core"
                _add brew-formula zoxide "Homebrew core"
                _add brew-formula gnupg "Homebrew core"
                _add brew-formula fzf "Homebrew core"
            fi
            if [[ "$INSTALL_TMUX" == true ]]; then
                _add brew-formula tmux "Homebrew core"
                _add brew-formula reattach-to-user-namespace "Homebrew core"
                _add brew-formula coreutils "Homebrew core"
                _add brew-formula gawk "Homebrew core"
            fi
            if [[ "$INSTALL_NEOVIM" == true ]]; then
                for pkg in cmake go hadolint llvm lua@5.4 luarocks markdownlint-cli2 neovim node python3 shellcheck yamllint; do
                    _add brew-formula "$pkg" "Homebrew core"
                done
                _add brew-formula terraform-linters/tap/tflint "Homebrew tap terraform-linters/tap"
            fi
            [[ "$INSTALL_NOTIFY" == true ]] && _add brew-formula yq "Homebrew core"
            if [[ "$INSTALL_AI_STATUSLINE" == true ]]; then
                _add brew-formula jq "Homebrew core"
                _add brew-formula python3 "Homebrew core"
            fi
            [[ "$INSTALL_TERMINAL_GHOSTTY" == true ]] && _add brew-cask ghostty "Homebrew cask"
            [[ "$INSTALL_TERMINAL_ITERM2" == true ]] && _add brew-cask iterm2 "Homebrew cask"
            ;;
        debian)
            for pkg in git make curl ca-certificates gum; do
                _add apt "$pkg" "Debian apt repository"
            done
            if [[ "$INSTALL_ZSH" == true ]]; then
                for pkg in zsh gh zoxide gnupg command-not-found fzf; do
                    _add apt "$pkg" "Debian or GitHub CLI apt repository"
                done
            fi
            if [[ "$INSTALL_TMUX" == true ]]; then
                for pkg in tmux xclip wl-clipboard mpg123 gawk net-tools; do
                    _add apt "$pkg" "Debian apt repository"
                done
            fi
            if [[ "$INSTALL_NEOVIM" == true ]]; then
                for pkg in build-essential cmake golang jq luarocks nodejs npm python3 python3-pip python3-venv shellcheck yamllint; do
                    _add apt "$pkg" "Debian apt repository"
                done
                _add github-release neovim "https://github.com/neovim/neovim/releases" nvim
                _add npm markdownlint-cli2 "https://www.npmjs.com/package/markdownlint-cli2"
            fi
            [[ "$INSTALL_NOTIFY" == true ]] && _add github-release yq "https://github.com/mikefarah/yq/releases" yq
            if [[ "$INSTALL_AI_STATUSLINE" == true ]]; then
                _add apt jq "Debian apt repository"
                _add apt python3 "Debian apt repository"
            fi
            ;;
        *)
            printf 'package-plan: unsupported platform\n' >&2
            return 1
            ;;
    esac

    if [[ "$INSTALL_NEOVIM" == true ]]; then
        _add pip pynvim "https://pypi.org/project/pynvim"
        _add pip neovim "https://pypi.org/project/neovim"
        _add luarocks luacheck "https://luarocks.org/modules/mpeterv/luacheck"
        _add neovim-plugin "lazy.nvim plugin set" "GitHub repositories declared in ~/.config/nvim/init.lua" "$HOME/.local/share/nvim/lazy"
    fi
    [[ "$INSTALL_AI_CODECOMPANION" == true ]] &&
        _add npm @agentclientprotocol/claude-agent-acp "https://www.npmjs.com/package/@agentclientprotocol/claude-agent-acp"

    if [[ "$INSTALL_ZSH" == true ]]; then
        _add git-external ohmyzsh/ohmyzsh "https://github.com/ohmyzsh/ohmyzsh.git" "$HOME/.zsh/ohmyzsh"
        _add git-external zsh-users/zsh-autosuggestions "https://github.com/zsh-users/zsh-autosuggestions.git" "$HOME/.zsh/custom/plugins/zsh-autosuggestions"
        _add git-external zsh-users/zsh-syntax-highlighting "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$HOME/.zsh/custom/plugins/zsh-syntax-highlighting"
        _add git-external zsh-users/zsh-completions "https://github.com/zsh-users/zsh-completions.git" "$HOME/.zsh/custom/plugins/zsh-completions"
    fi
    if [[ "$INSTALL_TMUX" == true ]]; then
        _add git-external tmux-plugins/tpm "https://github.com/tmux-plugins/tpm.git" "$HOME/.tmux/plugins/tpm"
        _add git-external tmux-plugins/tmux-sensible "https://github.com/tmux-plugins/tmux-sensible.git" "$HOME/.tmux/plugins/tmux-sensible"
        _add git-external tmux-plugins/tmux-yank "https://github.com/tmux-plugins/tmux-yank.git" "$HOME/.tmux/plugins/tmux-yank"
        _add git-external tmux-plugins/tmux-cpu "https://github.com/tmux-plugins/tmux-cpu.git" "$HOME/.tmux/plugins/tmux-cpu"
        _add git-external xamut/tmux-network-bandwidth "https://github.com/xamut/tmux-network-bandwidth.git" "$HOME/.tmux/plugins/tmux-network-bandwidth"
        _add git-external tmux-plugins/tmux-resurrect "https://github.com/tmux-plugins/tmux-resurrect.git" "$HOME/.tmux/plugins/tmux-resurrect"
    fi
}

_source_label() {
    case "$1" in
        brew-formula) printf 'Homebrew formulae' ;;
        brew-cask) printf 'Homebrew casks' ;;
        apt) printf 'apt packages' ;;
        github-release) printf 'GitHub release binaries' ;;
        npm) printf 'npm globals' ;;
        pip) printf 'Python virtual environment' ;;
        luarocks) printf 'LuaRocks' ;;
        git-external) printf 'chezmoi git externals' ;;
        neovim-plugin) printf 'Neovim plugin sync' ;;
    esac
}

_display() {
    local wanted source name status origin record printed
    printf 'Deduped download plan\n'
    for wanted in brew-formula brew-cask apt github-release npm pip luarocks neovim-plugin git-external; do
        printed=0
        for record in "${_records[@]}"; do
            IFS=$'\t' read -r source name status origin <<< "$record"
            [[ "$source" == "$wanted" ]] || continue
            if [[ "$printed" -eq 0 ]]; then
                printf '\n%s\n' "$(_source_label "$wanted")"
                printed=1
            fi
            printf '  [%s] %s - %s\n' "$status" "$name" "$origin"
        done
    done
}

_names() {
    local wanted="$1" source name status origin record
    for record in "${_records[@]}"; do
        IFS=$'\t' read -r source name status origin <<< "$record"
        [[ "$source" == "$wanted" ]] && printf '%s\n' "$name"
    done
}

_build
case "$_plan_mode" in
    # `|| true`: _display's status is whatever its final loop / `[[ ... ]]`
    # membership test happened to return (a no-match returns 1), which is
    # accidental, not an error. Normalize it so a caller capturing the plan under
    # `set -e` - confirm-install.sh does `plan=$(... --display)` - does not abort
    # on that stray non-zero.
    --display) _display || true ;;
    --records) printf '%s\n' "${_records[@]}" ;;
    --names)
        [[ -n "${2:-}" ]] || { printf 'package-plan: --names requires a source\n' >&2; exit 2; }
        _names "$2"
        ;;
    *) printf 'usage: package-plan.sh --display | --records | --names SOURCE\n' >&2; exit 2 ;;
esac
