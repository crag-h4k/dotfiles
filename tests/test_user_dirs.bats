#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2088
# tests/test_user_dirs.bats
# The worktrees and agent-notes directories: chezmoi data keys (worktreesDir,
# agentsDir), their env seeds, the `directories` entry on the AI picker and its
# one-page editor, the shared dotfiles-dir template, the ~/.zshenv exports, and the
# directory-creation script. Everything runs against a disposable HOME and config;
# nothing touches the real home or runs sudo.
#
# The prompts need a terminal, so those tests run the init template through
# tests/ctty_run.py, which supplies (or withholds) a controlling pty on any host,
# with a stub `gum` on PATH that records calls and answers from a script. A typed
# AI menu answer is the persisted aiSelection (promptStringOnce returns it), and
# chezmoi's prompt simulation (-p "<prompt text>=value") stands in for typing the
# two paths without Gum.
# SC2016 and SC2088 are disabled file-wide: literal $HOME, $USER, and ~/ are the
# values under test. SC2030 and SC2031 are the usual Bats noise: `run` sets $output
# and $status in the test's own shell, and the helpers read them back.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
CONFIG_TMPL="${REPO_ROOT}/home/.chezmoi.toml.tmpl"
ZSHENV_TMPL="${REPO_ROOT}/home/dot_zshenv.tmpl"
ENSURE_RUN_TMPL="${REPO_ROOT}/home/.chezmoiscripts/run_after_02-ensure-dirs.sh.tmpl"
ENSURE_DIRS="${REPO_ROOT}/scripts/ensure-dirs.sh"
CTTY="${BATS_TEST_DIRNAME}/ctty_run.py"
# chezmoi's prompt simulation keys on the exact prompt text.
WT_TITLE='Git worktrees directory (one folder per task)'
AG_TITLE='Agent notes directory (plans/specs/drafts/handoffs)'

setup() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # A commit hook exports these; chezmoi init shells out to Git.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
    GIT_INDEX_VERSION GIT_CONFIG_PARAMETERS
  unset DOTFILES_WORKTREES_DIR DOTFILES_AGENTS_DIR DOTFILES_NO_TUI DOTFILES_PACKAGE_UPDATE \
    DOTFILES_ASSUME_YES DOTFILES_PALETTE
  TEST_HOME="${BATS_TEST_TMPDIR}/home"
  CONFIG="${BATS_TEST_TMPDIR}/chezmoi.toml"
  mkdir -p "$TEST_HOME"
  CHEZMOI="$(command -v chezmoi)"
  STUBS="${BATS_TEST_TMPDIR}/stubs"
  TTY_LOG="${BATS_TEST_TMPDIR}/tty.log"
  CTTY_MODE=--stdin-tty
}

# mode_of <path>: octal permission bits on both GNU and BSD stat.
mode_of() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

# seed_config [extra TOML lines...]: componentSelection is pre-seeded so the
# component prompt returns it instead of opening a TTY.
seed_config() {
  {
    printf '[data]\n    componentSelection = "1 2 3"\n'
    printf '%s\n' "$@"
  } > "$CONFIG"
}

# render_init [VAR=value...]: render the init template the way `chezmoi init` does.
render_init() {
  run env HOME="$TEST_HOME" DOTFILES_NO_TUI=1 DOTFILES_INSTALL_MODE=configs "$@" \
    chezmoi execute-template --init --source "$REPO_ROOT" --config "$CONFIG" < "$CONFIG_TMPL"
}

# render_tmpl <template> [VAR=value...]: render an apply-time template against $CONFIG.
render_tmpl() {
  local tmpl="$1"
  shift
  run env HOME="$TEST_HOME" "$@" \
    chezmoi execute-template --source "$REPO_ROOT" --config "$CONFIG" < "$tmpl"
}

@test "dirs: unset keys and env persist the symbolic defaults" {
  seed_config
  render_init
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "$HOME/worktrees"'* ]]
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]
}

@test "dirs: env seeds the first init" {
  seed_config
  render_init DOTFILES_WORKTREES_DIR=/opt/worktrees DOTFILES_AGENTS_DIR='~/notes/agents'
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "/opt/worktrees"'* ]]
  [[ "$output" == *'agentsDir = "~/notes/agents"'* ]]
}

@test "dirs: a configured value beats the env seed on re-init" {
  seed_config 'worktreesDir = "~/src/worktrees"' 'agentsDir = "/srv/agents"'
  render_init DOTFILES_WORKTREES_DIR=/opt/worktrees DOTFILES_AGENTS_DIR=/tmp/other
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "~/src/worktrees"'* ]]
  [[ "$output" == *'agentsDir = "/srv/agents"'* ]]
}

@test "dirs: an old config with one key seeds only the missing one" {
  seed_config 'worktreesDir = "/opt/worktrees"'
  render_init DOTFILES_WORKTREES_DIR=/tmp/other DOTFILES_AGENTS_DIR=/srv/agents
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "/opt/worktrees"'* ]]
  [[ "$output" == *'agentsDir = "/srv/agents"'* ]]
}

@test "dirs: values resolve the same with no TUI, no gum, and no tty" {
  seed_config
  run env HOME="$TEST_HOME" PATH="/usr/bin:/bin" DOTFILES_INSTALL_MODE=configs \
    DOTFILES_WORKTREES_DIR=/opt/worktrees \
    "$(command -v chezmoi)" execute-template --init --source "$REPO_ROOT" \
    --config "$CONFIG" < "$CONFIG_TMPL"
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "/opt/worktrees"'* ]]
}

@test "dirs: a real chezmoi init persists the seed and then keeps it" {
  local persisted="$TEST_HOME/.config/chezmoi/chezmoi.toml"
  mkdir -p "$(dirname "$persisted")"
  printf '[data]\n    componentSelection = "1 2 3"\n' > "$persisted"
  run env HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_STATE_HOME="$TEST_HOME/.local/state" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" DOTFILES_NO_TUI=1 DOTFILES_INSTALL_MODE=configs \
    DOTFILES_WORKTREES_DIR=/opt/worktrees DOTFILES_AGENTS_DIR=/srv/agents \
    chezmoi init --no-tty --source "$REPO_ROOT"
  [ "$status" -eq 0 ]
  grep -Fq 'worktreesDir = "/opt/worktrees"' "$persisted"
  grep -Fq 'agentsDir = "/srv/agents"' "$persisted"

  run env HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_STATE_HOME="$TEST_HOME/.local/state" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" DOTFILES_NO_TUI=1 DOTFILES_INSTALL_MODE=configs \
    DOTFILES_WORKTREES_DIR=/tmp/other DOTFILES_AGENTS_DIR=/tmp/other \
    chezmoi init --no-tty --source "$REPO_ROOT"
  [ "$status" -eq 0 ]
  grep -Fq 'worktreesDir = "/opt/worktrees"' "$persisted"
  grep -Fq 'agentsDir = "/srv/agents"' "$persisted"
}

