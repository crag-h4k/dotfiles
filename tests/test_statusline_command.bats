#!/usr/bin/env bats
# tests/test_statusline_command.bats
# Tests for dot_claude/executable_statusline-command.sh (the fast renderer).
#
# The script is run hermetically: a temp HOME (so the gud-palette.sh override is
# absent and ORANGE falls back to the truecolor default), a temp XDG_CACHE_HOME
# (where the Sigma total cache is seeded), fixture stdin payloads piped in, and a
# throwaway git repo for the branch/dirty segment. Colors are asserted as raw SGR
# escape sequences (ESC via $'\e'). Fixtures set transcript_path="" so the detached
# updater is never spawned during a test.

CHEZMOI_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SCRIPT="${CHEZMOI_DIR}/dot_claude/executable_statusline-command.sh"
FIXTURES="${BATS_TEST_DIRNAME}/fixtures/statusline"

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache"
  PLAINDIR="${BATS_TEST_TMPDIR}/plain"    # a real dir that is not a git repo
  mkdir -p "$HOME" "$XDG_CACHE_HOME" "$PLAINDIR"
  # Pin the width tier deterministically: unset COLUMNS so the renderer takes its
  # no-width fallback (MED, the previous fixed layout), regardless of the runner's
  # environment. The width-specific tests below set COLUMNS explicitly per case.
  unset COLUMNS LINES
  # Isolate every git call (the git_repo helper AND the renderer's branch/dirty
  # detection) from any inherited git context. Under pre-commit, GIT_INDEX_FILE /
  # GIT_DIR / GIT_OBJECT_DIRECTORY etc. point at the parent chezmoi repo, so the
  # helper's `git add`/`commit` build trees against the parent index and fail with
  # "invalid object ... / Error building trees". `git -C` changes the cwd but does
  # NOT override these env vars, which take precedence. Clearing them makes git
  # discover the temp repo. Explicit list (no ${!GIT_@}) for bash 3.2 portability.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
        GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
        GIT_INDEX_VERSION GIT_CONFIG_PARAMETERS
}

# Seed the Sigma total cache the renderer reads. $1 = session_id, $2 = integer.
seed_total() {
  mkdir -p "${XDG_CACHE_HOME}/claude-statusline"
  printf '%s\n' "$2" > "${XDG_CACHE_HOME}/claude-statusline/$1.total"
}

# Build a stdin file from a fixture, optionally patched with a jq filter.
# $1 = fixture basename, $2 = jq filter (default '.'). Echoes the file path.
mkstdin() {
  local out="${BATS_TEST_TMPDIR}/stdin.json"
  jq "${2:-.}" "${FIXTURES}/$1" > "$out"
  printf '%s' "$out"
}

# A git repo with one commit on branch "test-branch". Identity is passed per
# command so no global gitconfig is required under the hermetic HOME.
git_repo() {
  local d="$1"
  git init -q -b test-branch "$d"
  echo orig > "$d/tracked.txt"
  git -C "$d" -c user.email=t@t -c user.name=t add tracked.txt
  git -C "$d" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m init
}

# --- composite render ------------------------------------------------------
@test "renders model, context bar+pct, used/max, sigma, duration, separators" {
  seed_total test-session 1200000
  run bash "$SCRIPT" < "$(mkstdin stdin-normal.json)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sonnet 4.6"* ]]          # model
  [[ "$output" == *$'\e[34m'* ]]             # purple model glyph
  [[ "$output" == *"42%"* ]]                 # context percentage
  [[ "$output" == *"["*"]"* ]]               # bracketed bar
  [[ "$output" == *$'\xe2\x96\x88'* ]]       # full-block bar cell
  [[ "$output" == *"(120k/200k)"* ]]         # used/max, human-formatted
  [[ "$output" == *"Σ 1.2M"* ]]              # seeded cumulative total
  [[ "$output" == *"1h30m"* ]]               # duration from total_duration_ms
  [[ "$output" == *"│"* ]]                    # grey segment separator
}

# --- sigma total -----------------------------------------------------------
@test "sigma shows placeholder when the total cache is absent" {
  run bash "$SCRIPT" < "$(mkstdin stdin-normal.json)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Σ ..."* ]]
}

@test "human-number formatting: raw / k / M" {
  seed_total test-session 940
  run bash "$SCRIPT" < "$(mkstdin stdin-normal.json)"
  [[ "$output" == *"Σ 940"* ]]

  seed_total test-session 94500
  run bash "$SCRIPT" < "$(mkstdin stdin-normal.json)"
  [[ "$output" == *"Σ 94.5k"* ]]

  seed_total test-session 1200000
  run bash "$SCRIPT" < "$(mkstdin stdin-normal.json)"
  [[ "$output" == *"Σ 1.2M"* ]]
}

@test "heavy payload: 90%+ context, rate limits, hours duration" {
  run bash "$SCRIPT" < "$(mkstdin stdin-heavy.json)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus 4.8"* ]]
  [[ "$output" == *"95%"* ]]
  [[ "$output" == *"(190k/200k)"* ]]
  [[ "$output" == *$'\e[1;31m'* ]]           # red-bold context bar at 95%
  [[ "$output" == *"5h "* ]]                 # rate segments present
  [[ "$output" == *"wk "* ]]
  [[ "$output" == *"2h30m"* ]]               # duration crosses the hour boundary
}

