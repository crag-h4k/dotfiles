#!/usr/bin/env bats
# tests/test_opencode2_wrapper.bats
# Verify the managed wrapper and npm-owned isolated installer without package
# mutations.

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
if [[ "${TEST_NPM_POLICY:-false}" == true ]]; then
  print -r -- "age=${NPM_CONFIG_MIN_RELEASE_AGE:-unset}"
  print -r -- "exclude=${NPM_CONFIG_MIN_RELEASE_AGE_EXCLUDE:-unset}"
fi
if [[ -n "${OPENCODE_CLI_CONFIG_CONTENT:-}" ]]; then
  print -r -- "cli=$OPENCODE_CLI_CONFIG_CONTENT"
fi
for arg in "$@"; do
  print -r -- "arg=$arg"
done
STUB
  chmod +x "$PREFIX/bin/opencode2"
}

install_with_npm() {
  local stub_dir="$BATS_TEST_TMPDIR/stubs" npm_log="$BATS_TEST_TMPDIR/npm.log"
  mkdir -p "$stub_dir"
  cat >"$stub_dir/npm" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$NPM_LOG"
if [ "$1" = --version ]; then
  printf '%s\n' "$TEST_NPM_VERSION"
  exit 0
fi
if [ "$1" = view ]; then
  case "$2" in
    @opencode/cli@latest) printf '2.0.8\n' ;;
    @opentui/solid@latest) printf '0.5.11\n' ;;
    @opentui/solid@0.5.11) printf '1.9.12\n' ;;
    *) exit 1 ;;
  esac
  exit 0
fi
  if [ "$1" = install ] && printf '%s\n' "$*" | grep -q '@opencode/cli@'; then
  case "$TEST_NPM_VERSION" in
    12.*) printf '%s\n' "$*" | grep -q -- '--allow-scripts=@opencode/cli' || exit 1 ;;
    11.*) case "$*" in *--allow-scripts*) exit 1 ;; esac ;;
  esac
    while [ "$#" -gt 0 ]; do
    if [ "$1" = --prefix ]; then
      prefix=$2
      break
    fi
    shift
    done
    if [ "${NPM_REQUIRE_FREE_BIN:-0}" = 1 ] && { [ -e "$prefix/bin/opencode2" ] || [ -L "$prefix/bin/opencode2" ]; }; then
      exit 1
    fi
    [ "${NPM_CLI_FAIL:-0}" = 1 ] && exit 1
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
  cat >"$stub_dir/sync-runtime" <<'STUB'
#!/bin/sh
exit "${NPM_RUNTIME_FAIL:-0}"
STUB
  chmod +x "$stub_dir/npm" "$stub_dir/node" "$stub_dir/sync-runtime"
  before=$(cksum "$WRAPPER")

  run env PATH="$stub_dir:$PATH" NPM_LOG="$npm_log" TEST_NPM_VERSION="$1" \
    INSTALL_AI_OPENCODE=true OPENCODE2_VERSION=latest \
    OPENCODE2_NPM_PREFIX="$PREFIX" OPENCODE2_WRAPPER="$WRAPPER" \
    OPENCODE2_RUNTIME_SYNC="$stub_dir/sync-runtime" \
    OPENCODE2_CONFIG_DIR="$HOME/.config/opencode" bash "$INSTALLER"

  [ "$status" -eq "${2:-0}" ]
  [ "$(cksum "$WRAPPER")" = "$before" ]
  [ "${2:-0}" -eq 0 ] || return 0
  grep -Eq "^install -g --prefix $PREFIX( --allow-scripts=@opencode/cli)? @opencode/cli@2.0.8$" "$npm_log"
  [[ "$output" == *"@opencode/cli@2.0.8 and matching plugin runtime are current"* ]]
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

@test "native interactive updater inherits an OpenCode-only release-age exception" {
  run env TEST_NPM_POLICY=true NPM_CONFIG_MIN_RELEASE_AGE=3 "$WRAPPER"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'age=3\nexclude=@opencode/*\n'* ]]
  [[ "$output" == *'arg=--standalone'* ]]
}

