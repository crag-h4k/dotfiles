#!/usr/bin/env bats
# tests/test_package_updates.bats
# Cover package-mode floating, pinned, selected-only, and pre-approval behavior.
# shellcheck source-path=SCRIPTDIR

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
PLANNER="$REPO_ROOT/scripts/package-plan.sh"
COMMON="$REPO_ROOT/scripts/common.sh"
NVIM_INSTALL="$REPO_ROOT/scripts/install-neovim.sh"
OPENCODE2_INSTALL="$REPO_ROOT/scripts/install-opencode2.sh"

write_python3_stub() {
  local path="$1" log="$2"
  cat >"$path" <<STUB
#!/bin/sh
if [ "\$1" = -m ] && [ "\$2" = venv ]; then
  target="\$3"
  mkdir -p "\$target/bin"
  cat >"\$target/bin/python" <<'PY'
#!/bin/sh
printf '%s\\n' "\$*" >>'$log'
if [ "\$1" = -m ] && [ "\$2" = pip ] && [ "\${VENV_PIP_FAIL:-0}" = 1 ]; then
  exit 1
fi
if [ "\$1" = -c ] && [ "\${VENV_IMPORT_FAIL:-0}" = 1 ]; then
  exit 1
fi
exit 0
PY
  chmod +x "\$target/bin/python"
  exit 0
fi
exit 1
STUB
  chmod +x "$path"
}

write_opencode_stubs() {
  local stubs="$1" log="$2"
  cat >"$stubs/npm" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>'$log'
prefix=""
previous=""
for arg in "\$@"; do
  if [ "\$previous" = --prefix ]; then prefix="\$arg"; fi
  previous="\$arg"
done
case "\$1" in
  install)
    if printf '%s\n' "\$*" | grep -q '@opencode/cli@'; then
      mkdir -p "\$prefix/bin"
      cat >"\$prefix/bin/opencode2" <<CLI
#!/bin/sh
printf 'opencode2 v2.0.8\\n'
CLI
      chmod +x "\$prefix/bin/opencode2"
    else
      [ "\${NPM_RUNTIME_FAIL:-0}" = 1 ] && exit 1
      mkdir -p "\$prefix/node_modules/@opencode/plugin" \
        "\$prefix/node_modules/@opentui/solid" "\$prefix/node_modules/solid-js"
      printf '{"name":"@opencode/plugin","version":"2.0.8","main":"index.js"}\n' >"\$prefix/node_modules/@opencode/plugin/package.json"
      printf 'module.exports = {}\n' >"\$prefix/node_modules/@opencode/plugin/index.js"
      printf '{"name":"@opentui/solid","version":"1.0.0","main":"index.js"}\n' >"\$prefix/node_modules/@opentui/solid/package.json"
      printf 'module.exports = {}\n' >"\$prefix/node_modules/@opentui/solid/index.js"
      printf '{"name":"solid-js","version":"1.0.0","main":"index.js"}\n' >"\$prefix/node_modules/solid-js/package.json"
      printf 'module.exports = {}\n' >"\$prefix/node_modules/solid-js/index.js"
    fi
    ;;
esac
exit 0
STUB
  chmod +x "$stubs/npm"
}

@test "pre-approval plan does not invoke package managers" {
  local stubs="$BATS_TEST_TMPDIR/stubs" log="$BATS_TEST_TMPDIR/managers.log"
  mkdir -p "$stubs"
  for manager in brew apt npm pip luarocks; do
    cat >"$stubs/$manager" <<STUB
#!/bin/sh
printf '%s %s\n' '$manager' "\$*" >>'$log'
exit 0
STUB
    chmod +x "$stubs/$manager"
  done
  run env PATH="$stubs:$PATH" DOTFILES_PLAN_OS=macos DOTFILES_PLAN_APPROVED=1 \
    INSTALL_NEOVIM=true INSTALL_AI_OPENCODE=true DOTFILES_TTY="$BATS_TEST_TMPDIR/no-tty" \
    DOTFILES_PKG_CONFIRM_SENTINEL="$BATS_TEST_TMPDIR/no-sentinel" \
    bash -c "source '$COMMON'; pkg_confirm test"
  [ "$status" -ne 0 ]
  [ ! -e "$log" ]
}

