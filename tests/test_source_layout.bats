#!/usr/bin/env bats
# Guard the repository/source-root boundary introduced by .chezmoiroot.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SOURCE_ROOT="$REPO_ROOT/home"

@test "repository declares home as the chezmoi source root" {
  [ "$(tr -d '\r\n' < "$REPO_ROOT/.chezmoiroot")" = "home" ]

  run chezmoi execute-template --source "$REPO_ROOT" \
    '{{ .chezmoi.sourceDir }}'
  [ "$status" -eq 0 ]
  [ "$output" = "$SOURCE_ROOT" ]
}

@test "chezmoi special files and hooks live beneath home" {
  for source_path in \
    .chezmoi.toml.tmpl \
    .chezmoidata/palettes.yaml \
    .chezmoiexternal.toml \
    .chezmoiignore \
    .chezmoiremove \
    .chezmoiscripts/run_before_00-backup.sh \
    .chezmoiscripts/run_after_00-install.sh.tmpl \
    .chezmoiscripts/run_after_01-finalize-agent-skills.sh.tmpl \
    .chezmoiscripts/run_after_02-ensure-dirs.sh.tmpl \
    .chezmoitemplates/dotfiles-dir; do
    [ -f "$SOURCE_ROOT/$source_path" ]
    [ ! -e "$REPO_ROOT/$source_path" ]
  done
}

@test "project infrastructure stays outside the managed source root" {
  for project_path in .github config docs scripts tests vendor; do
    [ -e "$REPO_ROOT/$project_path" ]
    [ ! -e "$SOURCE_ROOT/$project_path" ]
  done

  for linter_config in gitleaks.toml luacheckrc markdownlint.yaml stylua.toml; do
    [ -f "$REPO_ROOT/config/linters/$linter_config" ]
  done
}

@test "Lazygit renders the selected palette and macOS links to the shared config" {
  local config="${BATS_TEST_TMPDIR}/chezmoi.toml" output
  printf '[data]\npalette="nord"\n' > "$config"
  run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    < "$SOURCE_ROOT/dot_config/lazygit/config.yml.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'activeBorderColor: ["#b48ead", bold]'* ]]
  [[ "$output" == *'autoFetch: false'* ]]
  [[ "$output" == *'autoForwardBranches: none'* ]]
  [[ "$output" == *'method: never'* ]]

  local link="$SOURCE_ROOT/Library/Application Support/lazygit/symlink_config.yml"
  [ "$(cat "$link")" = '../../../.config/lazygit/config.yml' ]
  [ "$(cd "$(dirname "$link")/../../.." && pwd)/dot_config/lazygit/config.yml.tmpl" = \
    "$SOURCE_ROOT/dot_config/lazygit/config.yml.tmpl" ]

  run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    --override-data '{"chezmoi":{"os":"linux"}}' < "$SOURCE_ROOT/.chezmoiignore"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Library/Application Support'* ]]
  run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    --override-data '{"chezmoi":{"os":"darwin"}}' < "$SOURCE_ROOT/.chezmoiignore"
  [ "$status" -eq 0 ]
  [[ "$output" != *'Library/Application Support'* ]]
}

@test "OpenCode CLI seeds Shift+Tab for native agent cycling on the home screen" {
  local config="${BATS_TEST_TMPDIR}/chezmoi.toml" script="${BATS_TEST_TMPDIR}/merge-cli.py" output
  printf '[data]\n' > "$config"
  chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    < "$SOURCE_ROOT/dot_config/opencode/modify_private_cli.json.tmpl" > "$script"
  run bash -c 'printf "{}" | python3 "$1"' _ "$script"
  [ "$status" -eq 0 ]
  output="$(printf '%s' "$output" | jq -r '.keybinds["agent.cycle"]')"
  [ "$output" = shift+tab ]
}

@test "Ghostty config leaves Cmd+Enter at its default on both platforms" {
  local config="${BATS_TEST_TMPDIR}/chezmoi.toml" xdg="${BATS_TEST_TMPDIR}/xdg" os
  local template="$SOURCE_ROOT/dot_config/ghostty/config.tmpl"
  printf '[data]\n' > "$config"
  mkdir -p "$xdg/ghostty/themes" "${BATS_TEST_TMPDIR}/home"
  chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    < "$SOURCE_ROOT/dot_config/ghostty/themes/dotfiles.conf.tmpl" > "$xdg/ghostty/themes/dotfiles.conf"

  for os in darwin linux; do
    run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
      --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" < "$template"
    [ "$status" -eq 0 ]
    # OpenCode sends a prompt with Option+Enter, so nothing here binds or unbinds
    # Cmd+Enter. Ghostty keeps its fullscreen default; a host that wants the chord
    # for itself unbinds it in override.conf.
    [[ "$output" != *'cmd+enter='* ]]
    [[ "$output" != *'super+enter='* ]]
    printf '%s\n' "$output" > "$xdg/ghostty/config"

    # Let Ghostty judge the rendered copy where it is installed. A throwaway HOME
    # and XDG dir keep the live config out of the check.
    if command -v ghostty >/dev/null 2>&1; then
      run env XDG_CONFIG_HOME="$xdg" HOME="${BATS_TEST_TMPDIR}/home" \
        ghostty +validate-config --config-file="$xdg/ghostty/config"
      [ "$status" -eq 0 ]
    fi
  done
}

@test "Trixie bootstraps Python before selected configuration merges run" {
  run python3 - "$REPO_ROOT/tests/trixie-deployment/Dockerfile.trixie" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
install = source.split("apt-get install -y --no-install-recommends", 1)[1].split("&&", 1)[0]
packages = install.replace("\\", " ").split()
assert "python3" in packages
assert source.index("python3") < source.index("USER dotfiles")
PY
  [ "$status" -eq 0 ]
}
