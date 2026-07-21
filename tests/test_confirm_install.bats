#!/usr/bin/env bats
# tests/test_confirm_install.bats
# Drive confirm-install.sh over a real pty (tests/pty_run.py) and assert:
#   - each menu choice maps to the exact stdout token (packages/configs/exit),
#   - nothing leaks OSC/CSI escape bytes into the captured result stdout
#     (regression guard for the Gum stdin-pipe leak that motivated the rewrite),
#   - the "packages" choice writes the one-shot pkg-confirm sentinel and the other
#     choices do not.
# Gum is stripped from the child PATH so the deterministic typed-menu path runs;
# package inspection is stubbed missing so no real brew/dpkg probe happens.

CHEZMOI_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
CONFIRM="${CHEZMOI_DIR}/scripts/confirm-install.sh"
PTY="${BATS_TEST_DIRNAME}/pty_run.py"

setup() {
  PYTHON3="$(command -v python3 || true)"
  [ -n "$PYTHON3" ] || skip "python3 not available for the pty harness"
  SENTINEL="${BATS_TEST_TMPDIR}/pkg-confirm-sentinel"
  rm -f "$SENTINEL"
}

# drive <response> -> runs confirm-install.sh over a pty with a gum-free child
# PATH, feeding <response>; result token lands in $output.
drive() {
  run env PATH="/usr/bin:/bin" \
    DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1 \
    DOTFILES_PKG_CONFIRM_SENTINEL="${SENTINEL}" \
    "$PYTHON3" "$PTY" "$1" bash "$CONFIRM"
}

@test "confirm-install: choice 1 -> packages, writes sentinel" {
  drive "1"
  [ "$status" -eq 0 ]
  [ "$output" = "packages" ]
  [ -f "$SENTINEL" ]
}

@test "confirm-install: empty (Enter) -> packages (default), writes sentinel" {
  drive ""
  [ "$status" -eq 0 ]
  [ "$output" = "packages" ]
  [ -f "$SENTINEL" ]
}

@test "confirm-install: choice 2 -> configs, no sentinel" {
  drive "2"
  [ "$status" -eq 0 ]
  [ "$output" = "configs" ]
  [ ! -e "$SENTINEL" ]
}

@test "confirm-install: choice 3 -> exit, no sentinel" {
  drive "3"
  [ "$status" -eq 0 ]
  [ "$output" = "exit" ]
  [ ! -e "$SENTINEL" ]
}

@test "confirm-install: unrecognized input -> exit, no sentinel" {
  drive "9"
  [ "$status" -eq 0 ]
  [ "$output" = "exit" ]
  [ ! -e "$SENTINEL" ]
}

@test "confirm-install: result stdout carries no OSC/CSI escape bytes" {
  drive "1"
  [ "$status" -eq 0 ]
  # No ESC (0x1b) byte anywhere in the captured token stream.
  [[ "$output" != *$'\x1b'* ]]
}
