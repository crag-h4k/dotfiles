#!/usr/bin/env bats
# tests/test_confirm_install.bats
# Drive confirm-install.sh over a real pty (tests/pty_run.py) and assert:
#   - each yes/no answer maps to the exact stdout token (packages/configs),
#   - nothing leaks OSC/CSI escape bytes into the captured result stdout
#     (regression guard for the Gum stdin-pipe leak that motivated the rewrite),
#   - the "packages" choice writes the one-shot pkg-confirm sentinel and the other
#     choices do not.
# Package metadata and inventory calls are stubbed so no real brew/dpkg probe
# happens.

CHEZMOI_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
CONFIRM="${CHEZMOI_DIR}/scripts/confirm-install.sh"
PTY="${BATS_TEST_DIRNAME}/pty_run.py"

setup() {
  PYTHON3="$(command -v python3 || true)"
  [ -n "$PYTHON3" ] || skip "python3 not available for the pty harness"
  SENTINEL="${BATS_TEST_TMPDIR}/pkg-confirm-sentinel"
  STUBS="${BATS_TEST_TMPDIR}/stubs"
  mkdir -p "$STUBS"
  cat > "$STUBS/brew" <<'STUB'
#!/bin/sh
exit 0
STUB
  chmod +x "$STUBS/brew"
  rm -f "$SENTINEL"
}

# drive <response> -> runs confirm-install.sh over a pty, feeding <response>;
# result token lands in $output.
drive() {
  run env PATH="${STUBS}:/usr/bin:/bin" \
    DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1 \
    DOTFILES_PKG_CONFIRM_SENTINEL="${SENTINEL}" \
    "$PYTHON3" "$PTY" "$1" bash "$CONFIRM"
}

@test "confirm-install: yes -> packages, writes sentinel" {
  drive "y"
  [ "$status" -eq 0 ]
  [ "$output" = "packages" ]
  [ -f "$SENTINEL" ]
}

@test "confirm-install: current plan proceeds without an answer" {
  cat >"$STUBS/brew" <<'STUB'
#!/bin/sh
case "$*" in
  update) ;;
  "list --formula") printf 'git\ncurl\ngum\nchezmoi\nprek\n' ;;
  "list --cask"|"outdated --formula --quiet"|"outdated --cask --quiet") ;;
  *) exit 91 ;;
esac
STUB
  chmod +x "$STUBS/brew"
  run env PATH="${STUBS}:/usr/bin:/bin" DOTFILES_PLAN_OS=macos \
    DOTFILES_PKG_CONFIRM_SENTINEL="${SENTINEL}" \
    "$PYTHON3" "$PTY" "" bash "$CONFIRM"
  [ "$status" -eq 0 ]
  [ "$output" = "packages" ]
  [ -f "$SENTINEL" ]
}

@test "confirm-install: empty (Enter) -> configs, no sentinel" {
  drive ""
  [ "$status" -eq 0 ]
  [ "$output" = "configs" ]
  [ ! -e "$SENTINEL" ]
}

@test "confirm-install: no -> configs, no sentinel" {
  drive "n"
  [ "$status" -eq 0 ]
  [ "$output" = "configs" ]
  [ ! -e "$SENTINEL" ]
}

@test "confirm-install: unrecognized input -> configs, no sentinel" {
  drive "9"
  [ "$status" -eq 0 ]
  [ "$output" = "configs" ]
  [ ! -e "$SENTINEL" ]
}

@test "confirm-install: result stdout carries no OSC/CSI escape bytes" {
  drive "y"
  [ "$status" -eq 0 ]
  # No ESC (0x1b) byte anywhere in the captured token stream.
  [[ "$output" != *$'\x1b'* ]]
}

@test "confirm-install: rejects inherited /run/user/0 and writes UID fallback" {
  local fallback
  fallback="${BATS_TEST_TMPDIR}/dotfiles-runtime-$(id -u)/dotfiles-pkg-confirm"
  run env -u DOTFILES_PKG_CONFIRM_SENTINEL PATH="${STUBS}:/usr/bin:/bin" \
    DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1 \
    XDG_RUNTIME_DIR=/run/user/0 TMPDIR="${BATS_TEST_TMPDIR}" \
    "$PYTHON3" "$PTY" "y" bash "$CONFIRM"
  [ "$status" -eq 0 ]
  [ "$output" = "packages" ]
  [ -f "$fallback" ]
}