@test "package result accounting continues after an independent failure" {
  # shellcheck source=../scripts/common.sh
  source "$COMMON"
  package_results_reset
  package_try first false || true
  package_try second true
  run package_results_summary focused
  [ "$status" -eq 0 ]
  [[ "$output" == *"focused summary: ok=1 failed=1 skipped=0"* ]]
}

@test "planner marks floating, matching, and exact dependencies explicitly" {
  run env DOTFILES_PLAN_OS=debian DOTFILES_PLAN_ASSUME_MISSING=1 \
    INSTALL_NEOVIM=true INSTALL_AI_OPENCODE=true \
    OPENCODE2_VERSION=2.0.8 bash "$PLANNER" --records
  [ "$status" -eq 0 ]
  [[ "$output" == *$'github-release\ttree-sitter-cli\tplanned\tpinned:v0.26.11\t'* ]]
  [[ "$output" == *$'npm\t@opencode/cli\tplanned\tpinned:2.0.8\t'* ]]
  [[ "$output" == *$'npm-runtime\tOpenCode plugin API\tplanned\tfloating:matches-cli\t'* ]]
  [[ "$output" == *$'npm-runtime\tOpenTUI Solid runtime\tplanned\tfloating\t'* ]]
  [[ "$output" == *$'npm\t@fsouza/prettierd\tplanned\tfloating\t'* ]]
}

@test "selected-only planning excludes unselected component dependencies and Cargo" {
  run env DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1 \
    INSTALL_AI_COPILOT=true bash "$PLANNER" --records
  [ "$status" -eq 0 ]
  [[ "$output" == *$'npm\t@github/copilot\t'* ]]
  [[ "$output" == *$'brew-formula\tnode\t'* ]]
  [[ "$output" != *$'git-external\tohmyzsh/ohmyzsh\t'* ]]
  [[ "$output" != *$'neovim-plugin\t'* ]]
  [[ "$output" != *$'cargo\t'* ]]
}

@test "cup uses packageRun re-init without deleting the scriptState bucket" {
  local aliases="$REPO_ROOT/home/dot_zsh/aliases"
  grep -Fq 'alias "cup"="DOTFILES_PACKAGE_UPDATE=1 chezmoi init --apply"' "$aliases"
  grep -Fq 'alias "ccomp"="chezmoi init --apply"' "$aliases"
  run grep -F 'delete-bucket --bucket=scriptState' "$aliases"
  [ "$status" -ne 0 ]
}

@test "every Node-dependent AI feature selects the NodeSource path" {
  # shellcheck source=../scripts/common.sh
  source "$COMMON"
  for feature in INSTALL_AI_CODECOMPANION INSTALL_AI_OPENCODE INSTALL_AI_COPILOT; do
    # Bats intentionally isolates each test in a subshell.
    # shellcheck disable=SC2030
    export INSTALL_NEOVIM=false \
      INSTALL_AI_CODECOMPANION=false \
      INSTALL_AI_OPENCODE=false \
      INSTALL_AI_COPILOT=false
    printf -v "$feature" true
    run node_runtime_selected
    [ "$status" -eq 0 ]
  done
}

