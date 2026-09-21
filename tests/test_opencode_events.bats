#!/usr/bin/env bats
# tests/test_opencode_events.bats
# Covers the OpenCode attention shim (home/dot_config/notify/executable_opencode-events.sh):
# the stale-pane guard and the per-event group routing.
#
# The stale-pane case is the one worth pinning. A long-lived `opencode2 serve
# --service` keeps the TMUX_PANE it started in, so after a tmux server restart
# the shim is handed a pane id that no longer exists. tmux exits 0 with empty
# output for a dead target, so an exit-status check would call that success and
# the notification would vanish with no error anywhere.

CHEZMOI_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SHIM_SRC="${CHEZMOI_DIR}/home/dot_config/notify/executable_opencode-events.sh"
LIB_SRC="${CHEZMOI_DIR}/home/dot_config/notify/lib.sh"
PLUGIN_SRC="${CHEZMOI_DIR}/home/dot_config/opencode/plugin/notify.ts"
FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

setup() {
  FAKE_HOME="${BATS_TMPDIR}/oc-home-$$"
  STUB_DIR="${BATS_TMPDIR}/oc-stubs-$$"
  mkdir -p "${FAKE_HOME}/.config/notify" "${STUB_DIR}"
  cp "${LIB_SRC}" "${FAKE_HOME}/.config/notify/lib.sh"
  cp "${SHIM_SRC}" "${FAKE_HOME}/.config/notify/opencode-events.sh"
  LOG_FILE="${FAKE_HOME}/notify.log"

  # tmux stub: report LIVE_PANE as existing, every other pane id as gone (empty
  # output, exit 0), which is what real tmux does for a dead target.
  cat > "${STUB_DIR}/tmux" <<'STUB'
#!/bin/sh
for a in "$@"; do
  if [ "$a" = "display-message" ]; then
    for b in "$@"; do
      if [ "$b" = "${LIVE_PANE:-}" ]; then printf '%s' "$b"; exit 0; fi
    done
    exit 0
  fi
done
exit 0
STUB
  chmod +x "${STUB_DIR}/tmux"
}

teardown() {
  rm -rf "${FAKE_HOME}" "${STUB_DIR}"
}

# Run the shim with a controlled env. Args are passed through to the shim.
run_shim() {
  run env \
    HOME="${FAKE_HOME}" \
    PATH="${STUB_DIR}:${PATH}" \
    NOTIFY_CONFIG="${FIXTURES}/notify.yaml" \
    NOTIFY_DEBUG="${SHIM_DEBUG:-1}" \
    NOTIFY_LOG="${LOG_FILE}" \
    LIVE_PANE="${LIVE_PANE:-%1}" \
    TMUX="${TMUX_VAL-/tmp/tmux-501/default,1,0}" \
    TMUX_PANE="${PANE_VAL-%1}" \
    bash "${FAKE_HOME}/.config/notify/opencode-events.sh" "$@"
}

@test "exits quietly when not inside tmux" {
  TMUX_VAL="" PANE_VAL="" run_shim fire
  [ "$status" -eq 0 ]
  [ ! -f "${LOG_FILE}" ] || ! grep -q 'fire pane=' "${LOG_FILE}"
}

@test "a live pane fires the default opencode group" {
  run_shim fire
  [ "$status" -eq 0 ]
  grep -q 'group=opencode ' "${LOG_FILE}"
}

@test "a stale pane is skipped instead of firing into nothing" {
  PANE_VAL='%34' run_shim fire
  [ "$status" -eq 0 ]
  grep -q 'stale pane %34' "${LOG_FILE}"
  run grep -q 'fire pane=' "${LOG_FILE}"
  [ "$status" -ne 0 ]
}

@test "a stale pane warns on stderr so it is not silent" {
  PANE_VAL='%34' run_shim fire
  [[ "$output" == *"stale pane %34"* ]]
}

@test "plugin keeps detached launch while stale recovery logs without debug" {
  grep -Fq 'detached: true, stdio: "ignore"' "$PLUGIN_SRC"
  grep -Fq 'child.unref()' "$PLUGIN_SRC"
  grep -Fq 'process.argv.includes("--service")' "$PLUGIN_SRC"
  grep -Fq '["session.execution.succeeded", "opencode"]' "$PLUGIN_SRC"
  grep -Fq '["permission.asked", "opencode_permission"]' "$PLUGIN_SRC"
  grep -Fq '["form.created", "opencode_question"]' "$PLUGIN_SRC"

  SHIM_DEBUG=0 PANE_VAL='%34' run_shim fire opencode_permission
  [ "$status" -eq 0 ]
  grep -q 'stale pane %34 is not on this tmux server' "$LOG_FILE"
  run grep -q 'fire pane=' "$LOG_FILE"
  [ "$status" -ne 0 ]
}

@test "the permission group routes to its own appearance" {
  run_shim fire opencode_permission
  [ "$status" -eq 0 ]
  grep -q 'group=opencode_permission' "${LOG_FILE}"
}

@test "the question group routes to its own appearance" {
  run_shim fire opencode_question
  [ "$status" -eq 0 ]
  grep -q 'group=opencode_question' "${LOG_FILE}"
}

@test "the three groups resolve to three different accents" {
  run_shim fire
  run_shim fire opencode_permission
  run_shim fire opencode_question
  accents=$(grep -o 'accent=#[0-9a-f]*' "${LOG_FILE}" | sort -u | wc -l | tr -d ' ')
  [ "$accents" -eq 3 ]
}

@test "an unknown group falls back to opencode rather than failing" {
  run_shim fire not_a_real_group
  [ "$status" -eq 0 ]
  grep -q 'unknown group not_a_real_group' "${LOG_FILE}"
  grep -q 'group=opencode ' "${LOG_FILE}"
}

@test "omitting the group keeps the old single-argument call working" {
  run_shim fire
  [ "$status" -eq 0 ]
  grep -q 'group=opencode ' "${LOG_FILE}"
}

@test "clear accepts a group too" {
  run_shim clear opencode_question
  [ "$status" -eq 0 ]
}

@test "an unknown verb is a usage error" {
  run_shim bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}