@test "dirs: relative, root, and shell-unsafe values fail loudly at init" {
  seed_config 'worktreesDir = "worktrees"'
  render_init
  [ "$status" -ne 0 ]
  [[ "$output" == *"data.worktreesDir must be an absolute path"* ]]

  seed_config 'agentsDir = "/"'
  render_init
  [ "$status" -ne 0 ]
  [[ "$output" == *"data.agentsDir must not be the filesystem root"* ]]

  seed_config 'agentsDir = "/tmp/a$(id)"'
  render_init
  [ "$status" -ne 0 ]
  [[ "$output" == *"data.agentsDir must name a directory using only"* ]]

  seed_config
  render_init DOTFILES_WORKTREES_DIR="/tmp/it's"
  [ "$status" -ne 0 ]
}

# --- the `directories` entry of the AI page and its editor ---------------------

# write_gum_stub: a gum stand-in. It records every call in $STUBS/calls (newlines
# inside an argument show as a literal \n), saves what each call was given in
# $STUBS/{header,selected,value}.<sub>.<n>, and answers like a user:
#   choose  accepts the preselected options, or, when GUM_STUB_TOP / GUM_STUB_AI name
#           prefixes, the options whose text starts with one of them
#   write   prints $STUBS/write.<n> verbatim; "@value" presses Enter on the text it
#           was given; a missing file is Esc (no output, non-zero exit)
#   input   exists only to prove it is never called: it records itself and exits 1
write_gum_stub() {
  mkdir -p "$STUBS"
  cat > "$STUBS/gum" <<'STUB'
#!/bin/sh
dir=${GUM_STUB_DIR:?GUM_STUB_DIR is required}
sub=$1
shift
n=$(($(cat "$dir/n.$sub" 2>/dev/null || echo 0) + 1))
printf '%s' "$n" >"$dir/n.$sub"
{
  printf '%s #%s:' "$sub" "$n"
  for arg in "$@"; do
    printf ' [%s]' "$(printf '%s' "$arg" | awk 'NR>1{printf "\\n"} {printf "%s",$0}')"
  done
  printf '\n'
} >>"$dir/calls"
selected=""
header=""
value=""
options=""
while [ $# -gt 0 ]; do
  case $1 in
    --selected=*) selected=${1#--selected=} ;;
    --header) shift; header=$1 ;;
    --value) shift; value=$1 ;;
    --placeholder | --width | --prompt | --char-limit | --height) shift ;;
    --no-limit) ;;
    *) options="$options$1
" ;;
  esac
  shift
done
printf '%s' "$header" >"$dir/header.$sub.$n"
printf '%s' "$selected" >"$dir/selected.$sub.$n"
printf '%s' "$value" >"$dir/value.$sub.$n"
case $sub in
  choose)
    case $header in
      Components*) picks=${GUM_STUB_TOP-} ;;
      "AI tools"*) picks=${GUM_STUB_AI-} ;;
      *) picks="" ;;
    esac
    if [ -n "$picks" ]; then
      for pick in $picks; do
        printf '%s' "$options" | while IFS= read -r line; do
          case $line in "$pick"*) printf '%s\n' "$line" ;; esac
        done
      done
    elif [ -n "$selected" ]; then
      printf '%s\n' "$selected" | tr ',' '\n'
    fi
    ;;
  write)
    [ -e "$dir/write.$n" ] || exit 1
    if [ "$(cat "$dir/write.$n")" = "@value" ]; then printf '%s\n' "$value"; else cat "$dir/write.$n"; fi
    ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$STUBS/gum"
}

# need_pty: the prompt tests drive a pty from Python.
need_pty() {
  command -v python3 >/dev/null 2>&1 || skip "python3 not available for the pty harness"
  write_gum_stub
}

# seed_ai_config [extra [data] lines...]: an existing host with AI selected and no
# directory keys unless a line adds them, like a config written before the prompt.
seed_ai_config() {
  {
    printf '[data]\n    componentSelection = "5"\n    aiSelection = "opencode"\n'
    printf '    %s\n' "$@"
    printf '[data.components.ai]\n    opencode = true\n'
  } > "$CONFIG"
}

# set_write <n> <text>: what the stub answers to the nth `gum write`. An empty text
# is an empty answer. Never calling this for a call number is Esc.
set_write() {
  printf '%s\n' "$2" > "$STUBS/write.$1"
}

# reset_stub: forget recorded calls and answers, keep the stub itself.
reset_stub() {
  rm -f "$STUBS/calls" "$STUBS"/n.* "$STUBS"/write.* "$STUBS"/header.* "$STUBS"/selected.* "$STUBS"/value.*
}

# render_tty [VAR=value...] [-- extra chezmoi args]: render the init template under
# the terminal situation in $CTTY_MODE (default: controlling pty plus tty stdin),
# with the stub gum first on PATH. Prompt text the terminal received lands in
# $TTY_LOG. stdin is /dev/null unless ctty_run replaces it with the pty.
render_tty() {
  local envs=() args=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  if [ $# -gt 0 ]; then shift; fi
  args=("$@")
  run env HOME="$TEST_HOME" PATH="$STUBS:/usr/bin:/bin" DOTFILES_INSTALL_MODE=configs \
    GUM_STUB_DIR="$STUBS" CTTY_LOG="$TTY_LOG" ${envs[@]+"${envs[@]}"} \
    python3 "$CTTY" "$CTTY_MODE" "$CHEZMOI" execute-template --init --file \
    -p "$WT_TITLE=" -p "$AG_TITLE=" \
    --source "$REPO_ROOT" --config "$CONFIG" ${args[@]+"${args[@]}"} "$CONFIG_TMPL" </dev/null
}

render_typed() {
  local typed_path="$BATS_TEST_TMPDIR/no-gum"
  mkdir -p "$typed_path"
  ln -sf /bin/sh "$typed_path/sh"
  ln -sf "$(command -v python3)" "$typed_path/python3"
  render_tty PATH="$typed_path" "$@"
}

# gum_calls <subcommand>: the recorded calls of that subcommand.
gum_calls() {
  grep -F "$1 #" "$STUBS/calls" 2>/dev/null || true
}

# gum_count <subcommand>: how many times it ran.
gum_count() {
  gum_calls "$1" | wc -l | tr -d ' '
}

# no_gum_calls: the stub was never run.
no_gum_calls() {
  [ ! -e "$STUBS/calls" ]
}

# stored: the directory lines of the rendered config, for exact comparison.
stored() {
  printf '%s\n' "$output" | grep -E '^    (worktreesDir|agentsDir) = '
}

AI_HDR='AI tools  (space toggles, enter confirms, esc cancels):'

@test "dirs page: unchecked asks nothing and keeps the default on a first init" {
  need_pty
  printf '[data]\n' > "$CONFIG"
  render_tty GUM_STUB_TOP='5)'
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "$HOME/worktrees"'* ]]
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]
  # The top picker and the AI page, nothing else.
  [ "$(gum_count choose)" = 2 ]
  [ "$(gum_count write)" = 0 ]
  [ "$(gum_calls choose | sed -n 2p | cut -d' ' -f1-2)" = "choose #2:" ]
  [ "$(wc -l < "$STUBS/calls" | tr -d ' ')" = 2 ]
}

