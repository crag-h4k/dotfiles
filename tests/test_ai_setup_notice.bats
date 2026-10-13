#!/usr/bin/env bats
# tests/test_ai_setup_notice.bats
# Verify the post-apply AI setup reminder is read-only, selection-gated, and quiet
# once each selected service is configured and ready.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
NOTICE="$REPO_ROOT/scripts/ai-setup-notice.sh"

setup() {
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  STUBS="$BATS_TEST_TMPDIR/bin"
  CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  mkdir -p "$TEST_HOME" "$STUBS"
  : >"$CURL_LOG"
  cat >"$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_LOG"
[[ "${CURL_READY:-false}" == true ]]
EOF
  chmod +x "$STUBS/curl"
}

run_notice() {
  run env -u NO_COLOR HOME="$TEST_HOME" PATH="$STUBS:$PATH" CURL_LOG="$CURL_LOG" "$@" bash "$NOTICE"
}

write_openviking_config() {
  mkdir -p "$TEST_HOME/.openviking"
  printf '{}\n' >"$TEST_HOME/.openviking/ov.conf"
  printf '{"url": "http://127.0.0.1:1933/", "api_key": "fixture-secret"}\n' >"$TEST_HOME/.openviking/ovcli.conf"
}

write_caveman_settings() {
  mkdir -p "$TEST_HOME/.caveman/oc2"
  printf '{"enabled": %s, "url": "http://127.0.0.1:8787"}\n' "$1" >"$TEST_HOME/.caveman/oc2/settings.json"
}

@test "unselected services print nothing and probe nothing" {
  run_notice INSTALL_AI_OPENVIKING=false INSTALL_AI_CAVEMAN=false

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CURL_LOG" ]
}

@test "selected OpenViking without private config points to setup in red" {
  run_notice INSTALL_AI_OPENVIKING=true

  [ "$status" -eq 0 ]
  [[ "$output" == $'\033[31m'* ]]
  [[ "$output" == *"openvikingctl setup"* ]]
  [[ "$output" == *"/docs/openviking.md"* ]]
  [ ! -e "$TEST_HOME/.openviking" ]
}

@test "configured OpenViking that is not ready points to enable without leaking the key" {
  write_openviking_config

  run_notice INSTALL_AI_OPENVIKING=true CURL_READY=false

  [ "$status" -eq 0 ]
  [[ "$output" == *"openvikingctl enable"* ]]
  [[ "$output" != *fixture-secret* ]]
  grep -Fq 'http://127.0.0.1:1933/ready' "$CURL_LOG"
}

@test "ready OpenViking is quiet" {
  write_openviking_config

  run_notice INSTALL_AI_OPENVIKING=true CURL_READY=true

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Caveman without a private route points to init" {
  run_notice INSTALL_AI_CAVEMAN=true

  [ "$status" -eq 0 ]
  [[ "$output" == *"cavemanctl init"* ]]
  [[ "$output" == *"/docs/caveman.md"* ]]
}

@test "deliberately disabled Caveman is quiet and never probed" {
  write_caveman_settings false

  run_notice INSTALL_AI_CAVEMAN=true CURL_READY=false

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CURL_LOG" ]
}

@test "enabled Caveman with a stopped proxy is reported, and NO_COLOR drops red" {
  write_caveman_settings true

  run env HOME="$TEST_HOME" PATH="$STUBS:$PATH" CURL_LOG="$CURL_LOG" NO_COLOR=1 \
    INSTALL_AI_CAVEMAN=true CURL_READY=false bash "$NOTICE"

  [ "$status" -eq 0 ]
  [[ "$output" == "dotfiles: Caveman is configured but its proxy is not ready."* ]]
  grep -Fq 'http://127.0.0.1:8787/health/ready' "$CURL_LOG"
}

@test "enabled and ready Caveman is quiet" {
  write_caveman_settings true

  run_notice INSTALL_AI_CAVEMAN=true CURL_READY=true

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
