#!/usr/bin/env bats
# tests/test_opencode_events.bats
# Covers the OpenCode attention shim (home/dot_config/notify/executable_opencode-events.sh):
# the stale-pane guard, the per-event group routing, the focus gate, and the
# sound-only path used outside tmux.
#
# The stale-pane case is the one worth pinning. A long-lived `opencode2 serve
# --service` keeps the TMUX_PANE it started in, so after a tmux server restart
# the shim is handed a pane id that no longer exists. tmux exits 0 with empty
# output for a dead target, so an exit-status check would call that success and
# the notification would vanish with no error anywhere.
#
# The focus gate suppresses only the visual flag, and only when tmux positively
# reports that a focused client is looking at the pane. Anything else, including
# a failed or unparsable lookup, keeps today's tint. The stub tests pin that
# decision table; the real-socket tests pin that the format tmux answers with
# still means what the shim thinks it means.

CHEZMOI_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SHIM_SRC="${CHEZMOI_DIR}/home/dot_config/notify/executable_opencode-events.sh"
LIB_SRC="${CHEZMOI_DIR}/home/dot_config/notify/lib.sh"
PLUGIN_SRC="${CHEZMOI_DIR}/home/dot_config/opencode/plugin/notify.ts"
LAUNCH_SRC="${CHEZMOI_DIR}/home/dot_config/opencode/plugin/notify-shim.mjs"
CLEAR_SRC="${CHEZMOI_DIR}/home/dot_config/notify/executable_clear-pane.sh"
NOTIFY_CONF="${CHEZMOI_DIR}/home/dot_tmux/conf.d/notify.conf"
CLIENT_PY="${BATS_TEST_DIRNAME}/tmux_client.py"
FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

setup() {
  FAKE_HOME="${BATS_TMPDIR}/oc-home-$$"
  STUB_DIR="${BATS_TMPDIR}/oc-stubs-$$"
  PLAYER_DIR="${BATS_TMPDIR}/oc-player-$$"
  mkdir -p "${FAKE_HOME}/.config/notify" "${FAKE_HOME}/sounds" "${STUB_DIR}" "${PLAYER_DIR}"
  cp "${LIB_SRC}" "${FAKE_HOME}/.config/notify/lib.sh"
  cp "${SHIM_SRC}" "${FAKE_HOME}/.config/notify/opencode-events.sh"
  cp "${CLEAR_SRC}" "${FAKE_HOME}/.config/notify/clear-pane.sh"
  chmod +x "${FAKE_HOME}/.config/notify/clear-pane.sh"
  LOG_FILE="${FAKE_HOME}/notify.log"
  TMUX_CALLS="${FAKE_HOME}/tmux-calls.log"
  AFPLAY_LOG="${FAKE_HOME}/afplay.log"
  CLIENT_PID=""
  CLIENT2_PID=""

  # tmux stub. Every call is recorded in TMUX_CALLS. display-message answers with
  # PROBE_OUT when a test supplies one (the focus probe), otherwise it reports
  # LIVE_PANE as existing and every other pane id as gone (empty output, exit
  # 0), which is what real tmux does for a dead target. list-clients answers
  # with CLIENTS_OUT.
  cat > "${STUB_DIR}/tmux" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "${TMUX_CALLS:-/dev/null}"
for a in "$@"; do
  if [ "$a" = "list-clients" ]; then
    printf '%s' "${CLIENTS_OUT:-}"
    exit 0
  fi
  if [ "$a" = "display-message" ]; then
    # Only the shim's probe asks for #{pane_id}. Reads of a user option such as
    # @notify or @notify_elsewhere_bg answer empty, as tmux does for an unset one.
    case "$*" in *'#{pane_id}'*) ;; *) exit 0 ;; esac
    if [ -n "${PROBE_OUT:-}" ]; then printf '%s' "$PROBE_OUT"; exit 0; fi
    for b in "$@"; do
      if [ "$b" = "${LIVE_PANE:-}" ]; then printf '%s' "$b"; exit 0; fi
    done
    exit 0
  fi
done
exit 0
STUB
  chmod +x "${STUB_DIR}/tmux"

  # Player stub, found ahead of any real afplay. It runs detached from the shim,
  # so tests that expect sound poll AFPLAY_LOG.
  cat > "${PLAYER_DIR}/afplay" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "${AFPLAY_LOG:-/dev/null}"
STUB
  cp "${PLAYER_DIR}/afplay" "${STUB_DIR}/afplay"
  chmod +x "${PLAYER_DIR}/afplay" "${STUB_DIR}/afplay"

  # A config where the opencode and question groups have a sound and the
  # permission group does not, so one run can prove both "plays" and "stays
  # silent". The palette background is what elsewhere tints dim toward; at the
  # default 0.5 the dimmed backgrounds are #353b4f, #3f3a43 and #3e3e46.
  touch "${FAKE_HOME}/sounds/ping.mp3" "${FAKE_HOME}/sounds/latch.mp3"
  SOUND_CONFIG="${FAKE_HOME}/notify-sound.yaml"
  cat > "$SOUND_CONFIG" <<'YAML'
settings:
  volume: 50
  debug: false
  elsewhere_dim: 0.5
palette:
  background: "#282a36"