@test "dirs page: unchecked keeps the saved value and the env seed on a re-init" {
  need_pty
  seed_ai_config 'worktreesDir = "~/src/worktrees"' 'agentsDir = "/srv/agents"'
  render_tty DOTFILES_WORKTREES_DIR=/opt/seeded DOTFILES_AGENTS_DIR=/opt/seeded
  [ "$status" -eq 0 ]
  [ "$(stored)" = $'    worktreesDir = "~/src/worktrees"\n    agentsDir = "/srv/agents"' ]
  [ "$(gum_count write)" = 0 ]

  # A host with no saved value takes the env seed, still without being asked.
  reset_stub
  seed_ai_config
  render_tty DOTFILES_WORKTREES_DIR=/opt/seeded-wt DOTFILES_AGENTS_DIR='~/seeded/agents'
  [ "$status" -eq 0 ]
  [ "$(stored)" = $'    worktreesDir = "/opt/seeded-wt"\n    agentsDir = "~/seeded/agents"' ]
  [ "$(gum_count write)" = 0 ]
}

@test "dirs page: the entry is a checkbox that starts unchecked, in the AI page only" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/saved-wt"'
  render_tty
  [ "$status" -eq 0 ]
  # The AI page lists the entry last, and never preselects it, on a re-init
  # (opencode is on) and on a first init alike.
  gum_calls choose | sed -n 2p | grep -Fq '[directories - change the worktrees and agent-notes directories (unchecked keeps them)]'
  [[ "$(cat "$STUBS/selected.choose.2")" == *opencode* ]]
  [[ "$(cat "$STUBS/selected.choose.2")" != *directories* ]]
  # It is no component: not on the top page, not in the Git page.
  [[ "$(gum_calls choose | sed -n 1p)" != *directories* ]]

  reset_stub
  printf '[data]\n' > "$CONFIG"
  render_tty GUM_STUB_TOP='5)'
  [ "$status" -eq 0 ]
  [[ "$(cat "$STUBS/selected.choose.2")" != *directories* ]]
}

@test "dirs page: the header shows the current paths on their own lines" {
  need_pty
  seed_ai_config 'worktreesDir = "~/src/worktrees"'
  render_tty DOTFILES_AGENTS_DIR=/opt/seeded-agents
  [ "$status" -eq 0 ]
  [ "$(cat "$STUBS/header.choose.2")" = "$AI_HDR"$'\nWorktrees:   ~/src/worktrees\nAgent notes: /opt/seeded-agents' ]

  # A first init shows the defaults.
  reset_stub
  printf '[data]\n' > "$CONFIG"
  render_tty GUM_STUB_TOP='5)'
  [ "$(cat "$STUBS/header.choose.2")" = "$AI_HDR"$'\nWorktrees:   $HOME/worktrees\nAgent notes: $HOME/agents' ]
}

@test "dirs page: an unusable or hostile saved value is masked and marked, never run" {
  need_pty
  seed_ai_config "agentsDir = \"/tmp/x'; touch $TEST_HOME/pwned; echo '\"" 'worktreesDir = "relative"'
  render_tty
  [ "$status" -ne 0 ]
  [ ! -e "$TEST_HOME/pwned" ]
  header=$(cat "$STUBS/header.choose.2")
  [[ "$header" == *$'\nWorktrees:   relative (not usable)\n'* ]]
  [[ "$header" == *"Agent notes: /tmp/x?? touch $TEST_HOME/pwned? echo ? (not usable)"* ]]
  # Escape sequences and newlines cannot reach the terminal through the page.
  reset_stub
  seed_ai_config "agentsDir = \"/tmp/\\u001b[31mred\\u001b[0m\""
  render_tty
  header=$(cat "$STUBS/header.choose.2")
  [[ "$header" != *$'\033'* ]]
  [[ "$header" == *'Agent notes: /tmp/??31mred??0m (not usable)'* ]]
}

@test "dirs editor: checked opens exactly one page with both paths, in order after the AI page" {
  need_pty
  printf '[data]\n' > "$CONFIG"
  set_write 1 @value
  render_tty GUM_STUB_TOP='5)' GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  [ "$(stored)" = $'    worktreesDir = "$HOME/worktrees"\n    agentsDir = "$HOME/agents"' ]
  [ "$(gum_count choose)" = 2 ]
  [ "$(gum_count write)" = 1 ]
  [ "$(sed -n 3p "$STUBS/calls" | cut -d' ' -f1-2)" = "write #1:" ]
  [ "$(wc -l < "$STUBS/calls" | tr -d ' ')" = 3 ]
  [ "$(cat "$STUBS/value.write.1")" = $'worktrees: $HOME/worktrees\nagents: $HOME/agents' ]
  # Flags that behave the same in Gum 0.14 and 2.x: an explicit width (a fresh pty reports
  # none, so the 80-column fallback less the prompt) and no 400-character cap.
  gum_calls write | grep -Fq '[--width] [78]'
  gum_calls write | grep -Fq '[--char-limit] [0]'
  # The AI page gets room for its options plus a 3-line header, for Gum 0.14: 8 options,
  # or 9 on macOS, where the voice option is offered.
  if [ "$(uname -s)" = Darwin ]; then
    gum_calls choose | sed -n 2p | grep -Fq '[--height] [14]'
  else
    gum_calls choose | sed -n 2p | grep -Fq '[--height] [13]'
  fi
  # The page says how to submit and cancel, in the oldest and newest Gum alike.
  [[ "$(cat "$STUBS/header.write.1")" == *'Enter saves'* ]]
  [[ "$(cat "$STUBS/header.write.1")" == *'Ctrl+C'* ]]
  # The checkbox is the only way in: it never reaches the saved selection or the tables.
  [[ "$output" == *'aiSelection = "opencode"'* ]]
  [[ "$output" != *'directories'* ]]
}

