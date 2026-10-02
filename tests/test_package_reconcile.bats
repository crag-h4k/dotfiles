#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Bats isolates each test and its exports in a separate subshell.
# No real package installation or metadata requests in these regression tests.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home" XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "current plan entries skip installation and preserve resolved targets" {
  export DOTFILES_PACKAGE_PLAN="$BATS_TEST_TMPDIR/plan"
  printf 'npm\ttool\tinstalled\tfloating\torigin\ttool\t1.2.3\t1.2.3\tcurrent\n' >"$DOTFILES_PACKAGE_PLAN"
  run bash -c 'source "$1/scripts/common.sh"; package_action_try npm tool "tool install" false; package_target npm tool; package_results_summary' _ "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.2.3"* ]]
  [[ "$output" == *"skipped=1"* ]]
}

@test "blocked metadata cannot start installation" {
  export DOTFILES_PACKAGE_PLAN="$BATS_TEST_TMPDIR/plan"
  printf 'npm\ttool\tblocked\tfloating\torigin\ttool\t1.2.3\t-\tregistry unavailable\n' >"$DOTFILES_PACKAGE_PLAN"
  run bash -c 'source "$1/scripts/common.sh"; package_action_try npm tool "tool install" touch "$HOME/should-not-exist"' _ "$ROOT"
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/should-not-exist" ]
  [[ "$output" == *"registry unavailable"* ]]
}

@test "npm resolves the selected prerelease tag and skips the equal installed version" {
  mkdir -p "$HOME/.local/lib/node_modules/@github/copilot" "$HOME/.local/bin"
  printf '{"version":"1.2.3-beta.4"}\n' >"$HOME/.local/lib/node_modules/@github/copilot/package.json"
  printf '#!/bin/sh\nexit 0\n' >"$HOME/.local/bin/copilot"
  chmod +x "$HOME/.local/bin/copilot"
  cat >"$BATS_TEST_TMPDIR/bin/npm" <<'STUB'
#!/bin/sh
[ "$1 $2" = 'view @github/copilot@prerelease' ] || exit 90
printf '"1.2.3-beta.4"\n'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/npm"
  run bash -c 'source "$1/scripts/common.sh"; source "$1/scripts/package-resolve.sh"; name=@github/copilot; probe=copilot; policy=floating; COPILOT_VERSION=prerelease; current=-; candidate=-; _resolve_npm; printf "%s %s\n" "$status" "$candidate"' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = 'installed 1.2.3-beta.4' ]
}

@test "npm failed registry lookup is blocked rather than current" {
  printf '#!/bin/sh\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/npm"
  chmod +x "$BATS_TEST_TMPDIR/bin/npm"
  run bash -c 'source "$1/scripts/common.sh"; source "$1/scripts/package-resolve.sh"; name=tool; probe=tool; policy=floating; current=-; candidate=-; _resolve_npm; printf "%s\n" "$status"' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = blocked ]
}

@test "exact prek pin skips uv installation" {
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\nprintf "prek 0.5.4\\n"\n' >"$HOME/.local/bin/prek"
  printf '#!/bin/sh\nexit 91\n' >"$BATS_TEST_TMPDIR/bin/uv"
  chmod +x "$HOME/.local/bin/prek" "$BATS_TEST_TMPDIR/bin/uv"
  run env DOTFILES_PLAN_OS=debian bash "$ROOT/scripts/install-prek.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"is current"* ]]
}

@test "automatic log records a configuration-only run and viewing it does no work" {
  run env DOTFILES_INSTALL_MODE=configs INSTALL_ZSH=false INSTALL_TMUX=false INSTALL_NEOVIM=false \
    INSTALL_GIT_CONFIG=false INSTALL_TERMINAL_ITERM2=false bash "$ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
  run bash "$ROOT/scripts/install.sh" --log-path
  [ "$status" -eq 0 ]
  local logfile="$output"
  [ -f "$logfile" ]
  [ "$(stat -c '%a' "$logfile" 2>/dev/null || stat -f '%Lp' "$logfile")" = 600 ]
  run bash "$ROOT/scripts/install.sh" --log
  [ "$status" -eq 0 ]
  [[ "$output" == *"configs-only mode"* ]]
  [[ "$output" == *"exit=0"* ]]
  [ "$(find "$XDG_STATE_HOME/dotfiles/install" -type f | wc -l | tr -d ' ')" -eq 1 ]
}