integrations:
  opencode:
    bg: "#424c68"
    accent: "#8caaee"
    sound: ping.mp3
  opencode_permission:
    bg: "#564950"
    accent: "#ef9f76"
    sound: ""
  opencode_question:
    bg: "#545255"
    accent: "#e5c890"
    sound: latch.mp3
YAML
}

teardown() {
  if [ -n "${CLIENT_PID:-}" ]; then
    kill "$CLIENT_PID" 2>/dev/null || true
  fi
  if [ -n "${CLIENT2_PID:-}" ]; then
    kill "$CLIENT2_PID" 2>/dev/null || true
  fi
  if [ -n "${TMUX_TEST_SOCKET:-}" ]; then
    tmux -L "$TMUX_TEST_SOCKET" kill-server 2>/dev/null || true
  fi
  if [ -n "${REAL_SOCKET:-}" ]; then
    tmux -L "$REAL_SOCKET" kill-server 2>/dev/null || true
  fi
  # A detached player stub may still be appending to its log; retry once.
  rm -rf "${FAKE_HOME}" "${STUB_DIR}" "${PLAYER_DIR}" 2>/dev/null ||
    { sleep 0.3; rm -rf "${FAKE_HOME}" "${STUB_DIR}" "${PLAYER_DIR}"; }
}

# Run the shim with a controlled env. Args are passed through to the shim.
run_shim() {
  run env \
    HOME="${FAKE_HOME}" \
    PATH="${STUB_DIR}:${PATH}" \
    NOTIFY_CONFIG="${SHIM_CONFIG:-${FIXTURES}/notify.yaml}" \
    NOTIFY_SOUNDS="${FAKE_HOME}/sounds" \
    NOTIFY_DEBUG="${SHIM_DEBUG:-1}" \
    NOTIFY_LOG="${LOG_FILE}" \
    TMUX_CALLS="${TMUX_CALLS}" \
    AFPLAY_LOG="${AFPLAY_LOG}" \
    LIVE_PANE="${LIVE_PANE:-%1}" \
    PROBE_OUT="${PROBE_OUT:-}" \
    CLIENTS_OUT="${CLIENTS_OUT:-}" \
    TMUX="${TMUX_VAL-/tmp/tmux-501/default,1,0}" \
    TMUX_PANE="${PANE_VAL-%1}" \
    bash "${FAKE_HOME}/.config/notify/opencode-events.sh" "$@"
}

# Same shim against a REAL tmux server: only the player is stubbed. The server
# is addressed through TMUX, exactly as a plugin spawned inside a pane would.
run_shim_real() {
  run env \
    HOME="${FAKE_HOME}" \
    PATH="${PLAYER_DIR}:${PATH}" \
    NOTIFY_CONFIG="${SHIM_CONFIG:-${FIXTURES}/notify.yaml}" \
    NOTIFY_SOUNDS="${FAKE_HOME}/sounds" \
    NOTIFY_DEBUG=1 \
    NOTIFY_LOG="${LOG_FILE}" \
    AFPLAY_LOG="${AFPLAY_LOG}" \
    TMUX="${REAL_TMUX_ENV}" \
    TMUX_PANE="${1}" \
    bash "${FAKE_HOME}/.config/notify/opencode-events.sh" "${@:2}"
}

# Poll for a file that a detached player writes to.
wait_for_file() {
  local _i
  for _i in $(seq 1 50); do
    [ -s "$1" ] && return 0
    sleep 0.1
  done
  return 1
}

# probe <pane_active> <window_active> <attached> <session id> <flags> <focus-events>
# builds the display-message answer for pane %1, with the fields in the order the
# shim asks for them: pane_id|pane_active|window_active|session_attached|
# session_id|client_flags|focus-events.
probe() { printf '%%1|%s|%s|%s|%s|%s|%s' "$1" "$2" "$3" "$4" "$5" "$6"; }
FOCUSED_PROBE=$(probe 1 1 1 "\$0" attached,focused,UTF-8 1)

# Bats does not fail a test on a bare `! cmd`; this does.
refute() { if "$@"; then return 1; fi; }

# Outside tmux the bridge stays silent on purpose: OpenCode's own attention.sound
# is the outside-tmux sound (the opencode2 wrapper configures it), so playing from
# here too would double-fire.
@test "exits quietly when not inside tmux" {
  SHIM_CONFIG="$SOUND_CONFIG" TMUX_VAL="" PANE_VAL="" run_shim fire
  [ "$status" -eq 0 ]
  [ ! -f "${LOG_FILE}" ] || ! grep -q 'fire pane=' "${LOG_FILE}"
  [ ! -s "$TMUX_CALLS" ]
  [ ! -f "$AFPLAY_LOG" ]
  [ ! -f "${LOG_FILE}" ] || ! grep -q 'play via' "${LOG_FILE}"
}

@test "outside tmux clear is quiet too" {
  SHIM_CONFIG="$SOUND_CONFIG" TMUX_VAL="" PANE_VAL="" run_shim clear
  [ "$status" -eq 0 ]
  [ ! -s "$TMUX_CALLS" ]
  [ ! -f "$AFPLAY_LOG" ]
}

@test "a TMUX variable without a pane is quiet" {
  SHIM_CONFIG="$SOUND_CONFIG" PANE_VAL="" run_shim fire
  [ "$status" -eq 0 ]
  [ ! -s "$TMUX_CALLS" ]
  [ ! -f "$AFPLAY_LOG" ]
  # The shim logs "play via" synchronously, so this cannot pass by timing alone.
  [ ! -f "${LOG_FILE}" ] || ! grep -q 'play via' "${LOG_FILE}"
}