@test "dirs editor: a later submenu does not open it again" {
  need_pty
  printf '[data]\n' > "$CONFIG"
  set_write 1 @value
  set_write 2 @value
  render_tty GUM_STUB_TOP='5) 6)' GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  # Top page, AI page, the editor, then the terminal page: one editor in all.
  [ "$(gum_count choose)" = 3 ]
  [ "$(gum_count write)" = 1 ]
  [ "$(awk -F'[ #:]' '{print $1}' "$STUBS/calls" | tr '\n' ' ')" = "choose choose write choose " ]
}

@test "dirs editor: the pre-fill is the default, then the saved value, with the env seed between" {
  need_pty
  # First init, no seed: the default.
  printf '[data]\n' > "$CONFIG"
  set_write 1 @value
  render_tty GUM_STUB_TOP='5)' GUM_STUB_AI='opencode directories'
  [ "$(cat "$STUBS/value.write.1")" = $'worktrees: $HOME/worktrees\nagents: $HOME/agents' ]

  # No saved value, env seeds: the seeds.
  reset_stub
  set_write 1 @value
  render_tty GUM_STUB_TOP='5)' GUM_STUB_AI='opencode directories' \
    DOTFILES_WORKTREES_DIR=/opt/seeded-wt DOTFILES_AGENTS_DIR='~/seeded/agents'
  [ "$(cat "$STUBS/value.write.1")" = $'worktrees: /opt/seeded-wt\nagents: ~/seeded/agents' ]
  [ "$(stored)" = $'    worktreesDir = "/opt/seeded-wt"\n    agentsDir = "~/seeded/agents"' ]

  # Saved values win over seeds, one key at a time.
  reset_stub
  seed_ai_config 'worktreesDir = "~/src/worktrees"'
  set_write 1 @value
  render_tty GUM_STUB_AI='opencode directories' DOTFILES_WORKTREES_DIR=/opt/seeded-wt DOTFILES_AGENTS_DIR=/opt/seeded-agents
  [ "$status" -eq 0 ]
  [ "$(cat "$STUBS/value.write.1")" = $'worktrees: ~/src/worktrees\nagents: /opt/seeded-agents' ]
  [ "$(stored)" = $'    worktreesDir = "~/src/worktrees"\n    agentsDir = "/opt/seeded-agents"' ]
}

@test "dirs editor: both values can be edited and are stored as typed" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/old-wt"'
  set_write 1 $'worktrees: /opt/typed-wt/\nagents: ~/typed/agents'
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  [ "$(stored)" = $'    worktreesDir = "/opt/typed-wt/"\n    agentsDir = "~/typed/agents"' ]
  [ "$(gum_count write)" = 1 ]
}

@test "dirs editor: one edited value leaves the other at its pre-fill" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/old-wt"' 'agentsDir = "/srv/old-agents"'
  set_write 1 $'worktrees: /srv/old-wt\nagents: /opt/new-agents'
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  [ "$(stored)" = $'    worktreesDir = "/srv/old-wt"\n    agentsDir = "/opt/new-agents"' ]

  # A deleted line, or a key left empty, keeps that pre-fill too.
  reset_stub
  set_write 1 'worktrees: /opt/only-wt'
  render_tty GUM_STUB_AI='opencode directories'
  [ "$(stored)" = $'    worktreesDir = "/opt/only-wt"\n    agentsDir = "/srv/old-agents"' ]
  reset_stub
  set_write 1 $'worktrees:\nagents: /opt/only-agents'
  render_tty GUM_STUB_AI='opencode directories'
  [ "$(stored)" = $'    worktreesDir = "/srv/old-wt"\n    agentsDir = "/opt/only-agents"' ]
}

@test "dirs editor: the answer is parsed tolerantly" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/old-wt"' 'agentsDir = "/srv/old-agents"'
  set_write 1 $'\n  WORKTREES :   /opt/loose wt  \n\n\tAgents=~/loose/agents\n\n'
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  [ "$(stored)" = $'    worktreesDir = "/opt/loose wt"\n    agentsDir = "~/loose/agents"' ]
  [ "$(gum_count write)" = 1 ]
}

@test "dirs editor: a bad value reopens the editor with the text kept and says why" {
  need_pty
  seed_ai_config
  set_write 1 $'worktrees: relative/path\nagents: /srv/kept-agents'
  set_write 2 $'worktrees: /srv/good-wt\nagents: /srv/kept-agents'
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  [ "$(stored)" = $'    worktreesDir = "/srv/good-wt"\n    agentsDir = "/srv/kept-agents"' ]
  [ "$(gum_count write)" = 2 ]
  # The second page opens on the user's own text, not on the pre-fill.
  [ "$(cat "$STUBS/value.write.2")" = $'worktrees: relative/path\nagents: /srv/kept-agents' ]
  grep -Fq 'Not a usable directory for worktrees' "$TTY_LOG"
}

@test "dirs editor: a line it cannot read reopens the editor too" {
  need_pty
  seed_ai_config
  set_write 1 $'/opt/forgot-the-key\nagents: /srv/a'
  set_write 2 $'worktrees: /opt/fixed\nagents: /srv/a'
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  [ "$(gum_count write)" = 2 ]
  [ "$(cat "$STUBS/value.write.2")" = $'/opt/forgot-the-key\nagents: /srv/a' ]
  [ "$(stored)" = $'    worktreesDir = "/opt/fixed"\n    agentsDir = "/srv/a"' ]
  grep -Fq "Each line must look like 'worktrees: <path>'" "$TTY_LOG"
}

