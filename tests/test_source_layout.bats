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
    .chezmoiscripts/run_after_00-install.sh.tmpl; do
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
  [[ "$output" == *'Library/Application Support/lazygit/config.yml'* ]]
  run chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    --override-data '{"chezmoi":{"os":"darwin"}}' < "$SOURCE_ROOT/.chezmoiignore"
  [ "$status" -eq 0 ]
  [[ "$output" != *'Library/Application Support/lazygit/config.yml'* ]]
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
