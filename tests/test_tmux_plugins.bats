# tests/test_tmux_plugins.bats
# Exercise adopter plugin overrides against an isolated copy of the installed
# TPM implementation and a named scratch tmux socket.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
TMUX_CONF="${REPO_ROOT}/home/dot_tmux.conf"
IGNORE="${REPO_ROOT}/home/.chezmoiignore"
PLANNER="${REPO_ROOT}/scripts/package-plan.sh"
TPM_SOURCE="${TPM_TEST_SOURCE:-${HOME}/.tmux/plugins/tpm}"
TPM_WRAPPER="${REPO_ROOT}/home/dot_tmux/bin/executable_tpm-local-plugins"
TPM_POLICY="${REPO_ROOT}/home/dot_tmux/bin/executable_tpm-local-policy"

PLUGIN_SPECS=(
  "@dotfiles_plugin_tmux_sensible:tmux-plugins/tmux-sensible:tmux-sensible"
  "@dotfiles_plugin_tmux_yank:tmux-plugins/tmux-yank:tmux-yank"
  "@dotfiles_plugin_tmux_cpu:tmux-plugins/tmux-cpu:tmux-cpu"
  "@dotfiles_plugin_tmux_network_bandwidth:xamut/tmux-network-bandwidth:tmux-network-bandwidth"
  "@dotfiles_plugin_tmux_resurrect:tmux-plugins/tmux-resurrect:tmux-resurrect"
)

setup() {
  TEST_ROOT="${BATS_TEST_TMPDIR}/tmux-plugins-${BATS_TEST_NUMBER}"
  TEST_HOME="${TEST_ROOT}/home"
  TEST_BIN="${TEST_ROOT}/bin"
  SOCKET=""
  ZSH_BIN="$(command -v zsh || true)"
  rm -rf "$TEST_ROOT"
  mkdir -p "$TEST_HOME/.tmux/conf.d" "$TEST_HOME/.tmux/plugins" "$TEST_BIN"
}

teardown() {
  if [[ -n "$SOCKET" ]] && command -v tmux >/dev/null 2>&1; then
    env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
      tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  fi
}

runtime_missing() {
  local message="$1"

  if [[ "${TPM_TEST_REQUIRED:-false}" == true ]]; then
    printf 'required TPM runtime missing: %s\n' "$message" >&2
    return 1
  fi
  skip "$message"
}

require_tpm_runtime() {
  command -v tmux >/dev/null 2>&1 || {
    runtime_missing "tmux not installed"
    return
  }
  if [[ -z "$ZSH_BIN" ]]; then
    runtime_missing "zsh not installed"
    return
  fi
  if [[ ! -x "$TPM_SOURCE/tpm" ]]; then
    runtime_missing "TPM source not found at $TPM_SOURCE"
    return
  fi
}

create_plugin() {
  local plugin_name="$1"
  local marker="${plugin_name//-/_}"
  local plugin_dir="$TEST_HOME/.tmux/plugins/$plugin_name"

  mkdir -p "$plugin_dir"
  cat > "$plugin_dir/$plugin_name.tmux" <<EOF
#!/usr/bin/env zsh
tmux set-option -gq @test_loaded_${marker} yes
EOF
  chmod +x "$plugin_dir/$plugin_name.tmux"
}

prepare_runtime() {
  local conf_name spec plugin_name

  cp "$TMUX_CONF" "$TEST_HOME/.tmux.conf"
  for conf_name in clipboard scrollback status notify; do
    : > "$TEST_HOME/.tmux/conf.d/$conf_name.conf"
  done
  cp -R "$TPM_SOURCE" "$TEST_HOME/.tmux/plugins/tpm"
  mkdir -p "$TEST_HOME/.tmux/bin"
  cp "$TPM_WRAPPER" "$TEST_HOME/.tmux/bin/tpm-local-plugins"
  cp "$TPM_POLICY" "$TEST_HOME/.tmux/bin/tpm-local-policy"

  for spec in "${PLUGIN_SPECS[@]}"; do
    IFS=: read -r _ _ plugin_name <<<"$spec"
    create_plugin "$plugin_name"
  done
}

start_server() {
  local suffix="${1:-runtime}"

  SOCKET="dotfiles-plugins-${BATS_TEST_NUMBER}-${BASHPID}-${suffix}"
  env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH \
    HOME="$TEST_HOME" \
    SHELL="$ZSH_BIN" \
    TERM=xterm-256color \
    tmux -L "$SOCKET" -f "$TEST_HOME/.tmux.conf" \
    new-session -d -s dotfiles-test
}