@test "dirs editor: a value that parses but is unsafe to show is refused" {
  need_pty
  seed_ai_config
  # Cleaning the path would drop the quote with its ".." segment, so the usable-path check
  # alone passes; the raw text still could not be shown or re-edited safely.
  set_write 1 "worktrees: /tmp/a'b\$(id)/../ok"
  set_write 2 'worktrees: /srv/good'
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  [ "$(gum_count write)" = 2 ]
  [ "$(cat "$STUBS/value.write.2")" = "worktrees: /tmp/a'b\$(id)/../ok" ]
  [ "$(stored)" = $'    worktreesDir = "/srv/good"\n    agentsDir = "$HOME/agents"' ]
}

@test "dirs editor: three bad answers fail with the existing clear error" {
  need_pty
  seed_ai_config
  set_write 1 'worktrees: relative/path'
  set_write 2 'worktrees: relative/path'
  set_write 3 'worktrees: relative/path'
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -ne 0 ]
  [[ "$output" == *"data.worktreesDir must be an absolute path"* ]]
  [ "$(gum_count write)" = 3 ]

  # Unreadable three times is a clear failure as well, not a silent keep.
  reset_stub
  set_write 1 'no keys here'
  set_write 2 'no keys here'
  set_write 3 'no keys here'
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not use the directories answer after three tries"* ]]
  [ "$(gum_count write)" = 3 ]
}

@test "dirs editor: an empty answer and Escape keep the pre-fill without asking again" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/kept-wt"'
  set_write 1 ''
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  [ "$(stored)" = $'    worktreesDir = "/srv/kept-wt"\n    agentsDir = "$HOME/agents"' ]
  [ "$(gum_count write)" = 1 ]

  # Escape or Ctrl+C: Gum prints nothing and exits non-zero.
  reset_stub
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  [ "$(stored)" = $'    worktreesDir = "/srv/kept-wt"\n    agentsDir = "$HOME/agents"' ]
  [ "$(gum_count write)" = 1 ]
}

@test "dirs editor: an unusable saved value is replaced by the default, never run by the shell" {
  need_pty
  # A quote in a saved value would end a single-quoted word in a spliced command; the
  # value travels as a parameter, is replaced by the default, and the user is told.
  seed_ai_config "agentsDir = \"/tmp/x'; touch $TEST_HOME/pwned; echo '\""
  set_write 1 @value
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_HOME/pwned" ]
  [ "$(cat "$STUBS/value.write.1")" = $'worktrees: $HOME/worktrees\nagents: $HOME/agents' ]
  [ "$(stored)" = $'    worktreesDir = "$HOME/worktrees"\n    agentsDir = "$HOME/agents"' ]
  grep -Fq 'agentsDir value is not usable' "$TTY_LOG"
}

@test "dirs editor: a path the user types with quotes in the text reaches the page intact" {
  need_pty
  seed_ai_config
  # The kept text goes back to the editor through a parameter: quotes, $(), and backticks
  # in a refused answer must not be interpreted by sh.
  set_write 1 $'worktrees: /tmp/a\'b$(touch '"$TEST_HOME"$'/pwned)`id`\nagents: /srv/a'
  set_write 2 'worktrees: /srv/ok'
  render_tty GUM_STUB_AI='opencode directories'
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_HOME/pwned" ]
  [ "$(cat "$STUBS/value.write.2")" = $'worktrees: /tmp/a\'b$(touch '"$TEST_HOME"$'/pwned)`id`\nagents: /srv/a' ]
}

# --- typed fallback ------------------------------------------------------------

@test "dirs typed: a selected entry asks each path with promptString, pre-filled" {
  need_pty
  # The typed AI menu answer is the persisted aiSelection (promptStringOnce); chezmoi's
  # prompt simulation stands in for typing the two paths.
  seed_ai_config 'worktreesDir = "/srv/saved-wt"'
  sed -i.bak 's/aiSelection = "opencode"/aiSelection = "opencode directories"/' "$CONFIG"
  render_typed
  [ "$status" -eq 0 ]
  no_gum_calls
  # No typed answer: Enter keeps the pre-fill (saved, then default).
  [ "$(stored)" = $'    worktreesDir = "/srv/saved-wt"\n    agentsDir = "$HOME/agents"' ]

  render_typed -- -p "$WT_TITLE=/opt/typed-wt" -p "$AG_TITLE=~/typed/agents"
  [ "$status" -eq 0 ]
  [ "$(stored)" = $'    worktreesDir = "/opt/typed-wt"\n    agentsDir = "~/typed/agents"' ]
  # The choice never lands in the saved selection or the tables.
  [[ "$output" == *'aiSelection = "opencode"'* ]]
  [[ "$output" != *'directories'* ]]
}

@test "dirs typed: the number selects the entry, and an unselected entry asks nothing" {
  need_pty
  seed_ai_config
  sed -i.bak 's/aiSelection = "opencode"/aiSelection = "4 10"/' "$CONFIG"
  render_typed -- -p "$WT_TITLE=/opt/by-number"
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "/opt/by-number"'* ]]
  [[ "$output" == *'opencode = true'* ]]

  seed_ai_config
  render_typed -- -p "$WT_TITLE=/opt/ignored" -p "$AG_TITLE=/opt/ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "$HOME/worktrees"'* ]]
}

@test "dirs typed: a bad typed answer is asked again and then fails clearly" {
  need_pty
  seed_ai_config
  sed -i.bak 's/aiSelection = "opencode"/aiSelection = "opencode directories"/' "$CONFIG"
  render_typed -- -p "$WT_TITLE=/tmp/it's"
  [ "$status" -ne 0 ]
  [[ "$output" == *"data.worktreesDir must name a directory using only"* ]]
}

# --- existing AI selections are untouched -------------------------------------

@test "dirs regression: every AI sub-feature still resolves from its key and its number" {
  need_pty
  local expect='    claude_hooks = true
    codex_hooks = true
    statusline = true
    opencode = true
    voice = true
    copilot = true
    openviking = true
    codecompanion = true'
  seed_ai_config
  render_tty GUM_STUB_AI='claude_hooks codex_hooks statusline opencode voice copilot openviking codecompanion directories'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$expect"* ]]
  [[ "$output" == *'aiSelection = "claude_hooks codex_hooks statusline opencode voice copilot openviking codecompanion"'* ]]

  # Persisted numbers: 1..6, 8, and 11 are the sub-features, 7 and 9 are retired tokens that
  # migrate to opencode, and 10 is the entry, never a feature.
  seed_ai_config
  sed -i.bak 's/aiSelection = "opencode"/aiSelection = "1 2 3 4 11 5 8 6"/' "$CONFIG"
  render_typed
  [ "$status" -eq 0 ]
  [[ "$output" == *"$expect"* ]]

  seed_ai_config
  sed -i.bak 's/aiSelection = "opencode"/aiSelection = "7"/' "$CONFIG"
  render_typed
  [[ "$output" == *'opencode = true'* ]]
  [[ "$output" == *'copilot = false'* ]]
  sed -i.bak 's/aiSelection = "7"/aiSelection = "9"/' "$CONFIG"
  render_typed
  [[ "$output" == *'opencode = true'* ]]

  sed -i.bak 's/aiSelection = "9"/aiSelection = "10"/' "$CONFIG"
  render_typed
  [ "$status" -eq 0 ]
  [[ "$output" == *'claude_hooks = false'* ]]
  [[ "$output" == *'opencode = false'* ]]
  [[ "$output" == *'aiSelection = ""'* ]]
}

