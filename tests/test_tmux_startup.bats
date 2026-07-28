# tests/test_tmux_startup.bats
# Regression coverage for the Zsh -> Oh My Zsh -> tmux startup path and wheel
# ownership when a foreground TUI has enabled application mouse reporting.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
NOTIFY_CONF="${REPO_ROOT}/home/dot_tmux/conf.d/notify.conf"

setup() {
  TEST_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$TEST_HOME"
}

@test "Zsh replaces an inherited tmux config before Oh My Zsh loads" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"

  mkdir -p \
    "$TEST_HOME/zsh" \
    "$TEST_HOME/ohmyzsh" \
    "$TEST_HOME/custom/functions"
  : > "$TEST_HOME/zsh/theme.zsh"
  : > "$TEST_HOME/zsh/aliases"

  cat > "$TEST_HOME/ohmyzsh/oh-my-zsh.sh" <<'STUB'
print -r -- "$ZSH_TMUX_CONFIG" > "$TMUX_CONFIG_CAPTURE"
STUB
  cat > "$TEST_HOME/custom/functions/stubs.zsh" <<'STUB'
netbanner() { :; }
zsh_history_backup() { :; }
STUB

  run env \
    HOME="$TEST_HOME" \
    ZSH_BASE="$TEST_HOME/zsh" \
    ZSH="$TEST_HOME/ohmyzsh" \
    ZSH_CUSTOM="$TEST_HOME/custom" \
    TMUX_CONFIG_CAPTURE="$TEST_HOME/captured-tmux-config" \
    ZSH_TMUX_CONFIG="/stale/inherited/tmux.conf" \
    zsh -dfc "source '$REPO_ROOT/home/dot_zshrc'"

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_HOME/captured-tmux-config")" = "$TEST_HOME/.tmux.conf" ]
}

binding_block() {
  local table="$1" key="$2"
  awk -v prefix="bind-key -T ${table} ${key}" '
    index($0, prefix) == 1 { capture = 1 }
    capture && $0 ~ /^bind-key / && index($0, prefix) != 1 { exit }
    capture { print }
  ' "$NOTIFY_CONF"
}

@test "root wheel forwards to mouse-aware TUIs and never clears the flag" {
  local wheel_up wheel_down
  wheel_up=$(binding_block root WheelUpPane)
  wheel_down=$(binding_block root WheelDownPane)

  # Forward the wheel to a foreground TUI that requested mouse mode, so Claude
  # Code scrolls its OWN conversation; fall back to copy-mode for a plain shell.
  [[ "$wheel_up" == *"mouse_any_flag"* ]]
  [[ "$wheel_up" == *"send-keys -M"* ]]
  [[ "$wheel_up" == *"copy-mode -e"* ]]
  [[ "$wheel_down" == *"send-keys -M"* ]]

  # Apple trackpads emit wheel events on the faintest touch, so the wheel must
  # never be a clear trigger.
  [[ "$wheel_up" != *"clear-pane"* ]]
  [[ "$wheel_down" != *"clear-pane"* ]]
}

@test "the flag clears on a click but not on a drag" {
  # Left- and right-click clear; the drag override was removed (tmux default),
  # so dragging never clears - a MouseDown already precedes any drag.
  [[ "$(binding_block root MouseDown1Pane)" == *"clear-pane"* ]]
  [[ "$(binding_block root MouseDown3Pane)" == *"clear-pane"* ]]
  [[ -z "$(binding_block root MouseDrag1Pane)" ]]
}
