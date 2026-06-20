#!/usr/bin/env bats
# tests/test_lib.bats

CHEZMOI_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
NOTIFY_LIB="${CHEZMOI_DIR}/dot_config/notify/lib.sh"
FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

setup() {
  export NOTIFY_CONFIG="${FIXTURES}/notify.yaml"
  unset TMUX
  unset TMUX_PANE
  STUB_DIR="${BATS_TMPDIR}/stubs-$$"
  mkdir -p "$STUB_DIR"
  TMUX_STUB_LOG="${BATS_TMPDIR}/tmux-calls-$$"
  rm -f "$TMUX_STUB_LOG"
}

teardown() {
  rm -rf "$STUB_DIR" "$TMUX_STUB_LOG"
}

@test "notify_fire is a no-op when pane arg is empty" {
  run bash -c "
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    source '${NOTIFY_LIB}'
    notify_fire '' test_group
  "
  [ "$status" -eq 0 ]
}

@test "notify_clear is a no-op when pane arg is empty" {
  run bash -c "
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    source '${NOTIFY_LIB}'
    notify_clear ''
  "
  [ "$status" -eq 0 ]
}

@test "notify_fire does not call tmux when pane is empty" {
  cat > "${STUB_DIR}/tmux" <<'STUB'
#!/bin/sh
echo "tmux called" >> "${TMUX_STUB_LOG}"
STUB
  chmod +x "${STUB_DIR}/tmux"

  run bash -c "
    export PATH='${STUB_DIR}:${PATH}'
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    export TMUX_STUB_LOG='${TMUX_STUB_LOG}'
    source '${NOTIFY_LIB}'
    notify_fire '' test_group
  "
  [ "$status" -eq 0 ]
  [ ! -f "$TMUX_STUB_LOG" ]
}

@test "notify_play silently skips when no sound player found" {
  run bash -c "
    export PATH='/usr/bin:/bin'
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    source '${NOTIFY_LIB}'
    notify_play 'funk.mp3' 75
  "
  [ "$status" -eq 0 ]
}

@test "notify_debug_on returns false when config has debug: false" {
  run bash -c "
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    source '${NOTIFY_LIB}'
    notify_debug_on && echo 'on' || echo 'off'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "off" ]
}

@test "notify_log is silent when debug is off" {
  local logfile="${BATS_TMPDIR}/test-notify.log"
  rm -f "$logfile"
  run bash -c "
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    export NOTIFY_LOG='${logfile}'
    source '${NOTIFY_LIB}'
    notify_log 'should not appear'
  "
  [ "$status" -eq 0 ]
  [ ! -f "$logfile" ]
}
