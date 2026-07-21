#!/usr/bin/env bats
# tests/test_install_gate.bats
# Cover the package-manager confirmation gate: pkg_confirm() in scripts/common.sh
# and its two call sites (install.sh's packages branch, install-notify.sh). No test
# is allowed to install a real package: package managers are PATH-stubbed and
# INSTALL_* component flags are forced off so install.sh only exercises the batched
# `brew install` (stubbed) and never runs install-zsh.sh / install-neovim.sh.
#
# shellcheck disable=SC2030,SC2031
# Bats runs each @test in its own subshell, so an `export` scoped to one test
# never leaking into another is the intended behavior, not a bug.

CHEZMOI_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
COMMON="${CHEZMOI_DIR}/scripts/common.sh"
INSTALL="${CHEZMOI_DIR}/scripts/install.sh"
NOTIFY="${CHEZMOI_DIR}/scripts/install-notify.sh"

setup() {
  STUB_DIR="${BATS_TEST_TMPDIR}/stubs"
  mkdir -p "$STUB_DIR"
  BREW_LOG="${BATS_TEST_TMPDIR}/brew.log"
  rm -f "$BREW_LOG"
  # brew stub: log every call, succeed. Reused for both install.sh (brew install
  # ...) and install-notify.sh (brew install yq via ensure_yq).
  cat > "${STUB_DIR}/brew" <<STUB
#!/bin/sh
echo "\$*" >> "${BREW_LOG}"
exit 0
STUB
  chmod +x "${STUB_DIR}/brew"
  # Expose a real python3 through the stub dir so install-notify.sh's tail can run
  # under a Homebrew-free PATH (needed to keep the real yq out) without losing
  # python3 (yq and python3 share the Homebrew bin dir).
  if command -v python3 >/dev/null 2>&1; then
    ln -sf "$(command -v python3)" "${STUB_DIR}/python3"
  fi
  # A fresh home so the ~/dotfiles symlink and gitconfig prompts never touch the
  # real \$HOME.
  TEST_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$TEST_HOME"
  # Sentinel + tty paths that do not exist unless a test creates them.
  NO_TTY="${BATS_TEST_TMPDIR}/no-such-tty"
  NO_SENTINEL="${BATS_TEST_TMPDIR}/no-such-sentinel"
}

# Export the base env for driving install.sh in packages mode with every component
# off and package inspection stubbed out. Exported (not splatted through `env`) so
# a PATH entry containing a space - e.g. a "VMware Fusion.app" dir on the inherited
# PATH - never word-splits into a bogus argument. Callers export the gate vars too.
export_install_base() {
  export DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1
  export DOTFILES_INSTALL_MODE=packages
  export INSTALL_ZSH=false INSTALL_TMUX=false INSTALL_NEOVIM=false INSTALL_NOTIFY=false
  export INSTALL_AI_CODECOMPANION=false INSTALL_AI_STATUSLINE=false
  export INSTALL_TERMINAL_GHOSTTY=false INSTALL_TERMINAL_ITERM2=false
  export HOME="${TEST_HOME}" PATH="${STUB_DIR}:${PATH}"
}

# --- pkg_confirm unit behavior --------------------------------------------------

@test "pkg_confirm: DOTFILES_ASSUME_YES=1 proceeds silently" {
  run bash -c "source '${COMMON}'; DOTFILES_ASSUME_YES=1 pkg_confirm smoke"
  [ "$status" -eq 0 ]
}

@test "pkg_confirm: DOTFILES_ASSUME_YES accepts true/yes/y case-insensitively" {
  for v in true TRUE yes YES y Y; do
    run bash -c "source '${COMMON}'; DOTFILES_ASSUME_YES='${v}' pkg_confirm smoke"
    [ "$status" -eq 0 ]
  done
}

@test "pkg_confirm: no tty and no env declines" {
  run bash -c "source '${COMMON}'; DOTFILES_TTY='${NO_TTY}' DOTFILES_PKG_CONFIRM_SENTINEL='${NO_SENTINEL}' pkg_confirm smoke"
  [ "$status" -ne 0 ]
}

@test "pkg_confirm: DOTFILES_ASSUME_YES=0 is not truthy (declines with no tty)" {
  run bash -c "source '${COMMON}'; DOTFILES_ASSUME_YES=0 DOTFILES_TTY='${NO_TTY}' DOTFILES_PKG_CONFIRM_SENTINEL='${NO_SENTINEL}' pkg_confirm smoke"
  [ "$status" -ne 0 ]
}

@test "pkg_confirm: tty answer 'y' proceeds" {
  local ttyf="${BATS_TEST_TMPDIR}/tty-y"
  printf 'y\n' > "$ttyf"
  run bash -c "source '${COMMON}'; DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1 DOTFILES_TTY='${ttyf}' DOTFILES_PKG_CONFIRM_SENTINEL='${NO_SENTINEL}' pkg_confirm smoke"
  [ "$status" -eq 0 ]
}

@test "pkg_confirm: empty tty answer declines (default N)" {
  local ttyf="${BATS_TEST_TMPDIR}/tty-empty"
  printf '\n' > "$ttyf"
  run bash -c "source '${COMMON}'; DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1 DOTFILES_TTY='${ttyf}' DOTFILES_PKG_CONFIRM_SENTINEL='${NO_SENTINEL}' pkg_confirm smoke"
  [ "$status" -ne 0 ]
}