@test "package failure continues to finalizers and returns failure in the log" {
  export DOTFILES_PACKAGE_PLAN="$BATS_TEST_TMPDIR/plan"
  printf 'brew-formula\ttest-package\tplanned\tfloating\torigin\ttest-package\t-\t-\t-\n' >"$DOTFILES_PACKAGE_PLAN"
  printf '#!/bin/sh\nexit 42\n' >"$BATS_TEST_TMPDIR/bin/brew"
  chmod +x "$BATS_TEST_TMPDIR/bin/brew"
  run env DOTFILES_PLAN_OS=macos DOTFILES_ASSUME_YES=1 DOTFILES_INSTALL_MODE=packages \
    INSTALL_ZSH=false INSTALL_TMUX=false INSTALL_NEOVIM=false INSTALL_GIT_CONFIG=true \
    INSTALL_AI_OPENCODE=false INSTALL_AI_COPILOT=false INSTALL_AI_CODECOMPANION=false \
    INSTALL_TERMINAL_ITERM2=false DOTFILES_SOURCE_ROOT="$HOME/no-source" bash "$ROOT/scripts/install.sh"
  [ "$status" -ne 0 ]
  [ -f "$HOME/.gitconfig.override" ]
  run bash "$ROOT/scripts/install.sh" --log
  [ "$status" -eq 0 ]
  [[ "$output" == *"package step(s) failed"* ]]
  [[ "$output" == *"exit=1"* ]]
}

@test "a fully current approved plan never invokes a package manager" {
  export DOTFILES_PACKAGE_PLAN="$BATS_TEST_TMPDIR/current-plan"
  printf 'brew-formula\tgit\tinstalled\tfloating\torigin\tgit\t1.2.3\t1.2.3\tcurrent\n' >"$DOTFILES_PACKAGE_PLAN"
  cat >"$BATS_TEST_TMPDIR/bin/brew" <<'STUB'
#!/bin/sh
exit 92
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/brew"
  run env DOTFILES_PLAN_OS=macos DOTFILES_ASSUME_YES=1 DOTFILES_INSTALL_MODE=packages \
    INSTALL_ZSH=false INSTALL_TMUX=false INSTALL_NEOVIM=false INSTALL_GIT_CONFIG=false \
    INSTALL_AI_OPENCODE=false INSTALL_AI_COPILOT=false INSTALL_AI_CODECOMPANION=false \
    INSTALL_TERMINAL_ITERM2=false DOTFILES_SOURCE_ROOT="$HOME/no-source" bash "$ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Homebrew formula git is current: skipped"* ]]
  [[ "$output" == *"failed=0"* ]]
}

@test "archive source skips palette repair without Git metadata" {
  local source="$BATS_TEST_TMPDIR/archive-source"
  mkdir -p "$source"
  : >"$source/.gitmodules"
  export DOTFILES_PACKAGE_PLAN="$BATS_TEST_TMPDIR/current-plan"
  printf 'brew-formula\tgit\tinstalled\tfloating\torigin\tgit\t1.2.3\t1.2.3\tcurrent\n' >"$DOTFILES_PACKAGE_PLAN"
  cat >"$BATS_TEST_TMPDIR/bin/brew" <<'STUB'
#!/bin/sh
exit 92
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/brew"
  run env DOTFILES_PLAN_OS=macos DOTFILES_ASSUME_YES=1 DOTFILES_INSTALL_MODE=packages \
    INSTALL_ZSH=false INSTALL_TMUX=false INSTALL_NEOVIM=false INSTALL_GIT_CONFIG=false \
    INSTALL_AI_OPENCODE=false INSTALL_AI_COPILOT=false INSTALL_AI_CODECOMPANION=false \
    INSTALL_TERMINAL_ITERM2=false DOTFILES_SOURCE_ROOT="$source" bash "$ROOT/scripts/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"pinned palette submodule"* ]]
  [[ "$output" == *"failed=0"* ]]
}