stop_server() {
  env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
    tmux -L "$SOCKET" kill-server
  SOCKET=""
}

tmux_value() {
  local option="$1"

  env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
    tmux -L "$SOCKET" show-options -gqv "$option"
}

expected_managed_plugins() {
  local spec plugin_repo
  local plugins="tmux-plugins/tpm"

  for spec in "${PLUGIN_SPECS[@]}"; do
    IFS=: read -r _ plugin_repo _ <<<"$spec"
    plugins+=" $plugin_repo"
  done
  printf '%s\n' "$plugins"
}

@test "tmux config builds plugins after overrides and runs TPM last" {
  local override_line managed_line tpm_line last_executable

  run grep -Eq \
    '^[[:space:]]*set(-option)?[[:space:]]+-g[[:space:]]+@plugin' \
    "$TMUX_CONF"
  [[ "$status" -eq 1 ]]

  override_line=$(grep -n '^source-file -q ~/.tmux/conf.d/override.conf$' \
    "$TMUX_CONF" | cut -d: -f1)
  managed_line=$(grep -n "^set -g @tpm_plugins 'tmux-plugins/tpm'$" \
    "$TMUX_CONF" | cut -d: -f1)
  tpm_line=$(grep -n "^run-shell 'if \[ -x .*plugins/tpm/tpm" \
    "$TMUX_CONF" | cut -d: -f1)
  last_executable=$(grep -Ev '^[[:space:]]*(#|$)' "$TMUX_CONF" | tail -n 1)

  (( override_line < managed_line ))
  (( managed_line < tpm_line ))
  [[ "$last_executable" == *'plugins/tpm/tpm'* ]]
  [[ "$last_executable" == *'bin/tpm-local-policy'* ]]
}

@test "tmux plugin runtimes are installer-owned and ignored by chezmoi" {
  local spec plugin_name output

  grep -Fxq '.tmux/plugins' "$IGNORE"
  run env DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1 \
    INSTALL_TMUX=true INSTALL_ZSH=false INSTALL_NEOVIM=false bash "$PLANNER" --records
  [[ "$status" -eq 0 ]]
  [[ "$output" == *$'git-runtime\ttmux-plugins/tpm\tplanned\tfloating\t'* ]]
  for spec in "${PLUGIN_SPECS[@]}"; do
    IFS=: read -r _ plugin_name _ <<<"$spec"
    [[ "$output" == *$'git-runtime\t'"$plugin_name"$'\tplanned\tfloating\t'* ]]
  done
}

@test "managed plugins load by default when override.conf is absent" {
  local spec plugin_name marker

  require_tpm_runtime
  prepare_runtime
  start_server defaults

  [[ ! -e "$TEST_HOME/.tmux/conf.d/override.conf" ]]
  [[ "$(tmux_value @tpm_plugins)" == "$(expected_managed_plugins)" ]]
  for spec in "${PLUGIN_SPECS[@]}"; do
    IFS=: read -r _ _ plugin_name <<<"$spec"
    marker="${plugin_name//-/_}"
    [[ "$(tmux_value "@test_loaded_${marker}")" == yes ]]
  done
}

@test "each managed plugin can be disabled independently" {
  local spec switch_name plugin_repo plugin_name marker plugins
  local other_spec other_repo other_name other_marker

  require_tpm_runtime
  prepare_runtime

  for spec in "${PLUGIN_SPECS[@]}"; do
    IFS=: read -r switch_name plugin_repo plugin_name <<<"$spec"
    printf 'set -g %s off\n' "$switch_name" \
      > "$TEST_HOME/.tmux/conf.d/override.conf"

    start_server "$plugin_name"
    marker="${plugin_name//-/_}"
    plugins="$(tmux_value @tpm_plugins)"
    [[ "$plugins" != *"$plugin_repo"* ]]
    [[ -z "$(tmux_value "@test_loaded_${marker}")" ]]
    for other_spec in "${PLUGIN_SPECS[@]}"; do
      IFS=: read -r _ other_repo other_name <<<"$other_spec"
      [[ "$other_name" == "$plugin_name" ]] && continue
      other_marker="${other_name//-/_}"
      [[ "$plugins" == *"$other_repo"* ]]
      [[ "$(tmux_value "@test_loaded_${other_marker}")" == yes ]]
    done
    stop_server
  done
}

