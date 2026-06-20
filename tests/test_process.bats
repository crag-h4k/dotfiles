#!/usr/bin/env bats
# tests/test_process.bats
# Tests for _notify_resolve_bin in dot_zsh/custom/functions/notify-process.zsh.
# Each test runs zsh as a subprocess: the function uses zsh-specific syntax
# (${(@s:|:)line}, ${aliases[...]}) that cannot be tested in bash.

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
  run _resolve "terraform plan -var-file=prod.tfvars"
  [ "$status" -eq 0 ]
  [ "$output" = "terraform" ]
}

@test "strips sudo prefix" {
  run _resolve "sudo terraform apply"
  [ "$status" -eq 0 ]
  [ "$output" = "terraform" ]
}

@test "strips nohup prefix" {
  run _resolve "nohup rsync -av src/ dst/"
  [ "$status" -eq 0 ]
  [ "$output" = "rsync" ]
}

@test "strips time prefix" {
  run _resolve "time brew upgrade"
  [ "$status" -eq 0 ]
  [ "$output" = "brew" ]
}

@test "strips env prefix" {
  run _resolve "env TERM=dumb terraform init"
  [ "$status" -eq 0 ]
  [ "$output" = "terraform" ]
}

@test "takes first named-group segment in a pipeline" {
  run _resolve "terraform show plan.out | jq '.'"
  [ "$status" -eq 0 ]
  [ "$output" = "terraform" ]
}

@test "falls back to last segment when no segment is in a named group" {
  run _resolve "cat file.txt | sort | uniq"
  [ "$status" -eq 0 ]
  [ "$output" = "uniq" ]
}

@test "returns bare binary for an unregistered command" {
  run _resolve "some_unregistered_command --flag arg"
  [ "$status" -eq 0 ]
  [ "$output" = "some_unregistered_command" ]
}