@test "a focused pane keeps the sound and skips every tmux write" {
  SHIM_CONFIG="$SOUND_CONFIG" PROBE_OUT="$FOCUSED_PROBE" run_shim fire
  [ "$status" -eq 0 ]
  refute grep -q 'set-option' "$TMUX_CALLS"
  grep -q 'play via .*afplay' "${LOG_FILE}"
  wait_for_file "$AFPLAY_LOG"
  grep -q 'ping.mp3' "$AFPLAY_LOG"
  refute grep -q 'fire pane=' "${LOG_FILE}"
}

@test "a client that lost focus still gets the tint" {
  PROBE_OUT=$(probe 1 1 1 "\$0" attached,UTF-8 1) run_shim fire
  [ "$status" -eq 0 ]
  grep -q 'set-option -p -t %1 window-style' "$TMUX_CALLS"
  grep -q 'fire pane=%1' "${LOG_FILE}"
}

@test "a pane that is not the active pane still gets the tint" {
  PROBE_OUT=$(probe 0 1 1 "\$0" attached,focused,UTF-8 1) run_shim fire
  [ "$status" -eq 0 ]
  grep -q 'set-option -p -t %1 window-style' "$TMUX_CALLS"
}

@test "a window that is not the current window still gets the tint" {
  PROBE_OUT=$(probe 1 0 1 "\$0" attached,focused,UTF-8 1) run_shim fire
  [ "$status" -eq 0 ]
  grep -q 'set-option -p -t %1 window-style' "$TMUX_CALLS"
}

@test "a session with no attached client still gets the tint" {
  PROBE_OUT=$(probe 1 1 0 "\$0" "" 1) run_shim fire
  [ "$status" -eq 0 ]
  grep -q 'set-option -p -t %1 window-style' "$TMUX_CALLS"
}

@test "focus-events off never trusts the focused flag" {
  # Without focus reporting tmux assumes every client is focused forever, which
  # would suppress the tint for a user who has switched to another app.
  PROBE_OUT=$(probe 1 1 1 "\$0" attached,focused,UTF-8 0) run_shim fire
  [ "$status" -eq 0 ]
  grep -q 'set-option -p -t %1 window-style' "$TMUX_CALLS"
}

@test "an unparsable lookup falls back to the tint" {
  PROBE_OUT='%1' run_shim fire
  [ "$status" -eq 0 ]
  grep -q 'set-option -p -t %1 window-style' "$TMUX_CALLS"
}

@test "with several clients any focused client on the session counts" {
  PROBE_OUT=$(probe 1 1 2 "\$7" attached,UTF-8 1) \
    CLIENTS_OUT=$'attached,UTF-8\nattached,focused,UTF-8\n' run_shim fire
  [ "$status" -eq 0 ]
  grep -qF "list-clients -t \$7" "$TMUX_CALLS"
  refute grep -q 'set-option' "$TMUX_CALLS"
}

@test "with several clients none focused still gets the tint" {
  PROBE_OUT=$(probe 1 1 2 "\$7" attached,UTF-8 1) \
    CLIENTS_OUT=$'attached,UTF-8\nattached,UTF-8\n' run_shim fire
  [ "$status" -eq 0 ]
  grep -q 'set-option -p -t %1 window-style' "$TMUX_CALLS"
}

@test "with several clients a failed client list falls back to the tint" {
  PROBE_OUT=$(probe 1 1 2 "\$7" attached,UTF-8 1) CLIENTS_OUT="" run_shim fire
  [ "$status" -eq 0 ]
  grep -q 'set-option -p -t %1 window-style' "$TMUX_CALLS"
}