@test "dirs regression: the AI page keeps its order, and the entry comes last" {
  need_pty
  seed_ai_config
  render_tty
  [ "$status" -eq 0 ]
  local keys
  keys=$(gum_calls choose | sed -n 2p | grep -o '\[[a-z_]* - ' | sed -E 's/^\[([a-z_]*) - $/\1/' | tr '\n' ' ')
  # voice is offered only where its helper builds, so only on macOS.
  if [ "$(uname -s)" = Darwin ]; then
    [ "$keys" = "claude_hooks codex_hooks statusline opencode voice copilot openviking codecompanion directories " ]
  else
    [ "$keys" = "claude_hooks codex_hooks statusline opencode copilot openviking codecompanion directories " ]
  fi
}

@test "voice: selecting it by key or number also selects OpenCode and nothing else" {
  need_pty
  local selection
  for selection in voice 11; do
    seed_ai_config
    sed -i.bak "s/aiSelection = \"opencode\"/aiSelection = \"$selection\"/" "$CONFIG"
    render_typed
    [ "$status" -eq 0 ]
    [[ "$output" == *'    opencode = true'* ]]
    [[ "$output" == *'    voice = true'* ]]
    [[ "$output" == *'    claude_hooks = false'* ]]
    [[ "$output" == *'    copilot = false'* ]]
    [[ "$output" == *'aiSelection = "opencode voice"'* ]]
  done
  # OpenCode alone leaves voice off, which is the default.
  seed_ai_config
  render_typed
  [[ "$output" == *'    voice = false'* ]]
}

# --- gates: nothing is offered or asked ---------------------------------------
# Every case persists an aiSelection that already names the entry, so a leaked gate
# would open the editor or a prompt; the simulated typed answers would win if it did.

# seed_ai_with_entry: AI selected, entry chosen, saved worktrees value.
seed_ai_with_entry() {
  seed_ai_config 'worktreesDir = "/srv/saved-wt"'
  sed -i.bak 's/aiSelection = "opencode"/aiSelection = "opencode directories"/' "$CONFIG"
}

# gated_result: nothing was asked, the saved value and the default stand, the entry is not
# stored, and the typed answers that would have won were never used.
gated_result() {
  [ "$status" -eq 0 ]
  [ "$(gum_count write)" = 0 ]
  [[ "$output" == *'worktreesDir = "/srv/saved-wt"'* ]]
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]
  [[ "$output" == *'aiSelection = "opencode"'* ]]
  [[ "$output" != *'directories'* ]]
}

@test "dirs gate: no controlling terminal keeps the pre-fill and never opens anything" {
  need_pty
  seed_ai_with_entry
  set_write 1 'worktrees: /opt/never-used'
  CTTY_MODE=--none
  render_tty -- -p "$WT_TITLE=/opt/ignored" -p "$AG_TITLE=/opt/ignored"
  gated_result
}

@test "dirs gate: a tty stdin without a controlling terminal never prompts" {
  need_pty
  # chezmoi's own promptString fails here (no /dev/tty), so the template must not reach it.
  seed_ai_with_entry
  CTTY_MODE=--stdin-only
  render_typed -- -p "$WT_TITLE=/opt/ignored" -p "$AG_TITLE=/opt/ignored"
  gated_result
}

@test "dirs gate: a terminal without a tty stdin hides the entry and the paths" {
  need_pty
  seed_ai_with_entry
  set_write 1 'worktrees: /opt/never-used'
  CTTY_MODE=--ctty
  render_tty GUM_STUB_AI='opencode directories' -- -p "$WT_TITLE=/opt/ignored"
  gated_result
  # The AI page itself is still shown (Gum opens /dev/tty), without the entry or paths.
  [ "$(gum_count choose)" = 2 ]
  [ "$(cat "$STUBS/header.choose.2")" = "$AI_HDR" ]
  [[ "$(gum_calls choose | sed -n 2p)" != *directories* ]]
  [[ "$(gum_calls choose | sed -n 2p)" != *'--height'* ]]
}

@test "dirs gate: DOTFILES_NO_TUI skips everything" {
  need_pty
  seed_ai_with_entry
  set_write 1 'worktrees: /opt/never-used'
  render_tty DOTFILES_NO_TUI=1 -- -p "$WT_TITLE=/opt/ignored" -p "$AG_TITLE=/opt/ignored"
  gated_result
  no_gum_calls
}

@test "dirs gate: a host without AI selected is never asked and keeps its values" {
  need_pty
  printf '[data]\n    componentSelection = "1 2 3"\n    aiSelection = "opencode directories"\n    worktreesDir = "/srv/saved-wt"\n    agentsDir = "/srv/saved-agents"\n' > "$CONFIG"
  set_write 1 'worktrees: /opt/never-used'
  render_tty DOTFILES_WORKTREES_DIR=/opt/seeded -- -p "$WT_TITLE=/opt/ignored"
  [ "$status" -eq 0 ]
  [ "$(gum_count write)" = 0 ]
  # The top picker only: no AI page.
  [ "$(gum_count choose)" = 1 ]
  [ "$(stored)" = $'    worktreesDir = "/srv/saved-wt"\n    agentsDir = "/srv/saved-agents"' ]
}

@test "dirs gate: a package update re-init (cup) does not reopen anything" {
  need_pty
  seed_ai_with_entry
  set_write 1 'worktrees: /opt/never-used'
  render_tty DOTFILES_PACKAGE_UPDATE=1 -- -p "$WT_TITLE=/opt/ignored" -p "$AG_TITLE=/opt/ignored"
  gated_result
  no_gum_calls
}