@test "disabling a loaded plugin needs a fresh tmux server" {
  local plugin_script root_bindings

  require_tpm_runtime
  prepare_runtime
  plugin_script="$TEST_HOME/.tmux/plugins/tmux-cpu/tmux-cpu.tmux"
  cat > "$plugin_script" <<'ZSH'
#!/usr/bin/env zsh
tmux set-option -gq @test_cpu_runtime_option loaded
tmux bind-key -n F12 display-message plugin-owned-binding
ZSH
  chmod +x "$plugin_script"

  start_server reload
  [[ "$(tmux_value @test_cpu_runtime_option)" == loaded ]]
  root_bindings=$(env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
    tmux -L "$SOCKET" list-keys -T root)
  [[ "$root_bindings" == *plugin-owned-binding* ]]

  printf 'set -g @dotfiles_plugin_tmux_cpu off\n' \
    > "$TEST_HOME/.tmux/conf.d/override.conf"
  env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
    tmux -L "$SOCKET" source-file "$TEST_HOME/.tmux.conf"

  [[ "$(tmux_value @test_cpu_runtime_option)" == loaded ]]
  root_bindings=$(env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
    tmux -L "$SOCKET" list-keys -T root)
  [[ "$root_bindings" == *plugin-owned-binding* ]]

  stop_server
  start_server fresh-disable
  [[ -z "$(tmux_value @test_cpu_runtime_option)" ]]
  root_bindings=$(env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
    tmux -L "$SOCKET" list-keys -T root)
  [[ "$root_bindings" != *plugin-owned-binding* ]]
}

@test "literal local plugin and its options are available before startup" {
  local plugin_dir

  require_tpm_runtime
  prepare_runtime
  plugin_dir="$TEST_HOME/.tmux/plugins/local-plugin"
  mkdir -p "$plugin_dir"
  cat > "$plugin_dir/local-plugin.tmux" <<'ZSH'
#!/usr/bin/env zsh
value="$(tmux show-option -gqv @local_plugin_option)"
tmux set-option -gq @test_local_plugin_option "$value"
ZSH
  chmod +x "$plugin_dir/local-plugin.tmux"
  cat > "$TEST_HOME/.tmux/conf.d/override.conf" <<'TMUX'
set -g @local_plugin_option ready-before-startup
set -g @plugin 'adopter/local-plugin'
TMUX

  start_server local

  [[ "$(tmux_value @test_local_plugin_option)" == ready-before-startup ]]
}

@test "managed plugin options from override.conf exist before startup" {
  local plugin_script

  require_tpm_runtime
  prepare_runtime
  plugin_script="$TEST_HOME/.tmux/plugins/tmux-resurrect/tmux-resurrect.tmux"
  cat > "$plugin_script" <<'ZSH'
#!/usr/bin/env zsh
value="$(tmux show-option -gqv @resurrect-capture-pane-contents)"
tmux set-option -gq @test_resurrect_option "$value"
tmux set-option -gq @resurrect-capture-pane-contents plugin-overwrite
ZSH
  chmod +x "$plugin_script"
  cat > "$TEST_HOME/.tmux/conf.d/override.conf" <<'TMUX'
set -g @resurrect-capture-pane-contents 'on'
TMUX

  start_server managed-option

  [[ "$(tmux_value @test_resurrect_option)" == on ]]
  [[ "$(tmux_value @resurrect-capture-pane-contents)" == plugin-overwrite ]]
}