@test "clear is never gated by focus" {
  PROBE_OUT="$FOCUSED_PROBE" run_shim clear
  [ "$status" -eq 0 ]
  grep -q 'set-option -pu -t %1 window-style' "$TMUX_CALLS"
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
  grep -Fq 'detached: true, stdio: "ignore"' "$LAUNCH_SRC"
  grep -Fq 'child.unref()' "$LAUNCH_SRC"
  grep -Fq 'process.argv.includes("--service")' "$PLUGIN_SRC"
  grep -Fq 'notificationGroup(event,' "$PLUGIN_SRC"

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

@test "notification stays in its pane and clearing one keeps the other flagged" {
  command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
  TMUX_TEST_SOCKET="notify-panes-$$-${BATS_TEST_NUMBER}"
  tmux -L "$TMUX_TEST_SOCKET" -f /dev/null new-session -d -s notify -x 90 -y 24 sleep 60
  tmux -L "$TMUX_TEST_SOCKET" split-window -d -t notify:0 sleep 60
  local socket_path
  socket_path=$(tmux -L "$TMUX_TEST_SOCKET" display-message -p -t notify:0 '#{socket_path}')
  export TMUX="$socket_path,0,0"
  # shellcheck disable=SC1090
  . "$LIB_SRC"
  _notify_fire_attrs() { printf '%s' '#112233|#445566||75'; }
  notify_play() { :; }

  local first second
  first=$(tmux -L "$TMUX_TEST_SOCKET" list-panes -t notify:0 -F '#{pane_id}' | head -n 1)
  second=$(tmux -L "$TMUX_TEST_SOCKET" list-panes -t notify:0 -F '#{pane_id}' | tail -n 1)
  notify_fire "$first" opencode
  [ "$(tmux -L "$TMUX_TEST_SOCKET" display-message -p -t "$first" '#{@notify}')" = 1 ]
  [ -z "$(tmux -L "$TMUX_TEST_SOCKET" display-message -p -t "$second" '#{@notify}')" ]
  [ "$(tmux -L "$TMUX_TEST_SOCKET" display-message -p -t "$first" '#{@notify_window}')" = 1 ]

  notify_fire "$second" opencode
  notify_clear "$first" key
  [ -z "$(tmux -L "$TMUX_TEST_SOCKET" display-message -p -t "$first" '#{@notify}')" ]
  [ "$(tmux -L "$TMUX_TEST_SOCKET" display-message -p -t "$second" '#{@notify}')" = 1 ]
  [ "$(tmux -L "$TMUX_TEST_SOCKET" display-message -p -t "$first" '#{@notify_window}')" = 1 ]
  notify_clear "$second" key
  [ -z "$(tmux -L "$TMUX_TEST_SOCKET" display-message -p -t "$first" '#{@notify_window}')" ]
}

@test "an unknown verb is a usage error" {
  run_shim bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

# --- Real tmux: the gate against an actual client ------------------------------

real_tmux() { tmux -L "$REAL_SOCKET" "$@"; }

# Start an isolated server with focus reporting on, as ~/.tmux.conf has it, and
# record the target pane and the TMUX value a pane's child would see.
start_real_server() {
  command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
  REAL_SOCKET="notify-focus-$$-${BATS_TEST_NUMBER}"
  real_tmux -f /dev/null new-session -d -s notify -x 90 -y 24 sleep 60
  real_tmux set-option -s focus-events on
  REAL_TMUX_ENV="$(real_tmux display-message -p -t notify:0 '#{socket_path}'),0,0"
  ACTIVE_PANE=$(real_tmux display-message -p -t notify:0 '#{pane_id}')
}

# Same server plus a second pane (the first stays active) and an attached pty
# client, which tmux counts as focused until the terminal reports a blur.
attach_real_client() {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  start_real_server
  real_tmux split-window -d -t notify:0 sleep 60
  BACKGROUND_PANE=$(real_tmux list-panes -t notify:0 -F '#{pane_id}' | grep -v -x -F "$ACTIVE_PANE")
  # fd 3 is bats' own; a background job holding it would hang the suite.
  python3 "$CLIENT_PY" "$REAL_SOCKET" notify >/dev/null 2>&1 3>&- &
  CLIENT_PID=$!
  wait_client_focus 1
}

# wait_client_focus <1|0>: poll until a client is attached and focused (1) or
# attached and not focused (0).
wait_client_focus() {
  local _i flags
  for _i in $(seq 1 50); do
    flags=$(real_tmux list-clients -F '#{client_flags}' 2>/dev/null)
    if [ -n "$flags" ]; then
      case ",$flags," in
        *,focused,*) [ "$1" = 1 ] && return 0 ;;
        *) [ "$1" = 0 ] && return 0 ;;
      esac
    fi
    sleep 0.1
  done
  return 1
}

pane_flagged() { [ "$(real_tmux display-message -p -t "$1" '#{@notify}')" = 1 ]; }
pane_tinted() { [ -n "$(real_tmux show-options -p -t "$1" window-style 2>/dev/null)" ]; }

@test "real tmux: a focused client watching the pane is not tinted but still hears the sound" {
  attach_real_client
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" fire
  [ "$status" -eq 0 ]
  refute pane_flagged "$ACTIVE_PANE"
  refute pane_tinted "$ACTIVE_PANE"
  [ -z "$(real_tmux display-message -p -t "$ACTIVE_PANE" '#{@notify_window}')" ]
  grep -q 'play via .*afplay' "${LOG_FILE}"
  wait_for_file "$AFPLAY_LOG"
}

@test "real tmux: a client that lost focus gets the full tint and the sound" {
  attach_real_client
  kill -USR1 "$CLIENT_PID"
  wait_client_focus 0
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" fire
  [ "$status" -eq 0 ]
  pane_flagged "$ACTIVE_PANE"
  pane_tinted "$ACTIVE_PANE"
  [ "$(real_tmux display-message -p -t "$ACTIVE_PANE" '#{@notify_window}')" = 1 ]
  wait_for_file "$AFPLAY_LOG"
}

@test "real tmux: a focused client does not shield a pane it is not looking at" {
  attach_real_client
  run_shim_real "$BACKGROUND_PANE" fire
  [ "$status" -eq 0 ]
  pane_flagged "$BACKGROUND_PANE"
  pane_tinted "$BACKGROUND_PANE"
  refute pane_flagged "$ACTIVE_PANE"
}

@test "real tmux: a focused client does not shield a window it is not viewing" {
  attach_real_client
  local other
  other=$(real_tmux new-window -d -P -F '#{pane_id}' -t notify: sleep 60)
  run_shim_real "$other" fire
  [ "$status" -eq 0 ]
  pane_flagged "$other"
  pane_tinted "$other"
}