@test "pkg_confirm: 'n' tty answer declines" {
  local ttyf="${BATS_TEST_TMPDIR}/tty-n"
  printf 'n\n' > "$ttyf"
  run bash -c "source '${COMMON}'; DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1 DOTFILES_TTY='${ttyf}' DOTFILES_PKG_CONFIRM_SENTINEL='${NO_SENTINEL}' pkg_confirm smoke"
  [ "$status" -ne 0 ]
}

@test "pkg_confirm: fresh sentinel proceeds once and is consumed" {
  local sent="${BATS_TEST_TMPDIR}/sentinel"
  date +%s > "$sent"
  run bash -c "source '${COMMON}'; DOTFILES_TTY='${NO_TTY}' DOTFILES_PKG_CONFIRM_SENTINEL='${sent}' pkg_confirm smoke"
  [ "$status" -eq 0 ]
  [ ! -e "$sent" ]
}

@test "pkg_confirm: stale sentinel is ignored (declines with no tty) and cleaned up" {
  local sent="${BATS_TEST_TMPDIR}/sentinel-stale"
  date +%s > "$sent"
  touch -t 202001010000 "$sent"
  run bash -c "source '${COMMON}'; DOTFILES_TTY='${NO_TTY}' DOTFILES_PKG_CONFIRM_SENTINEL='${sent}' pkg_confirm smoke"
  [ "$status" -ne 0 ]
  [ ! -e "$sent" ]
}

# --- install.sh integration -----------------------------------------------------

@test "install.sh packages+DOTFILES_ASSUME_YES=1 runs brew" {
  export_install_base
  export DOTFILES_ASSUME_YES=1 DOTFILES_TTY="${NO_TTY}" DOTFILES_PKG_CONFIRM_SENTINEL="${NO_SENTINEL}"
  run bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ -f "$BREW_LOG" ]
  grep -q 'install' "$BREW_LOG"
}

@test "install.sh packages, no tty/env, declines: no brew, degrades to configs" {
  export_install_base
  export DOTFILES_TTY="${NO_TTY}" DOTFILES_PKG_CONFIRM_SENTINEL="${NO_SENTINEL}"
  run bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ ! -f "$BREW_LOG" ]
  [[ "$output" == *"declined for this run"* ]]
  [[ "$output" == *"configs-only mode: skipped packages"* ]]
}

@test "install.sh packages, tty answer 'y', runs brew" {
  local ttyf="${BATS_TEST_TMPDIR}/tty-y"
  printf 'y\n' > "$ttyf"
  export_install_base
  export DOTFILES_TTY="${ttyf}" DOTFILES_PKG_CONFIRM_SENTINEL="${NO_SENTINEL}"
  run bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ -f "$BREW_LOG" ]
  grep -q 'install' "$BREW_LOG"
}

@test "install.sh packages, tty answer 'n', declines: no brew" {
  local ttyf="${BATS_TEST_TMPDIR}/tty-n"
  printf 'n\n' > "$ttyf"
  export_install_base
  export DOTFILES_TTY="${ttyf}" DOTFILES_PKG_CONFIRM_SENTINEL="${NO_SENTINEL}"
  run bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ ! -f "$BREW_LOG" ]
  [[ "$output" == *"declined for this run"* ]]
}

@test "install.sh packages, fresh sentinel proceeds and consumes it" {
  local sent="${BATS_TEST_TMPDIR}/sentinel"
  date +%s > "$sent"
  export_install_base
  export DOTFILES_TTY="${NO_TTY}" DOTFILES_PKG_CONFIRM_SENTINEL="${sent}"
  run bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ -f "$BREW_LOG" ]
  [ ! -e "$sent" ]
}

# --- install-notify.sh gate -----------------------------------------------------

@test "install-notify.sh: yq missing, no tty/env -> dies mentioning yq" {
  run env PATH="${STUB_DIR}:/usr/bin:/bin" HOME="${TEST_HOME}" \
    DOTFILES_TTY="${NO_TTY}" DOTFILES_PKG_CONFIRM_SENTINEL="${NO_SENTINEL}" \
    bash "$NOTIFY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"yq is required"* ]]
  # Died at the gate before any package-manager call.
  [ ! -f "$BREW_LOG" ]
}

@test "install-notify.sh: yq missing + DOTFILES_ASSUME_YES=1 reaches ensure_yq (brew)" {
  run env PATH="${STUB_DIR}:/usr/bin:/bin" HOME="${TEST_HOME}" \
    DOTFILES_ASSUME_YES=1 DOTFILES_TTY="${NO_TTY}" \
    DOTFILES_PKG_CONFIRM_SENTINEL="${NO_SENTINEL}" \
    bash "$NOTIFY"
  [ -f "$BREW_LOG" ]
  grep -q 'yq' "$BREW_LOG"
}

@test "install-notify.sh: yq already present -> no prompt, no install attempted" {
  # mikefarah yq stub so have_mikefarah_yq is satisfied and ensure_yq no-ops.
  cat > "${STUB_DIR}/yq" <<'STUB'
#!/bin/sh
case "$1" in
  --version) echo "yq (https://github.com/mikefarah/yq/) version v4.44.0"; exit 0 ;;
esac
exit 0
STUB
  chmod +x "${STUB_DIR}/yq"
  run env PATH="${STUB_DIR}:/usr/bin:/bin" HOME="${TEST_HOME}" \
    DOTFILES_TTY="${NO_TTY}" DOTFILES_PKG_CONFIRM_SENTINEL="${NO_SENTINEL}" \
    bash "$NOTIFY"
  [ "$status" -eq 0 ]
  [ ! -f "$BREW_LOG" ]
  [[ "$output" != *"Install/update packages now?"* ]]
}