@test "approval restores the same resolved plan without rechecking versions" {
  export DOTFILES_PACKAGE_PLAN="$BATS_TEST_TMPDIR/approved-plan"
  export DOTFILES_PKG_CONFIRM_SENTINEL="$BATS_TEST_TMPDIR/approval"
  printf 'npm\ttool\tupdate\tfloating\torigin\ttool\t1.2.3\t1.2.4\tversion differs\n' >"$DOTFILES_PACKAGE_PLAN"
  run bash -c 'source "$1/scripts/common.sh"; package_plan_save_approval; expected="$DOTFILES_PACKAGE_PLAN"; unset DOTFILES_PACKAGE_PLAN; pkg_confirm; test "$DOTFILES_PACKAGE_PLAN" = "$expected"; package_target npm tool' _ "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.2.4"* ]]
  [ ! -e "$DOTFILES_PKG_CONFIRM_SENTINEL" ]
}

@test "matching OpenCode version still repairs missing runtime entrypoints" {
  local prefix="$HOME/.local/share/opencode2" config="$HOME/.config/opencode"
  mkdir -p "$prefix/lib/node_modules/@opencode/cli" "$prefix/bin" "$config/node_modules/@opencode/plugin"
  printf '{"version":"1.2.3"}\n' >"$prefix/lib/node_modules/@opencode/cli/package.json"
  printf '#!/bin/sh\nprintf "opencode2 v1.2.3\\n"\n' >"$prefix/bin/opencode2"
  printf '#!/bin/sh\nprintf '\''"1.2.3"\\n'\''\n' >"$BATS_TEST_TMPDIR/bin/npm"
  chmod +x "$prefix/bin/opencode2" "$BATS_TEST_TMPDIR/bin/npm"
  printf '{"version":"1.2.3","exports":{".":{"import":"./index.js"}}}\n' >"$config/node_modules/@opencode/plugin/package.json"
  touch "$config/node_modules/@opencode/plugin/index.js"
  run bash -c 'source "$1/scripts/common.sh"; source "$1/scripts/package-resolve.sh"; name=@opencode/cli; probe=opencode2; policy=floating; OPENCODE2_VERSION=latest; current=-; candidate=-; _resolve_npm; printf "%s\n" "$status"' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = check ]
  for package in @opentui/solid solid-js; do
    mkdir -p "$config/node_modules/$package"
    printf '{"version":"1.0.0","exports":{".":{"import":"./index.js"}}}\n' >"$config/node_modules/$package/package.json"
    touch "$config/node_modules/$package/index.js"
  done
  run bash -c 'source "$1/scripts/common.sh"; source "$1/scripts/package-resolve.sh"; name=@opencode/cli; probe=opencode2; policy=floating; OPENCODE2_VERSION=latest; current=-; candidate=-; _resolve_npm; printf "%s\n" "$status"' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = installed ]
}

@test "Terraform version inspection disables proxy auto-installation" {
  cat >"$BATS_TEST_TMPDIR/bin/terraform" <<'STUB'
#!/bin/sh
[ "$TENV_AUTO_INSTALL" = false ] || exit 91
printf 'Terraform v1.2.3\n'
STUB
  printf '#!/bin/sh\nprintf "1.2.3\\n"\n' >"$BATS_TEST_TMPDIR/bin/tenv"
  chmod +x "$BATS_TEST_TMPDIR/bin/terraform" "$BATS_TEST_TMPDIR/bin/tenv"
  mkdir -p "$HOME/.tenv/Terraform/1.2.3"
  printf '1.2.3\n' >"$HOME/.tenv/Terraform/version"
  cp "$BATS_TEST_TMPDIR/bin/terraform" "$HOME/.tenv/Terraform/1.2.3/terraform"
  # The child shell expands the fixture paths.
  # shellcheck disable=SC2016
  run env TENV_AUTO_INSTALL=true bash -c 'source "$1/scripts/common.sh"; source "$1/scripts/package-resolve.sh"; name=terraform; probe=terraform; policy=floating; current=-; candidate=-; _resolve_release; printf "%s\n" "$status"' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = installed ]
}