# wait_client_count <n>: poll until n clients are attached.
wait_client_count() {
  local _i
  for _i in $(seq 1 50); do
    [ "$(real_tmux list-clients 2>/dev/null | wc -l | tr -d ' ')" = "$1" ] && return 0
    sleep 0.1
  done
  return 1
}

@test "real tmux: with two clients one focused client is enough to hold the tint back" {
  attach_real_client
  python3 "$CLIENT_PY" "$REAL_SOCKET" notify >/dev/null 2>&1 3>&- &
  CLIENT2_PID=$!
  wait_client_count 2
  # Blur the first client; the second is still focused, so the pane is watched.
  kill -USR1 "$CLIENT_PID"
  sleep 0.3
  run_shim_real "$ACTIVE_PANE" fire
  [ "$status" -eq 0 ]
  refute pane_flagged "$ACTIVE_PANE"
}

@test "real tmux: with two clients both blurred the pane is tinted" {
  attach_real_client
  python3 "$CLIENT_PY" "$REAL_SOCKET" notify >/dev/null 2>&1 3>&- &
  CLIENT2_PID=$!
  wait_client_count 2
  kill -USR1 "$CLIENT_PID" "$CLIENT2_PID"
  local _i
  for _i in $(seq 1 50); do
    case "$(real_tmux list-clients -F '#{client_flags}')" in *focused*) sleep 0.1 ;; *) break ;; esac
  done
  run_shim_real "$ACTIVE_PANE" fire
  [ "$status" -eq 0 ]
  pane_flagged "$ACTIVE_PANE"
}

@test "real tmux: focus returning to the client restores the gate" {
  attach_real_client
  kill -USR1 "$CLIENT_PID"
  wait_client_focus 0
  run_shim_real "$ACTIVE_PANE" fire
  pane_flagged "$ACTIVE_PANE"
  run_shim_real "$ACTIVE_PANE" clear
  refute pane_flagged "$ACTIVE_PANE"
  kill -USR2 "$CLIENT_PID"
  wait_client_focus 1
  run_shim_real "$ACTIVE_PANE" fire
  [ "$status" -eq 0 ]
  refute pane_flagged "$ACTIVE_PANE"
}

@test "real tmux: with focus reporting off the focused flag is not trusted" {
  attach_real_client
  real_tmux set-option -s focus-events off
  run_shim_real "$ACTIVE_PANE" fire
  [ "$status" -eq 0 ]
  pane_flagged "$ACTIVE_PANE"
}

@test "real tmux: a detached session is tinted as before" {
  start_real_server
  run_shim_real "$ACTIVE_PANE" fire
  [ "$status" -eq 0 ]
  pane_flagged "$ACTIVE_PANE"
}

# --- Verbs for the OpenCode TUI plugin: tint, elsewhere, describe --------------
# The TUI plugin owns the visuals and calls these. `tint own` is the viewed tab's
# own alert (the full group color, the existing @notify flag). `tint elsewhere` is
# another tab needing attention: a dimmed tint and the window pill, but never
# @notify, because the keypress binding clears only a pane whose @notify is set.
# None of them has a focus gate or plays a sound.

DIM_OPENCODE="#353b4f"
DIM_PERMISSION="#3f3a43"
DIM_QUESTION="#3e3e46"

# opt <pane> <option>: a pane or window user option as tmux formats it ("" if unset).
opt() { real_tmux display-message -p -t "$1" "#{$2}"; }
# pane_style <pane>: the pane-local window-style value ("" if it is not set).
pane_style() { real_tmux show-options -pv -t "$1" window-style 2>/dev/null || true; }
pane_active_style() { real_tmux show-options -pv -t "$1" window-active-style 2>/dev/null || true; }
no_sound() {
  [ ! -f "$AFPLAY_LOG" ]
  [ ! -f "${LOG_FILE}" ] || ! grep -q 'play via' "${LOG_FILE}"
}

@test "tint verbs are quiet outside tmux" {
  local verb
  for verb in "tint own opencode" "tint elsewhere opencode_permission" "tint clear"; do
    # shellcheck disable=SC2086  # the verb string is the argument list
    SHIM_CONFIG="$SOUND_CONFIG" TMUX_VAL="" PANE_VAL="" run_shim $verb
    [ "$status" -eq 0 ]
  done
  [ ! -s "$TMUX_CALLS" ]
  no_sound
}

@test "tint verbs skip a stale pane without writing anything" {
  PANE_VAL='%34' run_shim tint own opencode
  [ "$status" -eq 0 ]
  PANE_VAL='%34' run_shim tint elsewhere opencode
  PANE_VAL='%34' run_shim tint clear
  refute grep -q 'set-option' "$TMUX_CALLS"
  grep -q 'stale pane %34' "$LOG_FILE"
}

@test "tint needs a mode, and only own, elsewhere or clear" {
  run_shim tint
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
  run_shim tint sideways opencode
  [ "$status" -eq 2 ]
}

@test "tint verbs have no focus gate: a focused pane is still tinted, in silence" {
  SHIM_CONFIG="$SOUND_CONFIG" PROBE_OUT="$FOCUSED_PROBE" run_shim tint own opencode
  [ "$status" -eq 0 ]
  grep -q 'set-option -p -t %1 window-style bg=#424c68' "$TMUX_CALLS"
  no_sound
}