@test "Neovim package step refreshes floating npm pip LuaRocks Lazy Treesitter and Mason state" {
  local home="$BATS_TEST_TMPDIR/home" stubs="$BATS_TEST_TMPDIR/stubs"
  local npm_log="$BATS_TEST_TMPDIR/npm.log" pip_log="$BATS_TEST_TMPDIR/pip.log"
  local rock_log="$BATS_TEST_TMPDIR/rock.log" nvim_log="$BATS_TEST_TMPDIR/nvim.log"
  mkdir -p "$home/.config/nvim" "$stubs"
  : >"$home/.config/nvim/init.lua"
  cat >"$stubs/npm" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>'$npm_log'
STUB
  write_python3_stub "$stubs/python3" "$pip_log"
  cat >"$stubs/luarocks" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>'$rock_log'
STUB
  cat >"$stubs/brew" <<'STUB'
#!/bin/sh
if [ "$1" = --prefix ]; then
  printf '/opt/homebrew/opt/lua@5.4\n'
fi
STUB
  cat >"$stubs/nvim" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>'$nvim_log'
STUB
  chmod +x "$stubs"/*

  run env HOME="$home" PATH="$stubs:$PATH" DOTFILES_PLAN_OS=macos \
    INSTALL_AI_CODECOMPANION=true bash "$NVIM_INSTALL"
  [ "$status" -eq 0 ]
  grep -Fq '@fsouza/prettierd@latest' "$npm_log"
  grep -Fq '@agentclientprotocol/claude-agent-acp@latest' "$npm_log"
  grep -Fq -- '-m pip install --quiet --upgrade pynvim' "$pip_log"
  grep -Fq 'install --local luacheck' "$rock_log"
  grep -Fq 'Lazy! sync' "$nvim_log"
  grep -Fq 'update-neovim-packages.lua' "$nvim_log"
}

@test "unready Node skips only Neovim npm work" {
  local home="$BATS_TEST_TMPDIR/no-node-home" stubs="$BATS_TEST_TMPDIR/no-node-stubs"
  local npm_log="$BATS_TEST_TMPDIR/no-node-npm.log" pip_log="$BATS_TEST_TMPDIR/no-node-pip.log"
  local rock_log="$BATS_TEST_TMPDIR/no-node-rock.log" nvim_log="$BATS_TEST_TMPDIR/no-node-nvim.log"
  mkdir -p "$home/.config/nvim" "$stubs"
  : >"$home/.config/nvim/init.lua"
  cat >"$stubs/npm" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>'$npm_log'
exit 1
STUB
  write_python3_stub "$stubs/python3" "$pip_log"
  cat >"$stubs/luarocks" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>'$rock_log'
STUB
  cat >"$stubs/brew" <<'STUB'
#!/bin/sh
[ "$1" = --prefix ] && printf '/opt/homebrew/opt/lua@5.4\n'
STUB
  cat >"$stubs/nvim" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>'$nvim_log'
STUB
  chmod +x "$stubs"/*

  run env HOME="$home" PATH="$stubs:$PATH" DOTFILES_PLAN_OS=macos \
    DOTFILES_NODE_READY=false INSTALL_AI_CODECOMPANION=true bash "$NVIM_INSTALL"
  [ "$status" -eq 0 ]
  [ ! -e "$npm_log" ]
  grep -Fq -- '-m pip install --quiet --upgrade pynvim' "$pip_log"
  grep -Fq 'install --local luacheck' "$rock_log"
  grep -Fq 'Lazy! sync' "$nvim_log"
}

@test "OpenCode 2 stages and activates the CLI and matching runtime" {
  local home="$BATS_TEST_TMPDIR/home" stubs="$BATS_TEST_TMPDIR/stubs"
  local prefix="$home/runtime" config="$home/config" npm_log="$BATS_TEST_TMPDIR/npm.log"
  local old_cli="$home/old/opencode2"
  mkdir -p "$stubs" "$(dirname "$old_cli")" "$config/node_modules" "$home/bin" "$prefix/bin"
  printf 'old runtime\n' >"$config/node_modules/marker"
  cat >"$old_cli" <<'STUB'
#!/bin/sh
printf 'opencode2 v1.0.0\n'
STUB
  chmod +x "$old_cli"
  ln -s "$old_cli" "$prefix/bin/opencode2"
  cp "$REPO_ROOT/home/dot_local/bin/executable_opencode2" "$home/bin/opencode2"
  chmod +x "$home/bin/opencode2"
  write_opencode_stubs "$stubs" "$npm_log"

  run env HOME="$home" PATH="$stubs:$PATH" INSTALL_AI_OPENCODE=true \
    OPENCODE2_VERSION=2.0.8 OPENCODE2_NPM_PREFIX="$prefix" \
    OPENCODE2_WRAPPER="$home/bin/opencode2" OPENCODE2_CONFIG_DIR="$config" \
    bash "$OPENCODE2_INSTALL"
  [ "$status" -eq 0 ]
  grep -Fq 'install -g --prefix' "$npm_log"
  grep -Fq '@opencode/plugin@2.0.8' "$npm_log"
  [ -L "$prefix/bin/opencode2" ]
  [ -L "$config/node_modules" ]
  [ "$(OPENCODE2_NPM_PREFIX="$prefix" "$home/bin/opencode2" --version)" = "opencode2 v2.0.8" ]
  run find "$config/.runtime-releases" -path '*/previous-*/marker' -print
  [ -n "$output" ]
}

