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

# ---- Option as Alt: left Option is Alt on macOS, Linux untouched --------------
@test "Ghostty makes only the left Option key Alt, and only on macOS" {
  local config="${BATS_TEST_TMPDIR}/chezmoi.toml" xdg="${BATS_TEST_TMPDIR}/xdg" os
  local template="$SOURCE_ROOT/dot_config/ghostty/config.tmpl" settings
  printf '[data]\n' > "$config"
  mkdir -p "$xdg/ghostty/themes" "${BATS_TEST_TMPDIR}/home"
  chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    < "$SOURCE_ROOT/dot_config/ghostty/themes/dotfiles.conf.tmpl" > "$xdg/ghostty/themes/dotfiles.conf"

  for os in darwin linux; do
    run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
      --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" < "$template"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" > "$xdg/ghostty/config"
    settings="$(grep -E '^[[:space:]]*macos-option-as-alt[[:space:]]*=' "$xdg/ghostty/config" || true)"
    if [ "$os" = darwin ]; then
      # Exactly one setting, and it is `left`: right Option keeps typing accents.
      [ "$settings" = "macos-option-as-alt = left" ]
    else
      [ -z "$settings" ]
    fi

    if command -v ghostty >/dev/null 2>&1; then
      run env XDG_CONFIG_HOME="$xdg" HOME="${BATS_TEST_TMPDIR}/home" \
        ghostty +validate-config --config-file="$xdg/ghostty/config"
      [ "$status" -eq 0 ]
    fi
  done
}

@test "Ghostty login LaunchAgent is macOS-only, follows the ghostty selection, and starts windowless" {
  local config="${BATS_TEST_TMPDIR}/chezmoi.toml"
  local target="Library/LaunchAgents/io.github.crag-h4k.dotfiles.ghostty.plist"
  printf '[data]\n' > "$config"

  run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    --override-data '{"chezmoi":{"os":"darwin"}}' < "$SOURCE_ROOT/.chezmoiignore"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$target"* ]]

  run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    --override-data '{"chezmoi":{"os":"linux"}}' < "$SOURCE_ROOT/.chezmoiignore"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$target"* ]]

  run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    --override-data '{"chezmoi":{"os":"darwin"},"components":{"terminal":{"ghostty":false}}}' \
    < "$SOURCE_ROOT/.chezmoiignore"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$target"* ]]

  if command -v plutil >/dev/null 2>&1; then
    run plutil -lint "$SOURCE_ROOT/$target"
    [ "$status" -eq 0 ]
  fi

  # The agent only helps if Ghostty comes up in the background with no window;
  # a foreground launch or an initial window would be worse than no agent.
  run python3 - "$SOURCE_ROOT/$target" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    agent = plistlib.load(handle)

args = agent["ProgramArguments"]
assert agent["RunAtLoad"] is True
assert args[0] == "/usr/bin/open"
assert "-g" in args
assert "com.mitchellh.ghostty" in args
assert args[args.index("--args") + 1:] == ["--initial-window=false"]
PY
  [ "$status" -eq 0 ]
}

@test "Ghostty quick-hide agent follows the ghostty selection and replaces native autohide on macOS" {
  local config="${BATS_TEST_TMPDIR}/chezmoi.toml" os target
  local plist_source="$SOURCE_ROOT/Library/LaunchAgents/io.github.crag-h4k.dotfiles.ghostty-quick-hide.plist.tmpl"
  local script_source="$SOURCE_ROOT/dot_local/bin/executable_ghostty-quick-hide"
  local template="$SOURCE_ROOT/dot_config/ghostty/config.tmpl"
  printf '[data]\n' > "$config"

  # Targets must be ignored everywhere except macOS with Ghostty selected.
  for target in \
    Library/LaunchAgents/io.github.crag-h4k.dotfiles.ghostty-quick-hide.plist \
    .local/bin/ghostty-quick-hide; do
    run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
      --override-data '{"chezmoi":{"os":"darwin"}}' < "$SOURCE_ROOT/.chezmoiignore"
    [ "$status" -eq 0 ]
    [[ "$output" != *"$target"* ]]

    run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
      --override-data '{"chezmoi":{"os":"linux"}}' < "$SOURCE_ROOT/.chezmoiignore"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$target"* ]]

    run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
      --override-data '{"chezmoi":{"os":"darwin"},"components":{"terminal":{"ghostty":false}}}' \
      < "$SOURCE_ROOT/.chezmoiignore"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$target"* ]]
  done

  # Native autohide is off only where the agent replaces it. Both halves are
  # needed: autohide on plus the agent double-toggles, autohide off without the
  # agent never hides the dropdown.
  for os in darwin linux; do
    run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
      --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" < "$template"
    [ "$status" -eq 0 ]
    if [ "$os" = darwin ]; then
      [[ "$output" == *$'\nquick-terminal-autohide = false\n'* ]]
      [[ "$output" != *$'\nquick-terminal-autohide = true\n'* ]]
    else
      [[ "$output" == *$'\nquick-terminal-autohide = true\n'* ]]
      [[ "$output" != *$'\nquick-terminal-autohide = false\n'* ]]
    fi
  done

  run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    --override-data '{"chezmoi":{"os":"darwin","homeDir":"/Users/example"}}' < "$plist_source"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "${BATS_TEST_TMPDIR}/quick-hide.plist"
  if command -v plutil >/dev/null 2>&1; then
    run plutil -lint "${BATS_TEST_TMPDIR}/quick-hide.plist"
    [ "$status" -eq 0 ]
  fi
  run python3 - "${BATS_TEST_TMPDIR}/quick-hide.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    agent = plistlib.load(handle)

# osascript, not the script's shebang, so the Automation grant belongs to the
# stable Apple-signed binary and a launchd run does not depend on shebang parsing.
assert agent["ProgramArguments"] == [
    "/usr/bin/osascript", "-l", "JavaScript", "/Users/example/.local/bin/ghostty-quick-hide",
]
assert agent["RunAtLoad"] is True
assert agent["KeepAlive"] is True
assert agent["StandardOutPath"].startswith("/Users/example/Library/Logs/")
PY
  [ "$status" -eq 0 ]

  [ "$(head -n 1 "$script_source")" = '#!/usr/bin/osascript -l JavaScript' ]
  if command -v osacompile >/dev/null 2>&1; then
    run osacompile -l JavaScript -o "${BATS_TEST_TMPDIR}/quick-hide.scpt" "$script_source"
    [ "$status" -eq 0 ]
  fi
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