@test "an unknown tint group falls back to opencode" {
  SHIM_CONFIG="$SOUND_CONFIG" run_shim tint own no_such_group
  [ "$status" -eq 0 ]
  grep -q 'set-option -p -t %1 window-style bg=#424c68' "$TMUX_CALLS"
}

@test "describe works outside tmux and prints the contract" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  SHIM_CONFIG="$SOUND_CONFIG" TMUX_VAL="" PANE_VAL="" run_shim describe
  [ "$status" -eq 0 ]
  [ "$(jget_json "$output" groups opencode bg)" = "#424c68" ]
  [ "$(jget_json "$output" groups opencode_permission sound)" = "" ]
  [ "$(jget_json "$output" groups opencode_question accent)" = "#e5c890" ]
  [ "$(jget_json "$output" elsewhere dim)" = 0.5 ]
  [ "$(jget_json "$output" elsewhere base)" = "#282a36" ]
  [ "$(jget_json "$output" elsewhereBg opencode)" = "$DIM_OPENCODE" ]
  [ "$(jget_json "$output" elsewhereBg opencode_permission)" = "$DIM_PERMISSION" ]
  [ "$(jget_json "$output" elsewhereBg opencode_question)" = "$DIM_QUESTION" ]
  [ ! -s "$TMUX_CALLS" ]
}

@test "describe also works inside tmux without calling it" {
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  SHIM_CONFIG="$SOUND_CONFIG" run_shim describe
  [ "$status" -eq 0 ]
  [ "$(jget_json "$output" groups opencode accent)" = "#8caaee" ]
  [ ! -s "$TMUX_CALLS" ]
}

@test "describe prints {} and exits 0 when the config is unreadable" {
  SHIM_CONFIG="${FAKE_HOME}/missing.yaml" TMUX_VAL="" PANE_VAL="" run_shim describe
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "describe prints {} and exits 0 when the notify library is missing" {
  rm "${FAKE_HOME}/.config/notify/lib.sh"
  TMUX_VAL="" PANE_VAL="" run_shim describe
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

jget_json() {
  printf '%s' "$1" | python3 -c 'import json, sys
v = json.load(sys.stdin)
for k in sys.argv[1:]:
    v = v[k]
print(v)' "${@:2}"
}

@test "real tmux: tint own tints the viewed pane and sets the pill, with no gate and no sound" {
  attach_real_client
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint own opencode
  [ "$status" -eq 0 ]
  [ "$(opt "$ACTIVE_PANE" @notify)" = 1 ]
  [ "$(opt "$ACTIVE_PANE" @notify_accent)" = "#8caaee" ]
  [ "$(pane_style "$ACTIVE_PANE")" = "bg=#424c68" ]
  [ "$(pane_active_style "$ACTIVE_PANE")" = "bg=#424c68" ]
  [ "$(opt "$ACTIVE_PANE" @notify_window)" = 1 ]
  [ "$(opt "$ACTIVE_PANE" @notify_window_accent)" = "#8caaee" ]
  no_sound
}

@test "real tmux: tint elsewhere stores the dimmed color and never sets @notify" {
  attach_real_client
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint elsewhere opencode_permission
  [ "$status" -eq 0 ]
  [ -z "$(opt "$ACTIVE_PANE" @notify)" ]
  [ "$(opt "$ACTIVE_PANE" @notify_elsewhere_bg)" = "$DIM_PERMISSION" ]
  [ "$(opt "$ACTIVE_PANE" @notify_elsewhere_accent)" = "#ef9f76" ]
  [ "$(pane_style "$ACTIVE_PANE")" = "bg=$DIM_PERMISSION" ]
  [ "$(pane_active_style "$ACTIVE_PANE")" = "bg=$DIM_PERMISSION" ]
  [ "$(opt "$ACTIVE_PANE" @notify_window)" = 1 ]
  [ "$(opt "$ACTIVE_PANE" @notify_window_accent)" = "#ef9f76" ]
  no_sound
}

@test "real tmux: own supersedes elsewhere in either order and keeps the stored state" {
  attach_real_client
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint elsewhere opencode_permission
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint own opencode_question
  [ "$(opt "$ACTIVE_PANE" @notify)" = 1 ]
  [ "$(pane_style "$ACTIVE_PANE")" = "bg=#545255" ]
  [ "$(opt "$ACTIVE_PANE" @notify_window_accent)" = "#e5c890" ]
  [ "$(opt "$ACTIVE_PANE" @notify_elsewhere_bg)" = "$DIM_PERMISSION" ]
  # Elsewhere arriving while an own tint shows changes nothing visible.
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint elsewhere opencode
  [ "$(pane_style "$ACTIVE_PANE")" = "bg=#545255" ]
  [ "$(opt "$ACTIVE_PANE" @notify_window_accent)" = "#e5c890" ]
  [ "$(opt "$ACTIVE_PANE" @notify_elsewhere_bg)" = "$DIM_OPENCODE" ]
  [ "$(opt "$ACTIVE_PANE" @notify_elsewhere_accent)" = "#8caaee" ]
}

@test "real tmux: the clear verb drops the own tint and re-applies the elsewhere one" {
  attach_real_client
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint elsewhere opencode_permission
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint own opencode
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" clear
  [ "$status" -eq 0 ]
  [ -z "$(opt "$ACTIVE_PANE" @notify)" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_accent)" ]
  [ "$(pane_style "$ACTIVE_PANE")" = "bg=$DIM_PERMISSION" ]
  [ "$(pane_active_style "$ACTIVE_PANE")" = "bg=$DIM_PERMISSION" ]
  [ "$(opt "$ACTIVE_PANE" @notify_window)" = 1 ]
  [ "$(opt "$ACTIVE_PANE" @notify_window_accent)" = "#ef9f76" ]
  [ "$(opt "$ACTIVE_PANE" @notify_elsewhere_bg)" = "$DIM_PERMISSION" ]
}

@test "real tmux: the clear verb with no elsewhere state leaves nothing behind" {
  attach_real_client
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint own opencode
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" clear
  [ -z "$(opt "$ACTIVE_PANE" @notify)" ]
  [ -z "$(pane_style "$ACTIVE_PANE")" ]
  [ -z "$(pane_active_style "$ACTIVE_PANE")" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_window)" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_elsewhere_bg)" ]
}

@test "real tmux: tint clear removes own and elsewhere state, the style and the pill" {
  attach_real_client
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint elsewhere opencode_permission
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint own opencode
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint clear
  [ "$status" -eq 0 ]
  [ -z "$(opt "$ACTIVE_PANE" @notify)" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_elsewhere_bg)" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_elsewhere_accent)" ]
  [ -z "$(pane_style "$ACTIVE_PANE")" ]
  [ -z "$(pane_active_style "$ACTIVE_PANE")" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_window)" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_window_accent)" ]
}