@test "dirs gate: the retired all+ migration does not reopen anything" {
  need_pty
  seed_ai_with_entry
  sed -i.bak 's/componentSelection = "5"/componentSelection = "all+"/' "$CONFIG"
  set_write 1 'worktrees: /opt/never-used'
  # all+ only reaches the template through the typed menu (a Gum top page would replace it).
  render_typed -- -p "$WT_TITLE=/opt/ignored" -p "$AG_TITLE=/opt/ignored"
  [ "$status" -eq 0 ]
  no_gum_calls
  [[ "$output" == *'worktreesDir = "/srv/saved-wt"'* ]]
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]
  [[ "$output" != *'directories'* ]]
}

@test "dirs gate: chezmoi apply never prompts, even with Gum and a terminal" {
  need_pty
  printf '[data]\nworktreesDir = "/opt/worktrees"\n[data.components]\nzsh = true\n[data.components.ai]\nopencode = true\n' > "$CONFIG"
  set_write 1 'worktrees: /opt/never-used'
  run env HOME="$TEST_HOME" PATH="$STUBS:/usr/bin:/bin" GUM_STUB_DIR="$STUBS" CTTY_LOG="$TTY_LOG" \
    python3 "$CTTY" --stdin-tty "$CHEZMOI" apply --source "$REPO_ROOT" --config "$CONFIG" \
    --destination "$TEST_HOME" --exclude=scripts,externals --refresh-externals=never \
    "$TEST_HOME/.zshenv"
  [ "$status" -eq 0 ]
  no_gum_calls
  grep -Fxq "export DOTFILES_WORKTREES_DIR='/opt/worktrees'" "$TEST_HOME/.zshenv"
}

@test "dirs: a real chezmoi init stores an edited answer and pre-fills it next time" {
  need_pty
  local persisted="$TEST_HOME/.config/chezmoi/chezmoi.toml"
  mkdir -p "$(dirname "$persisted")"
  printf '[data]\n    componentSelection = "5"\n    aiSelection = "opencode"\n[data.components.ai]\n    opencode = true\n' > "$persisted"
  set_write 1 $'worktrees: /opt/typed-wt\nagents: ~/typed/agents'
  run env HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_STATE_HOME="$TEST_HOME/.local/state" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" PATH="$STUBS:/usr/bin:/bin" GUM_STUB_DIR="$STUBS" \
    GUM_STUB_AI='opencode directories' CTTY_LOG="$TTY_LOG" DOTFILES_INSTALL_MODE=configs \
    python3 "$CTTY" --stdin-tty "$CHEZMOI" init --source "$REPO_ROOT"
  [ "$status" -eq 0 ]
  grep -Fq 'worktreesDir = "/opt/typed-wt"' "$persisted"
  grep -Fq 'agentsDir = "~/typed/agents"' "$persisted"
  run grep -Fq 'directories' "$persisted"
  [ "$status" -eq 1 ]

  # Re-init, entry unchecked: nothing is asked and the values stay, whatever the seeds say.
  reset_stub
  run env HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_STATE_HOME="$TEST_HOME/.local/state" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" PATH="$STUBS:/usr/bin:/bin" GUM_STUB_DIR="$STUBS" \
    CTTY_LOG="$TTY_LOG" DOTFILES_INSTALL_MODE=configs \
    DOTFILES_WORKTREES_DIR=/tmp/other DOTFILES_AGENTS_DIR=/tmp/other \
    python3 "$CTTY" --stdin-tty "$CHEZMOI" init --source "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$(gum_count write)" = 0 ]
  grep -Fq 'worktreesDir = "/opt/typed-wt"' "$persisted"
  grep -Fq 'agentsDir = "~/typed/agents"' "$persisted"

  # Re-init, entry checked: the editor opens on the saved values; Enter keeps them.
  reset_stub
  set_write 1 @value
  run env HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_STATE_HOME="$TEST_HOME/.local/state" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" PATH="$STUBS:/usr/bin:/bin" GUM_STUB_DIR="$STUBS" \
    GUM_STUB_AI='opencode directories' CTTY_LOG="$TTY_LOG" DOTFILES_INSTALL_MODE=configs \
    DOTFILES_WORKTREES_DIR=/tmp/other DOTFILES_AGENTS_DIR=/tmp/other \
    python3 "$CTTY" --stdin-tty "$CHEZMOI" init --source "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$(cat "$STUBS/value.write.1")" = $'worktrees: /opt/typed-wt\nagents: ~/typed/agents' ]
  grep -Fq 'worktreesDir = "/opt/typed-wt"' "$persisted"
  grep -Fq 'agentsDir = "~/typed/agents"' "$persisted"
}

@test "zshenv: absent keys render the home-relative defaults as literal paths" {
  printf '[data]\n' > "$CONFIG"
  render_tmpl "$ZSHENV_TMPL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"export DOTFILES_WORKTREES_DIR='$TEST_HOME/worktrees'"* ]]
  [[ "$output" == *"export DOTFILES_AGENTS_DIR='$TEST_HOME/agents'"* ]]
  [[ "$output" != *'{{'* ]]
}

@test "zshenv: configured, tilde, and HOME forms resolve to clean absolute paths" {
  printf '[data]\nworktreesDir = "/opt/worktrees/"\nagentsDir = "~/notes//agents/"\n' > "$CONFIG"
  render_tmpl "$ZSHENV_TMPL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"export DOTFILES_WORKTREES_DIR='/opt/worktrees'"* ]]
  [[ "$output" == *"export DOTFILES_AGENTS_DIR='$TEST_HOME/notes/agents'"* ]]

  printf '[data]\nworktreesDir = "$HOME/wt"\nagentsDir = "${HOME}/ag"\n' > "$CONFIG"
  render_tmpl "$ZSHENV_TMPL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"export DOTFILES_WORKTREES_DIR='$TEST_HOME/wt'"* ]]
  [[ "$output" == *"export DOTFILES_AGENTS_DIR='$TEST_HOME/ag'"* ]]
}

@test "zshenv: a hand-edited bad value fails the render instead of exporting it" {
  printf '[data]\nworktreesDir = "relative/path"\n' > "$CONFIG"
  render_tmpl "$ZSHENV_TMPL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"data.worktreesDir must be an absolute path"* ]]
}

