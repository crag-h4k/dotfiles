#!/usr/bin/env bats
# tests/test_lib.bats

CHEZMOI_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
NOTIFY_LIB="${CHEZMOI_DIR}/home/dot_config/notify/lib.sh"
FIXTURES="${BATS_TEST_DIRNAME}/fixtures"

setup() {
  export NOTIFY_CONFIG="${FIXTURES}/notify.yaml"
  unset TMUX
  unset TMUX_PANE
  STUB_DIR="${BATS_TMPDIR}/stubs-$$"
  mkdir -p "$STUB_DIR"
  TMUX_STUB_LOG="${BATS_TMPDIR}/tmux-calls-$$"
  rm -f "$TMUX_STUB_LOG"
}

teardown() {
  rm -rf "$STUB_DIR" "$TMUX_STUB_LOG"
}

@test "notify_fire is a no-op when pane arg is empty" {
  run bash -c "
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    source '${NOTIFY_LIB}'
    notify_fire '' test_group
  "
  [ "$status" -eq 0 ]
}

@test "notify_clear is a no-op when pane arg is empty" {
  run bash -c "
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    source '${NOTIFY_LIB}'
    notify_clear ''
  "
  [ "$status" -eq 0 ]
}

@test "notify_clear succeeds after clearing a pane when debug logging is off" {
  cat > "${STUB_DIR}/tmux" <<'STUB'
#!/bin/sh
exit 0
STUB
  chmod +x "${STUB_DIR}/tmux"

  run bash -c "
    export PATH='${STUB_DIR}:${PATH}'
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    unset NOTIFY_DEBUG
    source '${NOTIFY_LIB}'
    notify_clear '%1'
  "
  [ "$status" -eq 0 ]
}

@test "notify_fire does not call tmux when pane is empty" {
  cat > "${STUB_DIR}/tmux" <<'STUB'
#!/bin/sh
echo "tmux called" >> "${TMUX_STUB_LOG}"
STUB
  chmod +x "${STUB_DIR}/tmux"

  run bash -c "
    export PATH='${STUB_DIR}:${PATH}'
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    export TMUX_STUB_LOG='${TMUX_STUB_LOG}'
    source '${NOTIFY_LIB}'
    notify_fire '' test_group
  "
  [ "$status" -eq 0 ]
  [ ! -f "$TMUX_STUB_LOG" ]
}

# notify_fire's optional third argument, "sound": play the group's sound and
# leave tmux alone. The opencode shim uses it outside tmux and when a focused
# client is already looking at the pane. The two-argument call is the contract
# zsh, Claude and Codex rely on, so it must keep tinting.

sound_fixture() {
  SOUND_DIR="${BATS_TEST_TMPDIR}/sounds"
  mkdir -p "$SOUND_DIR"
  touch "${SOUND_DIR}/ping.mp3"
  SOUND_CONFIG="${BATS_TEST_TMPDIR}/notify-sound.yaml"
  cat > "$SOUND_CONFIG" <<'YAML'
settings:
  volume: 40
integrations:
  loud:
    bg: "#112233"
    accent: "#445566"
    sound: ping.mp3
  quiet:
    bg: "#112233"
    accent: "#445566"
    sound: ""
YAML
  cat > "${STUB_DIR}/tmux" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "${TMUX_STUB_LOG}"
STUB
  cat > "${STUB_DIR}/afplay" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "${AFPLAY_STUB_LOG}"
STUB
  chmod +x "${STUB_DIR}/tmux" "${STUB_DIR}/afplay"
  AFPLAY_STUB_LOG="${BATS_TEST_TMPDIR}/afplay-calls"
  rm -f "$AFPLAY_STUB_LOG"
}

fire_with() {
  run env PATH="${STUB_DIR}:${PATH}" NOTIFY_CONFIG="$SOUND_CONFIG" NOTIFY_SOUNDS="$SOUND_DIR" \
    TMUX_STUB_LOG="$TMUX_STUB_LOG" AFPLAY_STUB_LOG="$AFPLAY_STUB_LOG" \
    bash -c ". '${NOTIFY_LIB}'; notify_fire \"\$@\"" _ "$@"
}

wait_for_afplay() {
  local _i
  for _i in $(seq 1 50); do
    [ -s "$AFPLAY_STUB_LOG" ] && return 0
    sleep 0.1
  done
  return 1
}

@test "notify_fire with sound only plays the group sound and never calls tmux" {
  sound_fixture
  fire_with '%1' loud sound
  [ "$status" -eq 0 ]
  wait_for_afplay
  grep -q 'ping.mp3' "$AFPLAY_STUB_LOG"
  grep -q -- '-v 0.40' "$AFPLAY_STUB_LOG"
  [ ! -f "$TMUX_STUB_LOG" ]
}