@test "command-line updater inherits the same exception without changing npmrc" {
  printf 'min-release-age=3\n' >"$HOME/.npmrc"
  local before
  before=$(cksum "$HOME/.npmrc")
  run env TEST_NPM_POLICY=true NPM_CONFIG_MIN_RELEASE_AGE=3 "$WRAPPER" update
  [ "$status" -eq 0 ]
  [[ "$output" == *$'age=3\nexclude=@opencode/*\n'* ]]
  [ "$(cksum "$HOME/.npmrc")" = "$before" ]
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

@test "interactive launches default to standalone mode" {
  run "$WRAPPER"
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=--standalone" ]

  run "$WRAPPER" "$HOME/project"
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=--standalone
arg=$HOME/project" ]
}

@test "explicit server modes are not rewritten" {
  run "$WRAPPER" --standalone
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=--standalone" ]

  run "$WRAPPER" --server http://127.0.0.1:4096
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=--server
arg=http://127.0.0.1:4096" ]
}

@test "background service opt-in and subcommands stay unchanged" {
  run env OPENCODE2_BACKGROUND_SERVICE=true "$WRAPPER"
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX" ]

  run "$WRAPPER" service status
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=service
arg=status" ]
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

@test "npm 11 installer leaves the managed wrapper untouched" {
  install_with_npm 11.11.0
}

@test "npm 12 installer permits the CLI postinstall without enabling runtime scripts" {
  install_with_npm 12.0.2
}

@test "CLI overrides are passed to the native configuration loader" {
  mkdir -p "$HOME/.config/opencode"
  printf '%s\n' '{"session":{"sidebar":"show"}}' >"$HOME/.config/opencode/cli.override.json"
  run "$WRAPPER" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *'cli={"session":{"sidebar":"show"}}'* ]]
}

@test "an explicit CLI overlay takes precedence over the local file" {
  mkdir -p "$HOME/.config/opencode"
  printf '%s\n' '{"session":{"sidebar":"hide"}}' >"$HOME/.config/opencode/cli.override.json"
  run env OPENCODE_CLI_CONFIG_CONTENT='{"session":{"sidebar":"show"}}' "$WRAPPER" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *'cli={"session":{"sidebar":"show"}}'* ]]
}

@test "local launch overrides can select a server before standalone routing" {
  mkdir -p "$HOME/.config/opencode"
  cat >"$HOME/.config/opencode/override.zsh" <<'OVERRIDE'
if [[ "$interactive" == true && "$explicit_server" == false ]]; then
  exec "$binary" --server https://example.invalid "$@"
fi
OVERRIDE
  run "$WRAPPER" "two words"
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=--server
arg=https://example.invalid
arg=two words" ]
  run "$WRAPPER" --standalone
  [ "$status" -eq 0 ]
  [ "$output" = "prefix=$PREFIX
arg=--standalone" ]
}

@test "a failed local override prevents launching with partial settings" {
  mkdir -p "$HOME/.config/opencode"
  printf 'return 7\n' >"$HOME/.config/opencode/override.zsh"
  run "$WRAPPER"
  [ "$status" -eq 7 ]
  [ -z "$output" ]
}

legacy_release_link() {
  local release="$PREFIX/releases/2.0.7/bin"
  mkdir -p "$release"
  mv "$PREFIX/bin/opencode2" "$release/opencode2"
  ln -s "$release/opencode2" "$PREFIX/bin/opencode2"
}

@test "installer migrates legacy release links without forcing npm" {
  legacy_release_link
  local old_target
  old_target="$(readlink "$PREFIX/bin/opencode2")"
  export NPM_REQUIRE_FREE_BIN=1
  install_with_npm 11.11.0
  [ -x "$old_target" ]
  [ ! -L "$PREFIX/bin/opencode2" ]
}

@test "failed npm migration restores the previous executable link" {
  legacy_release_link
  local old_target
  old_target="$(readlink "$PREFIX/bin/opencode2")"
  export NPM_CLI_FAIL=1
  install_with_npm 11.11.0 1
  [ "$(readlink "$PREFIX/bin/opencode2")" = "$old_target" ]
  [ -x "$PREFIX/bin/opencode2" ]
  [[ "$output" == *"restored the previous release link"* ]]
}

@test "failed runtime migration restores the link after npm creates a new binary" {
  legacy_release_link
  local old_target
  old_target="$(readlink "$PREFIX/bin/opencode2")"
  export NPM_RUNTIME_FAIL=1
  install_with_npm 11.11.0 1
  [ "$(readlink "$PREFIX/bin/opencode2")" = "$old_target" ]
  [ -x "$PREFIX/bin/opencode2" ]
  [[ "$output" == *"restored the previous release link"* ]]
}