@test "zshenv: every zsh mode exports the resolved values and keeps the rest" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
  printf '[data]\nworktreesDir = "/opt/worktrees"\n' > "$CONFIG"
  render_tmpl "$ZSHENV_TMPL"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$TEST_HOME/.zshenv"
  for mode in -c -ic -lc; do
    run env -i HOME="$TEST_HOME" ZDOTDIR="$TEST_HOME" PATH=/usr/bin:/bin TERM=dumb \
      zsh "$mode" 'printf "%s|%s|%s\n" "$DOTFILES_WORKTREES_DIR" "$DOTFILES_AGENTS_DIR" "$DO_NOT_TRACK"'
    [ "$status" -eq 0 ]
    [ "${lines[$((${#lines[@]} - 1))]}" = "/opt/worktrees|$TEST_HOME/agents|1" ]
  done
}

@test "zshenv: chezmoi applies the template to ~/.zshenv only with the zsh component" {
  printf '[data]\nworktreesDir = "/opt/worktrees"\n[data.components]\nzsh = true\n' > "$CONFIG"
  run env HOME="$TEST_HOME" chezmoi apply --source "$REPO_ROOT" --config "$CONFIG" \
    --destination "$TEST_HOME" --exclude=scripts,externals --refresh-externals=never \
    --no-tty "$TEST_HOME/.zshenv"
  [ "$status" -eq 0 ]
  grep -Fxq "export DOTFILES_WORKTREES_DIR='/opt/worktrees'" "$TEST_HOME/.zshenv"
  grep -Fxq "export DOTFILES_AGENTS_DIR='$TEST_HOME/agents'" "$TEST_HOME/.zshenv"

  rm -f "$TEST_HOME/.zshenv"
  printf '[data.components]\nzsh = false\n' > "$CONFIG"
  run env HOME="$TEST_HOME" chezmoi managed --source "$REPO_ROOT" --config "$CONFIG" \
    --destination "$TEST_HOME" --path-style=relative
  [ "$status" -eq 0 ]
  [[ "$output" != *'.zshenv'* ]]
}

@test "ensure run script: worktrees always, agents only with an AI sub-feature" {
  local feature
  printf '[data]\nworktreesDir = "/opt/worktrees"\nagentsDir = "/opt/agents"\n' > "$CONFIG"
  render_tmpl "$ENSURE_RUN_TMPL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dirs=('/opt/worktrees')"* ]]
  [[ "$output" != *'/opt/agents'* ]]

  for feature in claude_hooks codex_hooks statusline opencode copilot openviking codecompanion; do
    printf '[data]\nworktreesDir = "/opt/worktrees"\nagentsDir = "/opt/agents"\n[data.components.ai]\n%s = true\n' \
      "$feature" > "$CONFIG"
    render_tmpl "$ENSURE_RUN_TMPL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dirs=('/opt/worktrees' '/opt/agents')"* ]]
  done
}

@test "ensure run script: an old config creates the default directories" {
  printf '[data.components.ai]\nopencode = true\n' > "$CONFIG"
  render_tmpl "$ENSURE_RUN_TMPL"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/run.sh"
  run env HOME="$TEST_HOME" bash "$BATS_TEST_TMPDIR/run.sh"
  [ "$status" -eq 0 ]
  [ -d "$TEST_HOME/worktrees" ]
  [ -d "$TEST_HOME/agents" ]
  [ "$(mode_of "$TEST_HOME/worktrees")" = 755 ]
}

@test "ensure run script: a non-writable parent warns and still exits zero" {
  [ "$(id -u)" -ne 0 ] || skip "root can write anywhere"
  mkdir "$TEST_HOME/locked"
  chmod 555 "$TEST_HOME/locked"
  printf '[data]\nworktreesDir = "%s/locked/worktrees"\n' "$TEST_HOME" > "$CONFIG"
  render_tmpl "$ENSURE_RUN_TMPL"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/run.sh"
  run env HOME="$TEST_HOME" bash "$BATS_TEST_TMPDIR/run.sh"
  chmod 755 "$TEST_HOME/locked"
  [ "$status" -eq 0 ]
  [[ "$output" == *'WARNING cannot create'* ]]
  [[ "$output" == *"sudo install -d -o \"\$USER\" -m 0755 $TEST_HOME/locked/worktrees"* ]]
  [ ! -e "$TEST_HOME/locked/worktrees" ]
}

@test "ensure-dirs: creates nested directories with mode 755 and is idempotent" {
  run bash "$ENSURE_DIRS" "$TEST_HOME/a/b/worktrees"
  [ "$status" -eq 0 ]
  [[ "$output" == *"created $TEST_HOME/a/b/worktrees"* ]]
  [ "$(mode_of "$TEST_HOME/a/b/worktrees")" = 755 ]

  run bash "$ENSURE_DIRS" "$TEST_HOME/a/b/worktrees"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ensure-dirs: leaves an existing directory's mode and contents alone" {
  mkdir -m 700 "$TEST_HOME/agents"
  : > "$TEST_HOME/agents/keep"
  run bash "$ENSURE_DIRS" "$TEST_HOME/agents"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(mode_of "$TEST_HOME/agents")" = 700 ]
  [ -f "$TEST_HOME/agents/keep" ]
}

@test "ensure-dirs: unusable targets warn without failing or running sudo" {
  : > "$TEST_HOME/file"
  ln -s "$TEST_HOME/missing" "$TEST_HOME/dangling"
  run bash "$ENSURE_DIRS" "$TEST_HOME/file" "$TEST_HOME/dangling" relative "" "$TEST_HOME/file/child"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_HOME/file exists but is not a usable directory"* ]]
  [[ "$output" == *"$TEST_HOME/dangling exists but is not a usable directory"* ]]
  [[ "$output" == *"skipping 'relative'"* ]]
  [[ "$output" == *"$TEST_HOME/file is not a directory"* ]]
  [[ "$output" != *'sudo install'* ]]
}

@test "ensure-dirs: an existing directory the user cannot write gets a chown hint" {
  [ "$(id -u)" -ne 0 ] || skip "root can write anywhere"
  mkdir -m 555 "$TEST_HOME/shared"
  run bash "$ENSURE_DIRS" "$TEST_HOME/shared"
  chmod 755 "$TEST_HOME/shared"
  [ "$status" -eq 0 ]
  [[ "$output" == *'sudo chown "$USER"'* ]]
}

@test "ensure-dirs: quotes a path with spaces in the privileged hint" {
  [ "$(id -u)" -ne 0 ] || skip "root can write anywhere"
  mkdir -m 555 "$TEST_HOME/locked dir"
  run bash "$ENSURE_DIRS" "$TEST_HOME/locked dir/work trees"
  chmod 755 "$TEST_HOME/locked dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *'locked\ dir/work\ trees'* ]]
}
