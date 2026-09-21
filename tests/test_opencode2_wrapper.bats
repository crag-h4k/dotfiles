#!/usr/bin/env bats
# tests/test_opencode2_wrapper.bats
# Verify the managed wrapper and isolated installer without package mutations.

bats_require_minimum_version 1.5.0

WRAPPER_SRC="${BATS_TEST_DIRNAME}/../home/dot_local/bin/executable_opencode2"
INSTALLER="${BATS_TEST_DIRNAME}/../scripts/install-opencode2.sh"

setup() {
  local real_tmpdir
  real_tmpdir="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="${real_tmpdir}/home"
  export PREFIX="$HOME/.local/share/opencode2"
  export WRAPPER="$HOME/.local/bin/opencode2"
  mkdir -p "$PREFIX/bin" "$(dirname "$WRAPPER")"
  cp "$WRAPPER_SRC" "$WRAPPER"
  chmod +x "$WRAPPER"
  cat >"$PREFIX/bin/opencode2" <<'STUB'
#!/usr/bin/env zsh
print -r -- "prefix=$NPM_CONFIG_PREFIX"
for arg in "$@"; do
  print -r -- "arg=$arg"
done
STUB
  chmod +x "$PREFIX/bin/opencode2"
}

@test "update defaults to the isolated npm method" {
  run "$WRAPPER" update 2.1.0
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=update
arg=--method
arg=npm
arg=2.1.0" ]
}

@test "upgrade preserves an explicit long method" {
  run "$WRAPPER" upgrade --method pnpm 2.1.0
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=upgrade
arg=--method
arg=pnpm
arg=2.1.0" ]
}

@test "upgrade preserves an explicit short method" {
  run "$WRAPPER" upgrade -m bun
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=upgrade
arg=-m
arg=bun" ]
}

@test "upgrade preserves an attached short method" {
  run "$WRAPPER" upgrade -mbun 2.1.0
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=upgrade
arg=-mbun
arg=2.1.0" ]
}

@test "upgrade preserves an equals-style long method" {
  run "$WRAPPER" upgrade --method=pnpm 2.1.0
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=upgrade
arg=--method=pnpm
arg=2.1.0" ]
}

@test "method-like arguments after double dash do not suppress npm default" {
  run "$WRAPPER" update -- --method curl
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=update
arg=--method
arg=npm
arg=--
arg=--method
arg=curl" ]
}

@test "non-updater arguments are forwarded unchanged" {
  run "$WRAPPER" run "two words" --standalone
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=run
arg=two words
arg=--standalone" ]
}

@test "missing isolated binary fails clearly" {
  rm "$PREFIX/bin/opencode2"
  run -127 "$WRAPPER" --version
  [ "$status" -eq 127 ]
  [[ "$output" == *"isolated binary not found at $PREFIX/bin/opencode2"* ]]
}

@test "wrapper rejects an npm prefix that resolves back to itself" {
  run timeout 2 env OPENCODE2_NPM_PREFIX="$HOME/.local" "$WRAPPER" --version
  [ "$status" -eq 126 ]
  [ "$status" -ne 124 ]
  [[ "$output" == *"isolated binary resolves to the managed wrapper"* ]]
}

@test "wrapper rejects a symlinked binary that resolves back to itself" {
  local recursive_prefix="$HOME/recursive-prefix"
  mkdir -p "$recursive_prefix/bin"
  ln -s "$WRAPPER" "$recursive_prefix/bin/opencode2"
  run timeout 2 env OPENCODE2_NPM_PREFIX="$recursive_prefix" "$WRAPPER" --version
  [ "$status" -eq 126 ]
  [ "$status" -ne 124 ]
  [[ "$output" == *"isolated binary resolves to the managed wrapper"* ]]
}

@test "installer rejects an npm prefix that contains the managed wrapper" {
  run timeout 2 env INSTALL_AI_OPENCODE=true \
    OPENCODE2_NPM_PREFIX="$HOME/.local" OPENCODE2_WRAPPER="$WRAPPER" \
    bash "$INSTALLER"
  [ "$status" -ne 0 ]
  [ "$status" -ne 124 ]
  [[ "$output" == *"isolated binary resolves to the managed wrapper"* ]]
}

@test "installer rejects a symlinked binary that resolves back to the wrapper" {
  local recursive_prefix="$HOME/installer-recursive-prefix"
  mkdir -p "$recursive_prefix/bin"
  ln -s "$WRAPPER" "$recursive_prefix/bin/opencode2"

  run timeout 2 env INSTALL_AI_OPENCODE=true \
    OPENCODE2_NPM_PREFIX="$recursive_prefix" OPENCODE2_WRAPPER="$WRAPPER" \
    bash "$INSTALLER"

  [ "$status" -ne 0 ]
  [ "$status" -ne 124 ]
  [[ "$output" == *"isolated binary resolves to the managed wrapper"* ]]
}

@test "installer leaves the managed wrapper untouched" {
  local stub_dir="$BATS_TEST_TMPDIR/stubs" npm_log="$BATS_TEST_TMPDIR/npm.log"
  mkdir -p "$stub_dir" "$HOME/.config/opencode"
  rm "$PREFIX/bin/opencode2"
  cat >"$stub_dir/npm" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$NPM_LOG"
if [ "$1" = install ] && printf '%s\n' "$*" | grep -q '@opencode/cli@'; then
  while [ "$#" -gt 0 ]; do
    if [ "$1" = --prefix ]; then
      prefix=$2
      break
    fi
    shift
  done
  mkdir -p "$prefix/bin"
  cat >"$prefix/bin/opencode2" <<'BIN'
#!/bin/sh
printf 'opencode2 v2.0.8\n'
BIN
  chmod +x "$prefix/bin/opencode2"
fi
STUB
  cat >"$stub_dir/node" <<'STUB'
#!/bin/sh
exit 0
STUB
  chmod +x "$stub_dir/npm" "$stub_dir/node"
  before=$(cksum "$WRAPPER")

  run env PATH="$stub_dir:$PATH" NPM_LOG="$npm_log" \
    INSTALL_AI_OPENCODE=true OPENCODE2_VERSION=latest \
    OPENCODE2_NPM_PREFIX="$PREFIX" OPENCODE2_WRAPPER="$WRAPPER" \
    OPENCODE2_CONFIG_DIR="$HOME/.config/opencode" bash "$INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(cksum "$WRAPPER")" = "$before" ]
  grep -q '^install -g --prefix .* @opencode/cli@latest$' "$npm_log"
  grep -q '^install --prefix .* --ignore-scripts --package-lock=false --no-save @opencode/plugin@2.0.8 @opentui/solid@latest solid-js@latest$' "$npm_log"
  [[ "$output" == *"activated @opencode/cli@2.0.8 and matching plugin runtime"* ]]
}