@test "failed OpenCode runtime staging preserves the working CLI and runtime" {
  local home="$BATS_TEST_TMPDIR/home" stubs="$BATS_TEST_TMPDIR/stubs"
  local prefix="$home/runtime" config="$home/config" npm_log="$BATS_TEST_TMPDIR/npm.log"
  local old_cli="$home/old/opencode2"
  mkdir -p "$stubs" "$(dirname "$old_cli")" "$config/node_modules" "$home/bin" "$prefix/bin"
  printf 'keep me\n' >"$config/node_modules/marker"
  printf '#!/bin/sh\nprintf "old cli\\n"\n' >"$old_cli"
  chmod +x "$old_cli"
  ln -s "$old_cli" "$prefix/bin/opencode2"
  cp "$REPO_ROOT/home/dot_local/bin/executable_opencode2" "$home/bin/opencode2"
  chmod +x "$home/bin/opencode2"
  write_opencode_stubs "$stubs" "$npm_log"

  run env HOME="$home" PATH="$stubs:$PATH" INSTALL_AI_OPENCODE=true \
    NPM_RUNTIME_FAIL=1 OPENCODE2_VERSION=2.0.8 OPENCODE2_NPM_PREFIX="$prefix" \
    OPENCODE2_WRAPPER="$home/bin/opencode2" OPENCODE2_CONFIG_DIR="$config" \
    bash "$OPENCODE2_INSTALL"
  [ "$status" -ne 0 ]
  [ "$(readlink "$prefix/bin/opencode2")" = "$old_cli" ]
  [ ! -L "$config/node_modules" ]
  [ "$(cat "$config/node_modules/marker")" = "keep me" ]
}

@test "atomic binary replacement leaves no partial destination" {
  # shellcheck source=../scripts/common.sh
  source "$COMMON"
  local source="$BATS_TEST_TMPDIR/source" destination="$BATS_TEST_TMPDIR/bin/tool"
  printf 'new\n' >"$source"
  mkdir -p "$(dirname "$destination")"
  printf 'old\n' >"$destination"
  run atomic_install_binary "$source" "$destination"
  [ "$status" -eq 0 ]
  [ "$(cat "$destination")" = new ]
  [ -x "$destination" ]
  run find "$(dirname "$destination")" -name 'tool.tmp.*' -print
  [ -z "$output" ]
}

@test "failed atomic binary replacement keeps the prior executable" {
  local source="$BATS_TEST_TMPDIR/source" destination="$BATS_TEST_TMPDIR/bin/tool"
  printf 'new\n' >"$source"
  mkdir -p "$(dirname "$destination")"
  printf 'old\n' >"$destination"
  run bash -c "source '$COMMON'; mv() { return 1; }; atomic_install_binary '$source' '$destination'"
  [ "$status" -ne 0 ]
  [ "$(cat "$destination")" = old ]
}

@test "atomic path replacement does not follow a directory symlink" {
  # shellcheck source=../scripts/common.sh
  source "$COMMON"
  local root="$BATS_TEST_TMPDIR/path-swap"
  local target="$root/current" replacement="$root/new"
  mkdir -p "$root/releases/old" "$root/releases/new"
  ln -s releases/old "$target"
  ln -s releases/new "$replacement"

  run atomic_replace_path "$replacement" "$target"

  [ "$status" -eq 0 ]
  [ "$(readlink "$target")" = releases/new ]
  [ ! -e "$replacement" ]
}

