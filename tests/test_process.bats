#!/usr/bin/env bats
# tests/test_process.bats
# Tests for _notify_resolve_bin in dot_zsh/custom/functions/notify-process.zsh.
# Each test runs zsh as a subprocess: the function uses zsh-specific syntax
# (${(@s:|:)line}, ${aliases[...]}) that cannot be tested in bash.
#
# _resolve is called directly via $() rather than through bats `run`, because
# bash functions are not exported to subprocesses and `run f args` would fail
# with exit 127. Bats fails the test automatically on any non-zero exit.

CHEZMOI_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
NOTIFY_PROCESS="${CHEZMOI_DIR}/dot_zsh/custom/functions/notify-process.zsh"
FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

# Resolve a command line through _notify_resolve_bin.
# Sources notify-process.zsh with NOTIFY_TEST=1 (skips yq config load),
# populates NOTIFY_GROUP with a test set, then prints $_notify_bin.
_resolve() {
  zsh -c "
    export NOTIFY_TEST=1
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    typeset -gA NOTIFY_GROUP NOTIFY_THRESHOLD
    typeset -ga NOTIFY_IGNORE
    source '${NOTIFY_PROCESS}'
    NOTIFY_GROUP[terraform]=iac
    NOTIFY_GROUP[rsync]=slow_processes
    NOTIFY_GROUP[brew]=pkg
    NOTIFY_GROUP[aws]=cloud
    NOTIFY_IGNORE=(claude codex)
    _notify_resolve_bin \"\$1\"
    printf '%s' \"\$_notify_bin\"
  " -- "$1"
}

@test "resolves simple binary" {
  local out
  out=$(_resolve "terraform plan -var-file=prod.tfvars")
  [ "$out" = "terraform" ]
}

@test "strips sudo prefix" {
  local out
  out=$(_resolve "sudo terraform apply")
  [ "$out" = "terraform" ]
}

@test "strips nohup prefix" {
  local out
  out=$(_resolve "nohup rsync -av src/ dst/")
  [ "$out" = "rsync" ]
}

@test "strips time prefix" {
  local out
  out=$(_resolve "time brew upgrade")
  [ "$out" = "brew" ]
}

@test "strips env prefix" {
  local out
  out=$(_resolve "env TERM=dumb terraform init")
  [ "$out" = "terraform" ]
}

@test "takes first named-group segment in a pipeline" {
  local out
  out=$(_resolve "terraform show plan.out | jq '.'")
  [ "$out" = "terraform" ]
}

@test "falls back to last segment when no segment is in a named group" {
  local out
  out=$(_resolve "cat file.txt | sort | uniq")
  [ "$out" = "uniq" ]
}

@test "returns bare binary for an unregistered command" {
  local out
  out=$(_resolve "some_unregistered_command --flag arg")
  [ "$out" = "some_unregistered_command" ]
}