@test "safe TPM commands update and clean only local plugins" {
  local socket_path manager_path original_plugins
  local prefix_bindings install_binding update_binding clean_binding git_log
  local managed_name
  local managed_names=(
    tpm
    tmux-sensible
    tmux-yank
    tmux-cpu
    tmux-network-bandwidth
    tmux-resurrect
  )

  require_tpm_runtime
  prepare_runtime
  create_plugin local-plugin
  mkdir -p "$TEST_HOME/.tmux/plugins/unused-local-plugin"
  : > "$TEST_HOME/.tmux/plugins/tmux-cpu/managed-sentinel"
  cat > "$TEST_HOME/.tmux/conf.d/override.conf" <<'TMUX'
set -g @dotfiles_plugin_tmux_cpu off
set -g @plugin 'adopter/local-plugin'
TMUX
  start_server commands

  socket_path=$(env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
    tmux -L "$SOCKET" display-message -p '#{socket_path}')
  manager_path=$(env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
    tmux -L "$SOCKET" show-environment -g TMUX_PLUGIN_MANAGER_PATH)
  [[ "$manager_path" == "TMUX_PLUGIN_MANAGER_PATH=$TEST_HOME/.tmux/plugins/" ]]
  original_plugins="$(tmux_value @tpm_plugins)"
  [[ "$original_plugins" != *tmux-plugins/tmux-cpu* ]]

  prefix_bindings=$(env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
    tmux -L "$SOCKET" list-keys -T prefix)
  install_binding=$(awk '$4 == "I" { print; exit }' <<<"$prefix_bindings")
  update_binding=$(awk '$4 == "U" { print; exit }' <<<"$prefix_bindings")
  clean_binding=$(awk '$4 == "M-u" { print; exit }' <<<"$prefix_bindings")
  [[ "$install_binding" == *tpm-local-plugins* ]]
  [[ "$update_binding" == *tpm-local-plugins* ]]
  [[ "$clean_binding" == *tpm-local-plugins* ]]
  [[ "$update_binding" != *bindings/update_plugins* ]]
  [[ "$clean_binding" != *bindings/clean_plugins* ]]

  run env \
    HOME="$TEST_HOME" \
    TMUX="$socket_path,0,0" \
    "$TEST_HOME/.tmux/bin/tpm-local-plugins" list
  [[ "$status" -eq 0 ]]
  if [[ "$output" != local-plugin ]]; then
    printf 'unexpected local plugin list: %s\n' "$output" >&3
    false
  fi

  cat > "$TEST_BIN/git" <<'ZSH'
#!/usr/bin/env zsh
print -r -- "${PWD:t}:$*" >> "$GIT_LOG"
ZSH
  chmod +x "$TEST_BIN/git"
  git_log="$TEST_ROOT/git.log"
  : > "$git_log"

  run env \
    HOME="$TEST_HOME" \
    TMUX="$socket_path,0,0" \
    PATH="$TEST_BIN:$PATH" \
    GIT_LOG="$git_log" \
    "$TEST_HOME/.tmux/bin/tpm-local-plugins" install
  [[ "$status" -eq 0 ]]
  [[ "$output" == *'Already installed "local-plugin"'* ]]
  [[ "$(cat "$git_log")" == local-plugin:remote ]]

  : > "$git_log"
  run env \
    HOME="$TEST_HOME" \
    TMUX="$socket_path,0,0" \
    PATH="$TEST_BIN:$PATH" \
    GIT_LOG="$git_log" \
    "$TEST_HOME/.tmux/bin/tpm-local-plugins" update all
  [[ "$status" -eq 0 ]]
  if [[ "$output" != *'"local-plugin" update success'* ]]; then
    printf 'unexpected local update output: %s\n' "$output" >&3
    false
  fi
  [[ "$(cat "$git_log")" == $'local-plugin:remote\nlocal-plugin:pull\nlocal-plugin:submodule update --init --recursive' ]]

  : > "$git_log"
  run env \
    HOME="$TEST_HOME" \
    TMUX="$socket_path,0,0" \
    PATH="$TEST_BIN:$PATH" \
    GIT_LOG="$git_log" \
    "$TEST_HOME/.tmux/bin/tpm-local-plugins" update tmux-cpu
  [[ "$status" -eq 1 ]]
  [[ ! -s "$git_log" ]]

  run env \
    HOME="$TEST_HOME" \
    TMUX="$socket_path,0,0" \
    "$TEST_HOME/.tmux/bin/tpm-local-plugins" clean
  [[ "$status" -eq 0 ]]
  [[ ! -d "$TEST_HOME/.tmux/plugins/unused-local-plugin" ]]
  [[ -f "$TEST_HOME/.tmux/plugins/tmux-cpu/managed-sentinel" ]]
  for managed_name in "${managed_names[@]}"; do
    [[ -d "$TEST_HOME/.tmux/plugins/$managed_name" ]]
  done
  [[ -d "$TEST_HOME/.tmux/plugins/local-plugin" ]]
  [[ "$(tmux_value @tpm_plugins)" == "$original_plugins" ]]
}

@test "runtime validation stays on a named scratch socket" {
  local socket_path manager_path

  require_tpm_runtime
  prepare_runtime
  start_server isolation

  socket_path=$(env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
    tmux -L "$SOCKET" display-message -p '#{socket_path}')
  manager_path=$(env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH HOME="$TEST_HOME" \
    tmux -L "$SOCKET" show-environment -g TMUX_PLUGIN_MANAGER_PATH)

  [[ "$socket_path" == *"/$SOCKET" ]]
  [[ "$manager_path" == "TMUX_PLUGIN_MANAGER_PATH=$TEST_HOME/.tmux/plugins/" ]]
}