@test "real tmux: the window pill outlives one pane's clear while another pane still needs attention" {
  attach_real_client
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint own opencode
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$BACKGROUND_PANE" tint elsewhere opencode_permission
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint clear
  # The other pane's elsewhere tint still holds the pill, with its own accent.
  [ "$(opt "$BACKGROUND_PANE" @notify_window)" = 1 ]
  [ "$(opt "$BACKGROUND_PANE" @notify_window_accent)" = "#ef9f76" ]
  [ "$(pane_style "$BACKGROUND_PANE")" = "bg=$DIM_PERMISSION" ]
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$BACKGROUND_PANE" tint clear
  [ -z "$(opt "$BACKGROUND_PANE" @notify_window)" ]
}

# lib_call <function> [args]: run one notify library function on the pane under
# test, against the real isolated server, with the attribute lookup and the player
# replaced so no config or sound is involved.
lib_call() {
  # The script is deliberately single-quoted: its $1, $2 are its own arguments.
  # shellcheck disable=SC2016
  run env TMUX="$REAL_TMUX_ENV" bash -c '. "$1"
    _notify_fire_attrs() { printf "%s" "#112233|#445566||75"; }
    notify_play() { :; }
    pane=$2 fn=$3; shift 3
    "$fn" "$pane" "$@"' _ "$LIB_SRC" "$ACTIVE_PANE" "$@"
}

@test "real tmux: Claude, Codex and zsh callers never see the elsewhere option" {
  # notify_fire and notify_clear with no elsewhere state behave exactly as before:
  # the tint, the flag and the pill are set, then cleared, and no elsewhere option
  # is ever created.
  start_real_server
  lib_call notify_fire claude
  [ "$status" -eq 0 ]
  [ "$(opt "$ACTIVE_PANE" @notify)" = 1 ]
  [ "$(pane_style "$ACTIVE_PANE")" = "bg=#112233" ]
  [ "$(opt "$ACTIVE_PANE" @notify_window_accent)" = "#445566" ]
  lib_call notify_clear claude-prompt
  [ "$status" -eq 0 ]
  [ -z "$(opt "$ACTIVE_PANE" @notify)" ]
  [ -z "$(pane_style "$ACTIVE_PANE")" ]
  [ -z "$(pane_active_style "$ACTIVE_PANE")" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_window)" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_window_accent)" ]
  [ -z "$(real_tmux show-options -p -t "$ACTIVE_PANE" 2>/dev/null | { grep elsewhere || true; })" ]
}

# --- The real keypress binding ---------------------------------------------------
# A server that sources the managed notify.conf, an attached client, and a key
# typed into it. The binding clears a pane only `if-shell -F '#{@notify}'`.

attach_keyed_client() {
  command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  REAL_SOCKET="notify-keys-$$-${BATS_TEST_NUMBER}"
  KEYFIFO="${FAKE_HOME}/keys"
  TYPED="${FAKE_HOME}/typed"
  mkfifo "$KEYFIFO"
  exec 7<>"$KEYFIFO"
  printf 'set -g focus-events on\nsource-file "%s"\n' "$NOTIFY_CONF" > "${FAKE_HOME}/tmux.conf"
  # The server's HOME is the fake one, so the binding's ~/.config/notify/clear-pane.sh
  # is the copy installed in setup, and the library reads the test config.
  env HOME="$FAKE_HOME" NOTIFY_CONFIG="$SOUND_CONFIG" NOTIFY_SOUNDS="${FAKE_HOME}/sounds" \
    NOTIFY_DEBUG=1 NOTIFY_LOG="$LOG_FILE" PATH="${PLAYER_DIR}:${PATH}" \
    tmux -L "$REAL_SOCKET" -f "${FAKE_HOME}/tmux.conf" new-session -d -s notify -x 90 -y 24 \
    "cat > '${TYPED}'"
  REAL_TMUX_ENV="$(real_tmux display-message -p -t notify:0 '#{socket_path}'),0,0"
  ACTIVE_PANE=$(real_tmux display-message -p -t notify:0 '#{pane_id}')
  python3 "$CLIENT_PY" "$REAL_SOCKET" notify <&7 >/dev/null 2>&1 3>&- &
  CLIENT_PID=$!
  wait_client_focus 1
}