@test "GitHub release metadata handles minified and indented JSON with URL first" {
  local digest
  digest=$(printf '%064d' 0)
  cat >"$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then cp "$RELEASE_FIXTURE" "$2"; exit; fi
  shift
done
exit 90
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export RELEASE_FIXTURE="$BATS_TEST_TMPDIR/release.json"
  printf '{"url":"https://api.github.com/repos/example/tool/releases/123","tag_name":"v0.64.0","assets":[{"url":"https://example.invalid/asset","name":"tool.zip","digest":"sha256:%s"}]}\n' "$digest" >"$RELEASE_FIXTURE"
  run bash -c 'source "$1/scripts/common.sh"; github_latest_release_tag example/tool; github_latest_release_asset_sha256 example/tool tool.zip v0.64.0' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "v0.64.0"$'\n'"$digest" ]
  printf '{\n  "url": "https://example.invalid/release",\n  "tag_name": "v0.64.0",\n  "assets": [{"name": "tool.zip", "digest": "sha256:%s"}]\n}\n' "$digest" >"$RELEASE_FIXTURE"
  run bash -c 'source "$1/scripts/common.sh"; github_latest_release_tag example/tool; github_latest_release_asset_sha256 example/tool tool.zip v0.64.0' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "v0.64.0"$'\n'"$digest" ]
  printf '{"tag_name":"https://example.invalid/not-a-version"}\n' >"$RELEASE_FIXTURE"
  run bash -c 'source "$1/scripts/common.sh"; github_latest_release_tag example/tool' _ "$ROOT"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "GitHub release tag falls back to the public latest redirect" {
  cat >"$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/bin/sh
for argument; do url="$argument"; done
case "$url" in
  https://api.github.com/repos/example/tool/releases/latest) exit 22 ;;
  https://github.com/example/tool/releases/latest)
    printf 'https://github.com/example/tool/releases/tag/v1.2.3\n'
    ;;
  *) exit 90 ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  run bash -c 'source "$1/scripts/common.sh"; github_latest_release_tag example/tool' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "v1.2.3" ]
}

@test "Terraform fallback comparison ignores an older project-selected binary" {
  mkdir -p "$HOME/.tenv/Terraform/1.2.3"
  printf '1.2.3\n' >"$HOME/.tenv/Terraform/version"
  printf '#!/bin/sh\nprintf "Terraform v1.2.3\\n"\n' >"$HOME/.tenv/Terraform/1.2.3/terraform"
  printf '#!/bin/sh\nprintf "Terraform v1.0.0\\n"\n' >"$BATS_TEST_TMPDIR/bin/terraform"
  printf '#!/bin/sh\nprintf "1.2.3\\n"\n' >"$BATS_TEST_TMPDIR/bin/tenv"
  chmod +x "$HOME/.tenv/Terraform/1.2.3/terraform" "$BATS_TEST_TMPDIR/bin/terraform" "$BATS_TEST_TMPDIR/bin/tenv"
  run bash -c 'source "$1/scripts/common.sh"; source "$1/scripts/package-resolve.sh"; name=terraform; probe=terraform; policy=floating; current=-; candidate=-; _resolve_release; printf "%s %s\n" "$status" "$current"' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = 'installed 1.2.3' ]
}

@test "Neovim equal version does not hide an unhealthy public launcher" {
  export DOTFILES_NVIM_ROOT="$HOME/nvim"
  export DOTFILES_NVIM_BIN="$BATS_TEST_TMPDIR/bin/nvim"
  mkdir -p "$DOTFILES_NVIM_ROOT/current/bin" "$DOTFILES_NVIM_ROOT/current/share/nvim/runtime"
  cat >"$DOTFILES_NVIM_ROOT/current/bin/nvim" <<'STUB'
#!/bin/sh
[ "$1" != --version ] || printf 'NVIM v1.2.3\n'
exit 0
STUB
  cat >"$DOTFILES_NVIM_BIN" <<'STUB'
#!/bin/sh
if [ "$1" = --version ]; then printf 'NVIM v1.2.3\n'; exit 0; fi
exit 1
STUB
  chmod +x "$DOTFILES_NVIM_ROOT/current/bin/nvim" "$DOTFILES_NVIM_BIN"
  run bash -c 'source "$1/scripts/common.sh"; source "$1/scripts/package-resolve.sh"; github_latest_release_tag() { printf "v1.2.3\n"; }; name=neovim; probe=nvim; policy=floating; current=-; candidate=-; _resolve_release; printf "%s\n" "$status"' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = planned ]
}