@test "portable SHA-256 helper uses stock macOS shasum fallback" {
  # shellcheck source=../scripts/common.sh
  source "$COMMON"
  local stubs="$BATS_TEST_TMPDIR/sha-stubs" file="$BATS_TEST_TMPDIR/payload"
  local expected="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  mkdir -p "$stubs"
  printf 'payload\n' >"$file"
  cat >"$stubs/shasum" <<STUB
#!/bin/sh
printf '%s  %s\n' '$expected' "\${3:-\$2}"
STUB
  chmod +x "$stubs/shasum"
  PATH="$stubs" run sha256_file "$file"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "Neovim venv staging failure preserves the prior venv" {
  # shellcheck source=../scripts/install-neovim.sh
  source "$NVIM_INSTALL"
  local home="$BATS_TEST_TMPDIR/venv-fail" stubs="$BATS_TEST_TMPDIR/venv-stubs"
  local target="$home/nvim-venv" pip_log="$BATS_TEST_TMPDIR/venv-pip.log"
  mkdir -p "$target/bin" "$stubs"
  printf 'working prior\n' >"$target/marker"
  printf '#!/bin/sh\nexit 0\n' >"$target/bin/python"
  chmod +x "$target/bin/python"
  write_python3_stub "$stubs/python3" "$pip_log"
  PATH="$stubs:$PATH" VENV_PIP_FAIL=1 run update_nvim_venv "$target"
  [ "$status" -ne 0 ]
  [ ! -L "$target" ]
  [ "$(cat "$target/marker")" = "working prior" ]
}

@test "Neovim venv transaction repairs a corrupt existing venv" {
  # shellcheck source=../scripts/install-neovim.sh
  source "$NVIM_INSTALL"
  local home="$BATS_TEST_TMPDIR/venv-repair" stubs="$BATS_TEST_TMPDIR/venv-repair-stubs"
  local target="$home/nvim-venv" pip_log="$BATS_TEST_TMPDIR/venv-repair-pip.log"
  mkdir -p "$target" "$stubs"
  printf 'corrupt prior\n' >"$target/marker"
  write_python3_stub "$stubs/python3" "$pip_log"
  PATH="$stubs:$PATH" run update_nvim_venv "$target"
  [ "$status" -eq 0 ]
  [ -L "$target" ]
  [ -x "$target/bin/python" ]
  run find "${target}-releases" -path '*/previous-*/marker' -print
  [ -n "$output" ]
}

@test "Neovim activation rolls back its pointer when wrapper replacement fails" {
  # shellcheck source=../scripts/common.sh
  source "$COMMON"
  local root="$BATS_TEST_TMPDIR/nvim-root" public="$BATS_TEST_TMPDIR/bin/nvim"
  local old="$root/releases/old" stage="$root/releases/.new-stage" stubs="$BATS_TEST_TMPDIR/sudo-stubs"
  mkdir -p "$old/bin" "$old/share/nvim/runtime" "$stage/bin" "$stage/share/nvim/runtime" "$(dirname "$public")" "$stubs"
  printf '#!/bin/sh\nexit 0\n' >"$old/bin/nvim"
  printf '#!/bin/sh\nexit 0\n' >"$stage/bin/nvim"
  printf '#!/bin/sh\nprintf "old public\\n"\n' >"$public"
  chmod +x "$old/bin/nvim" "$stage/bin/nvim" "$public"
  ln -s releases/old "$root/current"
  cat >"$stubs/sudo" <<STUB
#!/bin/sh
last=""
for arg in "\$@"; do last="\$arg"; done
if [ "\$1" = mv ] && [ "\$last" = '$public' ]; then exit 1; fi
exec "\$@"
STUB
  chmod +x "$stubs/sudo"
  PATH="$stubs:$PATH" run activate_neovim_tree "$root" "$public" v2 "$stage"
  [ "$status" -ne 0 ]
  [ "$(readlink "$root/current")" = releases/old ]
  [ "$("$public")" = "old public" ]
  [ -d "$old" ]
}

@test "Neovim activation switches one pointer and retains the prior full tree" {
  # shellcheck source=../scripts/common.sh
  source "$COMMON"
  local root="$BATS_TEST_TMPDIR/nvim-success" public="$BATS_TEST_TMPDIR/nvim-bin/nvim"
  local old="$root/releases/old" stage="$root/releases/.new-stage" stubs="$BATS_TEST_TMPDIR/nvim-sudo"
  mkdir -p "$old/bin" "$old/share/nvim/runtime" "$old/lib" \
    "$stage/bin" "$stage/share/nvim/runtime" "$stage/lib" "$(dirname "$public")" "$stubs"
  printf '#!/bin/sh\nexit 0\n' >"$old/bin/nvim"
  printf '#!/bin/sh\nexit 0\n' >"$stage/bin/nvim"
  printf 'new lib\n' >"$stage/lib/marker"
  printf '#!/bin/sh\nprintf "old public\\n"\n' >"$public"
  chmod +x "$old/bin/nvim" "$stage/bin/nvim" "$public"
  ln -s releases/old "$root/current"
  printf '#!/bin/sh\nexec "$@"\n' >"$stubs/sudo"
  chmod +x "$stubs/sudo"
  PATH="$stubs:$PATH" run activate_neovim_tree "$root" "$public" v2 "$stage"
  [ "$status" -eq 0 ]
  [ "$(readlink "$root/current")" = releases/v2 ]
  [ -d "$old" ]
  [ "$(cat "$root/releases/v2/lib/marker")" = "new lib" ]
  [ -x "$public" ]
  [ -e "${public}.previous" ]
}

@test "Treesitter wait helper rejects a false task result" {
  command -v nvim >/dev/null 2>&1 || skip "nvim not available"
  run nvim --clean --headless -l "$REPO_ROOT/tests/test_neovim_update.lua"
  [ "$status" -eq 0 ]
}

@test "Node-dependent leaf installers refuse an unready Node runtime" {
  local stubs="$BATS_TEST_TMPDIR/leaf-stubs" npm_log="$BATS_TEST_TMPDIR/leaf-npm.log"
  mkdir -p "$stubs"
  cat >"$stubs/npm" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>'$npm_log'
STUB
  chmod +x "$stubs/npm"
  run env PATH="$stubs:$PATH" DOTFILES_NODE_READY=false INSTALL_AI_OPENCODE=true \
    bash "$REPO_ROOT/scripts/install-opencode2.sh"
  [ "$status" -eq 2 ]
  run env PATH="$stubs:$PATH" DOTFILES_NODE_READY=false INSTALL_AI_COPILOT=true \
    bash "$REPO_ROOT/scripts/install-copilot.sh"
  [ "$status" -eq 2 ]
  [ ! -e "$npm_log" ]
}

@test "top-level installer skips only Node-dependent AI work after failed verification" {
  local root="$BATS_TEST_TMPDIR/top-node" home="$BATS_TEST_TMPDIR/top-node-home"
  local stubs="$BATS_TEST_TMPDIR/top-node-stubs" npm_log="$BATS_TEST_TMPDIR/top-node-npm.log"
  mkdir -p "$root" "$home" "$stubs"
  cp -R "$REPO_ROOT/scripts" "$root/scripts"
  cat >"$stubs/brew" <<'STUB'
#!/bin/sh
case "$*" in
  "list --formula"|"list --cask"|"outdated --formula --quiet"|"outdated --cask --quiet") exit 0 ;;
esac
exit 0
STUB
  cat >"$stubs/node" <<'STUB'
#!/bin/sh
printf 'v23.0.0\n'
STUB
  cat >"$stubs/npm" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>'$npm_log'
STUB
  chmod +x "$stubs"/*
  run env HOME="$home" PATH="$stubs:$PATH" DOTFILES_PLAN_OS=macos \
    DOTFILES_INSTALL_MODE=packages DOTFILES_ASSUME_YES=1 \
    INSTALL_ZSH=false INSTALL_TMUX=false INSTALL_NEOVIM=false INSTALL_NOTIFY=false \
    INSTALL_AI_CODECOMPANION=false INSTALL_AI_STATUSLINE=false INSTALL_AI_OPENCODE=true \
    INSTALL_AI_COPILOT=false \
    INSTALL_TERMINAL_GHOSTTY=false INSTALL_TERMINAL_ITERM2=false \
    bash "$root/scripts/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OpenCode V2 CLI and matching runtime; Node.js 24 unavailable: skipped"* ]]
  run grep -E '(^|[[:space:]])(install|ci)([[:space:]]|$)' "$npm_log"
  [ "$status" -ne 0 ]
}