# type_key: send a character and a newline, and wait until the pane's program has
# received it, which proves the root key binding ran to the end.
type_key() {
  local _i
  printf 'x\n' >&7
  for _i in $(seq 1 50); do
    [ -s "$TYPED" ] && break
    sleep 0.1
  done
  [ -s "$TYPED" ]
  # run-shell is asynchronous; give a (wrong) clear time to land.
  sleep 0.6
}

@test "real tmux: a keypress leaves an elsewhere-only tint alone" {
  attach_keyed_client
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint elsewhere opencode_permission
  type_key
  [ "$(pane_style "$ACTIVE_PANE")" = "bg=$DIM_PERMISSION" ]
  [ "$(opt "$ACTIVE_PANE" @notify_elsewhere_bg)" = "$DIM_PERMISSION" ]
  [ "$(opt "$ACTIVE_PANE" @notify_window)" = 1 ]
  [ "$(opt "$ACTIVE_PANE" @notify_window_accent)" = "#ef9f76" ]
}

@test "real tmux: a keypress clears the own tint and falls back to the elsewhere one" {
  attach_keyed_client
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint elsewhere opencode_permission
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint own opencode
  [ "$(pane_style "$ACTIVE_PANE")" = "bg=#424c68" ]
  type_key
  [ -z "$(opt "$ACTIVE_PANE" @notify)" ]
  [ "$(pane_style "$ACTIVE_PANE")" = "bg=$DIM_PERMISSION" ]
  [ "$(pane_active_style "$ACTIVE_PANE")" = "bg=$DIM_PERMISSION" ]
  [ "$(opt "$ACTIVE_PANE" @notify_window)" = 1 ]
  [ "$(opt "$ACTIVE_PANE" @notify_window_accent)" = "#ef9f76" ]
}

@test "real tmux: a keypress clears an own-only tint completely, as before" {
  attach_keyed_client
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" tint own opencode
  type_key
  [ -z "$(opt "$ACTIVE_PANE" @notify)" ]
  [ -z "$(pane_style "$ACTIVE_PANE")" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_window)" ]
}

# The attention-tabs plugin and this shim were each tested against a stub of the
# other, which let the plugin spawn `own <group>` where the shim expects
# `tint own <group>`. These tests feed the plugin's real argv to the real shim.
ATTENTION_RANK="${CHEZMOI_DIR}/home/dot_config/opencode/v2-plugins/attention-tabs/rank.mjs"

# plugin_argv <active tab> <target tab> <rank> <kind>: the argv the plugin derives
# for two tabs, a and b, where the target has the given state ("none" for idle).
plugin_argv() {
  command -v node >/dev/null 2>&1 || skip "node not installed"
  node --input-type=module -e "
    import { sinkState } from '${ATTENTION_RANK}'
    const [active, target, rank, kind] = process.argv.slice(1)
    const entries = ['a', 'b'].map((id) => id === target && rank !== 'none'
      ? { sessionID: id, rank: Number(rank), since: 1, kind }
      : { sessionID: id, rank: 0, since: 0, kind: 'none' })
    console.log(sinkState(entries, active).args.join(' '))
  " "$@"
}

@test "contract: the argv the plugin derives for another tab's permission is a shim verb that works" {
  attach_real_client
  local argv
  argv=$(plugin_argv a b 4 permission)
  [ "$argv" = "tint elsewhere opencode_permission" ]
  # shellcheck disable=SC2086  # the derived argv is the verb's argument list
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" $argv
  [ "$status" -eq 0 ]
  [ "$(opt "$ACTIVE_PANE" @notify_elsewhere_bg)" = "$DIM_PERMISSION" ]
  [ "$(pane_style "$ACTIVE_PANE")" = "bg=$DIM_PERMISSION" ]
}

@test "contract: the argv for the viewed tab's own alert tints it, and the clear argv removes both" {
  attach_real_client
  local own clear_argv elsewhere
  elsewhere=$(plugin_argv a b 3 question)
  # shellcheck disable=SC2086
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" $elsewhere
  own=$(plugin_argv b b 4 permission)
  [ "$own" = "tint own opencode_permission" ]
  # shellcheck disable=SC2086
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" $own
  [ "$(opt "$ACTIVE_PANE" @notify)" = 1 ]
  clear_argv=$(plugin_argv a b none)
  [ "$clear_argv" = "tint clear" ]
  # shellcheck disable=SC2086
  SHIM_CONFIG="$SOUND_CONFIG" run_shim_real "$ACTIVE_PANE" $clear_argv
  [ "$status" -eq 0 ]
  # Unlike the plain `clear` verb, this drops the elsewhere state as well.
  [ -z "$(opt "$ACTIVE_PANE" @notify)" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_elsewhere_bg)" ]
  [ -z "$(pane_style "$ACTIVE_PANE")" ]
  [ -z "$(opt "$ACTIVE_PANE" @notify_window)" ]
}