# --- threshold bar colors --------------------------------------------------
# No-rate fixture + non-git dir, so the only ramped color source is the context bar.
@test "context bar is green below 50%" {
  run bash "$SCRIPT" < "$(mkstdin stdin-no-rate.json \
    "$(printf '.context_window.used_percentage=42 | .workspace.current_dir=%s' "\"$PLAINDIR\"")")"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[32m'* ]]             # green
  [[ "$output" != *$'\e[1;31m'* ]]           # not red-bold
}

@test "context bar is yellow at 50-74%" {
  run bash "$SCRIPT" < "$(mkstdin stdin-no-rate.json \
    "$(printf '.context_window.used_percentage=60 | .workspace.current_dir=%s' "\"$PLAINDIR\"")")"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[33m'* ]]             # yellow
  [[ "$output" != *$'\e[32m'* ]]             # not green
}

@test "context bar is orange truecolor at 75-89%" {
  run bash "$SCRIPT" < "$(mkstdin stdin-no-rate.json \
    "$(printf '.context_window.used_percentage=80 | .workspace.current_dir=%s' "\"$PLAINDIR\"")")"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[38;2;255;184;108m'* ]]   # gud orange (24-bit)
}

@test "context bar is red-bold at 90%+" {
  run bash "$SCRIPT" < "$(mkstdin stdin-no-rate.json \
    "$(printf '.context_window.used_percentage=95 | .workspace.current_dir=%s' "\"$PLAINDIR\"")")"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[1;31m'* ]]           # red-bold
}

# --- rate segments ---------------------------------------------------------
@test "rate segments hide when rate_limits is absent" {
  run bash "$SCRIPT" < "$(mkstdin stdin-no-rate.json)"
  [ "$status" -eq 0 ]
  [[ "$output" != *"5h"* ]]
  [[ "$output" != *"wk"* ]]
}

@test "rate segments render when rate_limits is present" {
  run bash "$SCRIPT" < "$(mkstdin stdin-normal.json)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"5h "* ]]
  [[ "$output" == *"30%"* ]]                 # five_hour used_percentage
  [[ "$output" == *"wk "* ]]
  [[ "$output" == *"65%"* ]]                 # seven_day used_percentage
}

# --- git segment -----------------------------------------------------------
@test "git segment shows branch in green when clean" {
  local repo="${BATS_TEST_TMPDIR}/clean"
  git_repo "$repo"
  run bash "$SCRIPT" < "$(mkstdin stdin-no-rate.json \
    "$(printf '.workspace.current_dir=%s' "\"$repo\"")")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-branch"* ]]
  [[ "$output" == *$'\e[32m'* ]]             # green branch
  [[ "$output" != *$'\e[31m'* ]]             # no dirty dot
}

@test "git segment shows branch in yellow with a red dot when dirty" {
  local repo="${BATS_TEST_TMPDIR}/dirty"
  git_repo "$repo"
  echo changed > "$repo/tracked.txt"         # modify a tracked file
  run bash "$SCRIPT" < "$(mkstdin stdin-no-rate.json \
    "$(printf '.workspace.current_dir=%s' "\"$repo\"")")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-branch"* ]]
  [[ "$output" == *$'\e[33m'* ]]             # yellow branch
  [[ "$output" == *$'\e[31m'* ]]             # red dirty marker
  [[ "$output" == *"●"* ]]                    # dirty dot glyph
}

# --- adaptive width (COLUMNS) ----------------------------------------------
# Claude Code >= 2.1.153 exports COLUMNS to the statusline command; the renderer
# widens the bars and drops lower-priority segments as width shrinks. COLUMNS is
# delivered via `env` so the script reads it from its environment, exactly as
# Claude Code sets it.
@test "wide tier widens the bars vs the default (MED) layout" {
  seed_total test-session 1200000
  local wide med
  wide=$(env COLUMNS=140 bash "$SCRIPT" < "$(mkstdin stdin-normal.json)" \
    | python3 -c 'import sys;print(sys.stdin.read().count("█"))')
  med=$(env COLUMNS=90 bash "$SCRIPT" < "$(mkstdin stdin-normal.json)" \
    | python3 -c 'import sys;print(sys.stdin.read().count("█"))')
  [ "$wide" -gt "$med" ]
}

@test "narrow tier drops the (used/max) detail but keeps context and total" {
  seed_total test-session 1200000
  run env COLUMNS=60 bash "$SCRIPT" < "$(mkstdin stdin-normal.json)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"42%"* ]]                 # context still present
  [[ "$output" == *"Σ 1.2M"* ]]             # total still present
  [[ "$output" != *"(120k/200k)"* ]]         # used/max detail dropped
}

@test "tiny tier drops rate bars and duration, keeps model/context/total" {
  seed_total test-session 1200000
  # stdin-normal carries rate_limits AND a duration; the tiny tier drops both.
  run env COLUMNS=40 bash "$SCRIPT" < "$(mkstdin stdin-normal.json)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sonnet 4.6"* ]]
  [[ "$output" == *"42%"* ]]
  [[ "$output" == *"Σ 1.2M"* ]]
  [[ "$output" != *"5h"* ]]                  # rate segments dropped
  [[ "$output" != *"wk"* ]]
  [[ "$output" != *"1h30m"* ]]               # duration dropped
}

@test "COLUMNS unset falls back to the MED layout (used/max detail shown)" {
  seed_total test-session 1200000
  run env -u COLUMNS bash "$SCRIPT" < "$(mkstdin stdin-normal.json)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(120k/200k)"* ]]
}