@test "notify_fire with sound only needs no pane" {
  sound_fixture
  fire_with '' loud sound
  [ "$status" -eq 0 ]
  wait_for_afplay
  grep -q 'ping.mp3' "$AFPLAY_STUB_LOG"
  [ ! -f "$TMUX_STUB_LOG" ]
}

@test "notify_fire with sound only stays silent for an empty sound" {
  sound_fixture
  fire_with '%1' quiet sound
  [ "$status" -eq 0 ]
  [ ! -f "$TMUX_STUB_LOG" ]
  sleep 0.3
  [ ! -f "$AFPLAY_STUB_LOG" ]
}

@test "notify_fire without the third argument still tints the pane and plays" {
  sound_fixture
  fire_with '%1' loud
  [ "$status" -eq 0 ]
  grep -q 'set-option -p -t %1 window-style bg=#112233' "$TMUX_STUB_LOG"
  grep -q 'set-option -w -t %1 @notify_window 1' "$TMUX_STUB_LOG"
  wait_for_afplay
}

@test "notify_fire ignores an unknown third argument and tints" {
  sound_fixture
  fire_with '%1' quiet loud
  [ "$status" -eq 0 ]
  grep -q 'window-style' "$TMUX_STUB_LOG"
}

# Skip a test that needs the mikefarah yq the library depends on, and python3 to
# read the JSON it prints.
require_yq_and_python() {
  command -v yq >/dev/null 2>&1 || skip "yq not installed"
  yq --version 2>/dev/null | grep -qi mikefarah || skip "mikefarah yq not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
}

# notify_attention_config: OpenCode's own attention.sound, built from notify.yaml.
# The opencode2 wrapper exports it outside tmux, where this notifier is silent.
# Native sound overrides fall back to a BUNDLED sound when a path is missing or
# empty, so an empty `sound:` here maps to the shipped silence.mp3 instead.

SILENCE_SRC="${CHEZMOI_DIR}/home/dot_config/notify/sounds/silence.mp3"

attention_fixture() {
  require_yq_and_python
  SOUND_DIR="${BATS_TEST_TMPDIR}/sounds"
  mkdir -p "$SOUND_DIR"
  touch "${SOUND_DIR}/ping.mp3" "${SOUND_DIR}/knock.mp3" "${SOUND_DIR}/latch.mp3"
  cp "$SILENCE_SRC" "${SOUND_DIR}/silence.mp3"
  ATTN_CONFIG="${BATS_TEST_TMPDIR}/attention.yaml"
  cat > "$ATTN_CONFIG" <<'YAML'
settings:
  volume: 60
integrations:
  opencode:
    sound: ping.mp3
    volume: 30
  opencode_permission:
    sound: knock.mp3
  opencode_question:
    sound: latch.mp3
YAML
}

attention() {
  run env NOTIFY_CONFIG="$ATTN_CONFIG" NOTIFY_SOUNDS="$SOUND_DIR" HOME="${BATS_TEST_TMPDIR}/nohome" \
    bash -c ". '${NOTIFY_LIB}'; notify_attention_config"
}

# jget <json> <key>...: print the value at a path in a JSON document.
jget() {
  printf '%s' "$1" | python3 -c 'import json, sys
v = json.load(sys.stdin)
for k in sys.argv[1:]:
    v = v[k]
print(v)' "${@:2}"
}

@test "attention config maps done and default to the opencode sound and silences subagent_done" {
  attention_fixture
  attention
  [ "$status" -eq 0 ]
  [ "$(jget "$output" attention sound)" = True ]
  [ "$(jget "$output" attention sounds "done")" = "${SOUND_DIR}/ping.mp3" ]
  [ "$(jget "$output" attention sounds subagent_done)" = "${SOUND_DIR}/silence.mp3" ]
  [ "$(jget "$output" attention sounds default)" = "${SOUND_DIR}/ping.mp3" ]
}

@test "attention config maps permission and error to the permission sound, question to its own" {
  attention_fixture
  attention
  [ "$(jget "$output" attention sounds permission)" = "${SOUND_DIR}/knock.mp3" ]
  [ "$(jget "$output" attention sounds error)" = "${SOUND_DIR}/knock.mp3" ]
  [ "$(jget "$output" attention sounds question)" = "${SOUND_DIR}/latch.mp3" ]
}

