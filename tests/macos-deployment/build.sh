#!/usr/bin/env bash
# Prepare and render the exact clean source tree used by the native macOS
# deployment job. Keeping this separate from installation makes build, install,
# and runtime smoke results visible independently in the PR summary.
set -euo pipefail

fail() {
    printf 'macOS deployment build: %s\n' "$*" >&2
    exit 1
}

[[ "$(uname -s)" == Darwin ]] || fail "must run on macOS"
[[ ! -t 0 ]] || fail "stdin must be non-interactive"
[[ "$#" -eq 1 ]] || fail "usage: build.sh TARGET_SOURCE_DIR"

for command_name in chezmoi rsync tar; do
    command -v "$command_name" >/dev/null ||
        fail "required command missing: $command_name"
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
target_source="$1"
[[ ! -e "$target_source" ]] ||
    fail "target source already exists: $target_source"

mkdir -p "$target_source"
rsync -a \
    --exclude .git \
    --exclude vendor \
    "$repo_root/" "$target_source/"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-macos-build.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
config_file="$work_dir/chezmoi.toml"
generated_config="$work_dir/generated-chezmoi.toml"
render_home="$work_dir/home"
archive_file="$work_dir/dotfiles-macos.tar"
mkdir -p "$render_home"

printf '%s\n' \
    '[data]' \
    'componentSelection = "1 2 4"' \
    'gitSelection = "1 3"' \
    'aiSelection = ""' \
    'terminalSelection = ""' \
    'palette = "dracula"' \
    'zshTheme = "gud"' \
    'installMode = "packages"' \
    >"$config_file"

# `archive` consumes resolved template data; it does not itself regenerate
# .chezmoi.toml.tmpl. Run the non-applying init phase first so the selected
# component numbers become the nested data.components table used by
# .chezmoiignore.
DOTFILES_INSTALL_MODE=packages DOTFILES_NO_TUI=1 \
    chezmoi \
    --source "$target_source" \
    --config "$config_file" \
    --destination "$render_home" \
    --refresh-externals=never \
    init \
    --config-path "$generated_config" \
    --no-tty

chezmoi \
    --source "$target_source" \
    --config "$generated_config" \
    --destination "$render_home" \
    --refresh-externals=never \
    archive \
    --format tar \
    --output "$archive_file"

archive_listing=$(tar -tf "$archive_file")
for rendered_file in .zshrc .tmux.conf .gitconfig .gitignore_global; do
    printf '%s\n' "$archive_listing" | grep -Eq "(^|/)${rendered_file}$" ||
        fail "rendered archive is missing $rendered_file"
done
if printf '%s\n' "$archive_listing" |
    grep -Eq '(^|/)\.config/nvim/init\.lua$'; then
    fail "rendered archive unexpectedly contains Neovim configuration"
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf 'DOTFILES_SOURCE=%s\n' "$target_source" >>"$GITHUB_ENV"
fi

printf 'macOS source and rendered archive passed build validation\n'