@test "LuaRocks resolves only the explicit account tree, including root" {
  mkdir -p "$HOME/.luarocks/bin"
  printf '#!/bin/sh\nexit 0\n' >"$HOME/.luarocks/bin/luacheck"
  chmod +x "$HOME/.luarocks/bin/luacheck"
  cat >"$BATS_TEST_TMPDIR/bin/luarocks" <<'STUB'
#!/bin/sh
# Model the superuser refusal and reject unscoped system-tree inventory.
case "$*" in *--local*) exit 42 ;; esac
[ "$1" = --tree ] && [ "$2" = "$HOME/.luarocks" ] || exit 43
shift 2
case "$1" in
  list|search) printf 'luacheck\t1.2.0-1\tinstalled\t%s\n' "$HOME/.luarocks" ;;
  *) exit 44 ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/luarocks"
  # Variable expansion belongs to the isolated child shell.
  # shellcheck disable=SC2016
  run bash -c 'source "$1/scripts/common.sh"; source "$1/scripts/package-resolve.sh"; _plan_os() { echo debian; }; name=luacheck; probe=luacheck; current=-; candidate=-; _resolve_luarocks; printf "%s %s %s\n" "$status" "$current" "$candidate"' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = 'installed 1.2.0-1 1.2.0-1' ]
}

@test "a system Luacheck does not satisfy the account-tree installation" {
  printf '#!/bin/sh\nexit 0\n' >"$BATS_TEST_TMPDIR/bin/luacheck"
  cat >"$BATS_TEST_TMPDIR/bin/luarocks" <<'STUB'
#!/bin/sh
[ "$1" = --tree ] && [ "$2" = "$HOME/.luarocks" ] || exit 43
case "$3" in
  list) exit 0 ;;
  search) printf 'luacheck\t1.2.0-1\trockspec\tregistry\n' ;;
  *) exit 44 ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/luarocks" "$BATS_TEST_TMPDIR/bin/luacheck"
  # Variable expansion belongs to the isolated child shell.
  # shellcheck disable=SC2016
  run bash -c 'source "$1/scripts/common.sh"; source "$1/scripts/package-resolve.sh"; _plan_os() { echo debian; }; name=luacheck; probe=luacheck; current=-; candidate=-; _resolve_luarocks; printf "%s %s\n" "$status" "$candidate"' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = 'planned 1.2.0-1' ]
  # Pre-approval inspection uses the same account boundary without invoking LuaRocks.
  # shellcheck disable=SC2016
  run env DOTFILES_PLAN_OS=debian DOTFILES_PLAN_APPROVED=0 bash -c 'source "$1/scripts/package-plan.sh" --records >/dev/null; _status luarocks luacheck luacheck; printf "%s\n" "$_status_result"' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = planned ]
}

@test "macOS LuaRocks account inventory still selects Lua 5.4" {
  mkdir -p "$HOME/.luarocks/bin"
  printf '#!/bin/sh\nexit 0\n' >"$HOME/.luarocks/bin/luacheck"
  chmod +x "$HOME/.luarocks/bin/luacheck"
  cat >"$BATS_TEST_TMPDIR/bin/luarocks" <<'STUB'
#!/bin/sh
[ "$1" = --lua-version=5.4 ] && [ "$2" = --tree ] && [ "$3" = "$HOME/.luarocks" ] || exit 43
printf 'luacheck\t1.2.0-1\tinstalled\t%s\n' "$HOME/.luarocks"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/luarocks"
  # Variable expansion belongs to the isolated child shell.
  # shellcheck disable=SC2016
  run bash -c 'source "$1/scripts/common.sh"; source "$1/scripts/package-resolve.sh"; _plan_os() { echo macos; }; name=luacheck; probe=luacheck; current=-; candidate=-; _resolve_luarocks; printf "%s\n" "$status"' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = installed ]
}
