#!/usr/bin/env bats

INSTALLER="${BATS_TEST_DIRNAME}/../scripts/install-ai-clis.sh"

setup() {
  TEST_HOME="${BATS_TEST_TMPDIR}/home"
  STUB_DIR="${BATS_TEST_TMPDIR}/bin"
  CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  mkdir -p "$TEST_HOME" "$STUB_DIR"

  cat > "${STUB_DIR}/curl" <<'STUB'
#!/bin/sh
output=
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    http*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s\n' "$url" >> "$DOTFILES_TEST_CURL_LOG"
if [ "${DOTFILES_TEST_FAIL_CLAUDE:-0}" = 1 ] &&
    [ "$url" = "https://claude.ai/install.sh" ]; then
  printf '#!/bin/sh\nexit 1\n' > "$output"
else
  printf '#!/bin/sh\nexit 0\n' > "$output"
fi
STUB
  chmod +x "${STUB_DIR}/curl"
}

@test "installs missing Claude Code and Codex CLI from official endpoints" {
  run env \
    HOME="$TEST_HOME" \
    PATH="${STUB_DIR}:/usr/bin:/bin" \
    DOTFILES_TEST_CURL_LOG="$CURL_LOG" \
    bash "$INSTALLER"

  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CURL_LOG")" -eq 2 ]
  grep -Fxq "https://claude.ai/install.sh" "$CURL_LOG"
  grep -Fxq "https://chatgpt.com/codex/install.sh" "$CURL_LOG"
  [[ "$output" == *"installing Claude Code"* ]]
  [[ "$output" == *"installing Codex CLI"* ]]
}

@test "attempts Codex even when the Claude installer fails" {
  run env \
    HOME="$TEST_HOME" \
    PATH="${STUB_DIR}:/usr/bin:/bin" \
    DOTFILES_TEST_CURL_LOG="$CURL_LOG" \
    DOTFILES_TEST_FAIL_CLAUDE=1 \
    bash "$INSTALLER"

  [ "$status" -eq 1 ]
  [ "$(wc -l < "$CURL_LOG")" -eq 2 ]
  grep -Fxq "https://chatgpt.com/codex/install.sh" "$CURL_LOG"
  [[ "$output" == *"Claude Code installer failed"* ]]
  [[ "$output" == *"installing Codex CLI"* ]]
}

@test "keeps existing CLI installations and performs no download" {
  for command_name in claude codex; do
    printf '#!/bin/sh\nexit 0\n' > "${STUB_DIR}/${command_name}"
    chmod +x "${STUB_DIR}/${command_name}"
  done

  run env \
    HOME="$TEST_HOME" \
    PATH="${STUB_DIR}:/usr/bin:/bin" \
    DOTFILES_TEST_CURL_LOG="$CURL_LOG" \
    bash "$INSTALLER"

  [ "$status" -eq 0 ]
  [ ! -e "$CURL_LOG" ]
  [[ "$output" == *"Claude Code: already installed"* ]]
  [[ "$output" == *"Codex CLI: already installed"* ]]
}