@test "attention config uses absolute paths and never a tilde" {
  attention_fixture
  attention
  [[ "$output" != *'"~'* ]]
  [[ "$(jget "$output" attention sounds "done")" == /* ]]
}

@test "attention volume is the opencode integration volume scaled to 0 to 1" {
  attention_fixture
  attention
  [ "$(jget "$output" attention volume)" = 0.3 ]
}

@test "attention volume falls back to settings.volume, then 75" {
  attention_fixture
  sed -i.bak '/^    volume: 30$/d' "$ATTN_CONFIG"
  attention
  [ "$(jget "$output" attention volume)" = 0.6 ]
  sed -i.bak '/^  volume: 60$/d' "$ATTN_CONFIG"
  attention
  [ "$(jget "$output" attention volume)" = 0.75 ]
}

@test "attention volume is clamped to the 0 to 1 range" {
  attention_fixture
  sed -i.bak 's/^    volume: 30$/    volume: 250/' "$ATTN_CONFIG"
  attention
  [ "$(jget "$output" attention volume)" = 1.0 ]
  sed -i.bak 's/^    volume: 250$/    volume: loud/' "$ATTN_CONFIG"
  attention
  [ "$(jget "$output" attention volume)" = 0.75 ]
}

@test "an empty sound maps to the shipped silence file, not to the bundled fallback" {
  attention_fixture
  sed -i.bak 's/^    sound: latch.mp3$/    sound: ""/' "$ATTN_CONFIG"
  attention
  [ "$status" -eq 0 ]
  [ "$(jget "$output" attention sounds question)" = "${SOUND_DIR}/silence.mp3" ]
  # The other events keep their own sounds.
  [ "$(jget "$output" attention sounds "done")" = "${SOUND_DIR}/ping.mp3" ]
}

@test "a group missing from the config is silent rather than a bundled sound" {
  attention_fixture
  printf 'settings:\n  volume: 60\nintegrations:\n  opencode:\n    sound: ping.mp3\n' > "$ATTN_CONFIG"
  attention
  [ "$(jget "$output" attention sounds permission)" = "${SOUND_DIR}/silence.mp3" ]
  [ "$(jget "$output" attention sounds question)" = "${SOUND_DIR}/silence.mp3" ]
}

@test "a sound file that does not exist maps to silence, as notify_play would stay quiet" {
  attention_fixture
  rm "${SOUND_DIR}/knock.mp3"
  attention
  [ "$(jget "$output" attention sounds permission)" = "${SOUND_DIR}/silence.mp3" ]
  [ "$(jget "$output" attention sounds "done")" = "${SOUND_DIR}/ping.mp3" ]
}

@test "attention config prints nothing when the silence file is missing" {
  attention_fixture
  rm "${SOUND_DIR}/silence.mp3"
  attention
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "attention config prints nothing when the config is missing" {
  attention_fixture
  rm "$ATTN_CONFIG"
  attention
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "attention config prints nothing when yq is unavailable" {
  attention_fixture
  # The resolver memoizes its result in these two process globals, so presetting
  # them is the same as no mikefarah yq anywhere.
  run env _NOTIFY_YQ_READY=1 _NOTIFY_YQ= NOTIFY_CONFIG="$ATTN_CONFIG" NOTIFY_SOUNDS="$SOUND_DIR" \
    bash -c ". '${NOTIFY_LIB}'; notify_attention_config"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "attention config escapes a sound directory that needs JSON escaping" {
  attention_fixture
  mkdir -p "${BATS_TEST_TMPDIR}/odd \"dir\""
  cp "${SOUND_DIR}"/*.mp3 "${BATS_TEST_TMPDIR}/odd \"dir\"/"
  SOUND_DIR="${BATS_TEST_TMPDIR}/odd \"dir\""
  attention
  [ "$status" -eq 0 ]
  [ "$(jget "$output" attention sounds "done")" = "${SOUND_DIR}/ping.mp3" ]
}

@test "the shipped silence file is a real, short, silent mp3" {
  [ -s "$SILENCE_SRC" ]
  # Frame sync, then a plausible size: a few hundredths of a second to a second.
  [ "$(head -c 2 "$SILENCE_SRC" | od -An -tx1 | tr -d ' \n' | cut -c1-3)" = "fff" ]
  [ "$(wc -c < "$SILENCE_SRC")" -lt 20000 ]
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -hide_banner -i "$SILENCE_SRC" -af volumedetect -f null - 2>&1 | grep -q 'max_volume: -91.0 dB'
  fi
}

# notify_blend_hex <bg> <base> <ratio>: the dimmed background of an "elsewhere"
# tint, the group color blended toward the palette background. Ratio 0 is the full
# group color and 1 is the base. It is POSIX shell arithmetic only, so it has to
# give the same answer under macOS /bin/bash 3.2, a current bash, dash, and zsh.

blend_shells() {
  local sh
  for sh in bash /bin/bash dash /bin/dash zsh; do
    command -v "$sh" >/dev/null 2>&1 && printf '%s\n' "$sh"
  done | sort -u
}

blend_expect() {
  # blend_expect <bg> <base> <ratio> <expected>, in every shell that is installed
  local sh got
  for sh in $(blend_shells); do
    got=$("$sh" -c ". '${NOTIFY_LIB}'; notify_blend_hex \"\$@\"" _ "$1" "$2" "$3") || got="<failed>"
    if [ "$got" != "$4" ]; then
      echo "shell=$sh blend($1,$2,$3) got=[$got] want=[$4]" >&2
      return 1
    fi
  done
}

@test "blend: the half way point, in every installed shell" {
  blend_expect '#5b1a1a' '#282a36' 0.5 '#422228'
  blend_expect '#424c68' '#282a36' 0.5 '#353b4f'
  blend_expect '#564950' '#282a36' 0.5 '#3f3a43'
}

@test "blend: ratio 0 is the group color and ratio 1 is the base" {
  blend_expect '#5b1a1a' '#282a36' 0 '#5b1a1a'
  blend_expect '#5b1a1a' '#282a36' 0.0 '#5b1a1a'
  blend_expect '#5b1a1a' '#282a36' 1 '#282a36'
  blend_expect '#5b1a1a' '#282a36' 1.0 '#282a36'
}

@test "blend: other ratios, including leading-zero fractions that octal would break" {
  blend_expect '#5b1a1a' '#282a36' 0.25 '#4e1e21'
  blend_expect '#5b1a1a' '#282a36' .5 '#422228'
  blend_expect '#5b1a1a' '#282a36' 0.05 '#581b1b'
  blend_expect '#5b1a1a' '#282a36' 0.008 '#5b1a1a'
  blend_expect '#5b1a1a' '#282a36' 0.123456 '#551c1d'
}

@test "blend: a ratio above 1 clamps to the base, an unparsable one means 0.5" {
  blend_expect '#5b1a1a' '#282a36' 2 '#282a36'
  blend_expect '#5b1a1a' '#282a36' abc '#422228'
  blend_expect '#5b1a1a' '#282a36' -1 '#422228'
  blend_expect '#5b1a1a' '#282a36' '' '#422228'
  blend_expect '#5b1a1a' '#282a36' 0.1.2 '#422228'
}

@test "blend: hex digits are case-insensitive and the result is lowercase" {
  blend_expect '#5B1A1A' '#282A36' 0.5 '#422228'
}

@test "blend: a color that is not #rrggbb passes through unchanged" {
  blend_expect default '#282a36' 0.5 default
  blend_expect '#fff' '#282a36' 0.5 '#fff'
  blend_expect '#5b1a1a' default 0.5 '#5b1a1a'
  blend_expect '#5b1a1a' '' 0.5 '#5b1a1a'
  blend_expect '#5b1a1azz' '#282a36' 0.5 '#5b1a1azz'
}

# notify_describe: what the OpenCode TUI plugin reads to draw its own indicators.

describe_fixture() {
  require_yq_and_python
  DESC_CONFIG="${BATS_TEST_TMPDIR}/describe.yaml"
  cat > "$DESC_CONFIG" <<'YAML'
settings:
  volume: 50
  elsewhere_dim: 0.5
palette:
  background: "#282a36"
  dark_blue: "#424c68"
  bright_blue: "#8caaee"
  bright_orange: "#ef9f76"
  bright_yellow: "#e5c890"
integrations:
  opencode:
    bg: dark_blue
    accent: bright_blue
    sound: glass.mp3
    volume: 30
  opencode_permission:
    bg: "#564950"
    accent: bright_orange
    sound: ""
  opencode_question:
    bg: default
    accent: bright_yellow
    sound: latch.mp3
YAML
}

describe() {
  run env NOTIFY_CONFIG="$DESC_CONFIG" HOME="${BATS_TEST_TMPDIR}/nohome" \
    bash -c ". '${NOTIFY_LIB}'; notify_describe"
}

@test "describe prints the groups, the elsewhere settings and the dimmed backgrounds" {
  describe_fixture
  describe
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(jget "$output" groups opencode bg)" = "#424c68" ]
  [ "$(jget "$output" groups opencode accent)" = "#8caaee" ]
  [ "$(jget "$output" groups opencode sound)" = "glass.mp3" ]
  [ "$(jget "$output" groups opencode volume)" = 30 ]
  [ "$(jget "$output" groups opencode_permission bg)" = "#564950" ]
  [ "$(jget "$output" groups opencode_permission accent)" = "#ef9f76" ]
  [ "$(jget "$output" groups opencode_permission sound)" = "" ]
  [ "$(jget "$output" groups opencode_permission volume)" = 50 ]
  [ "$(jget "$output" groups opencode_question sound)" = "latch.mp3" ]
  [ "$(jget "$output" elsewhere dim)" = 0.5 ]
  [ "$(jget "$output" elsewhere base)" = "#282a36" ]
  [ "$(jget "$output" elsewhereBg opencode)" = "#353b4f" ]
  [ "$(jget "$output" elsewhereBg opencode_permission)" = "#3f3a43" ]
}

@test "describe passes a non-hex background through undimmed" {
  describe_fixture
  describe
  [ "$(jget "$output" groups opencode_question bg)" = "default" ]
  [ "$(jget "$output" elsewhereBg opencode_question)" = "default" ]
}

@test "describe follows settings.elsewhere_dim and defaults it to 0.5" {
  describe_fixture
  sed -i.bak 's/^  elsewhere_dim: 0.5$/  elsewhere_dim: 0.25/' "$DESC_CONFIG"
  describe
  [ "$(jget "$output" elsewhere dim)" = 0.25 ]
  [ "$(jget "$output" elsewhereBg opencode)" = "#3c445c" ]
  sed -i.bak '/elsewhere_dim/d' "$DESC_CONFIG"
  describe
  [ "$(jget "$output" elsewhere dim)" = 0.5 ]
  [ "$(jget "$output" elsewhereBg opencode)" = "#353b4f" ]
}

@test "describe leaves the group colors when the palette has no background" {
  describe_fixture
  sed -i.bak '/^  background:/d' "$DESC_CONFIG"
  describe
  [ "$status" -eq 0 ]
  [ "$(jget "$output" elsewhere base)" = "" ]
  [ "$(jget "$output" elsewhereBg opencode)" = "#424c68" ]
}

@test "describe prints {} and exits 0 when the config is unreadable" {
  describe_fixture
  rm "$DESC_CONFIG"
  describe
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "describe prints {} and exits 0 when yq is unavailable" {
  describe_fixture
  run env _NOTIFY_YQ_READY=1 _NOTIFY_YQ= NOTIFY_CONFIG="$DESC_CONFIG" \
    bash -c ". '${NOTIFY_LIB}'; notify_describe"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "notify_play silently skips when no sound player found" {
  run bash -c "
    export PATH='/usr/bin:/bin'
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    source '${NOTIFY_LIB}'
    notify_play 'funk.mp3' 75
  "
  [ "$status" -eq 0 ]
}

@test "config resolves under a stripped PATH (grep/yq fallback hardening)" {
  # Needs a real mikefarah yq to read the fixture; skip where it is absent.
  command -v yq >/dev/null 2>&1 && yq --version 2>/dev/null | grep -qi mikefarah || skip "mikefarah yq not installed"
  run bash -c "
    export PATH=''
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    source '${NOTIFY_LIB}'
    _notify_fire_attrs claude
  "
  [ "$status" -eq 0 ]
  # dark_pink (#4d1a38) is the fixture's 'claude' integration bg, NOT the built-in
  # #5b1a1a fallback - so resolving it proves _notify_yq_resolve found grep + yq
  # despite the empty PATH. Without the _NOTIFY_SYSPATH augmentation this is empty.
  [[ "$output" == *"#4d1a38"* ]]
}

@test "notify_debug_on returns false when config has debug: false" {
  run bash -c "
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    source '${NOTIFY_LIB}'
    notify_debug_on && echo 'on' || echo 'off'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "off" ]
}

@test "notify_log is silent when debug is off" {
  local logfile="${BATS_TMPDIR}/test-notify.log"
  rm -f "$logfile"
  run bash -c "
    export NOTIFY_CONFIG='${FIXTURES}/notify.yaml'
    export NOTIFY_LOG='${logfile}'
    source '${NOTIFY_LIB}'
    notify_log 'should not appear'
  "
  [ "$status" -eq 0 ]
  [ ! -f "$logfile" ]
}

@test "notify_log succeeds under errexit with an ordinary log path" {
  run bash -ec 'export NOTIFY_CONFIG="$1" NOTIFY_LOG="$2" NOTIFY_DEBUG=0; . "$3"; notify_log "quiet"' \
    _ "${FIXTURES}/notify.yaml" "${BATS_TEST_TMPDIR}/notify.log" "$NOTIFY_LIB"
  [ "$status" -eq 0 ]
}
