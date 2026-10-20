#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2088
# tests/test_user_dirs.bats
# The worktrees and agent-notes directories: chezmoi data keys (worktreesDir,
# agentsDir), their env seeds, the init prompts that follow the AI submenu, the
# shared dotfiles-dir template, the ~/.zshenv exports, and the directory-creation
# script. Everything runs against a disposable HOME and config; nothing touches the
# real home or runs sudo.
#
# The prompts need a terminal, so those tests run the init template through
# tests/ctty_run.py, which supplies (or withholds) a controlling pty on any host,
# with a stub `gum` on PATH that records calls and answers from a script. chezmoi's
# prompt simulation (-p "<prompt text>=value") stands in for typing without Gum.
# SC2016 and SC2088 are disabled file-wide: literal $HOME, $USER, and ~/ are the
# values under test.

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

# --- init prompts after the AI submenu ----------------------------------------

# write_gum_stub: a gum stand-in. It records every call to $STUBS/calls and answers
# like a user: `choose` accepts the preselected options, or the options whose text
# starts with a prefix named in GUM_STUB_TOP / GUM_STUB_AI; `input` answers with
# line N of $STUBS/inputs, where "@value" presses Enter on the offered value and a
# missing line is Esc (no output, non-zero exit).
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
  for arg in "$@"; do printf ' [%s]' "$arg"; done
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
    --placeholder | --width | --prompt) shift ;;
    --no-limit) ;;
    *) options="$options$1
" ;;
  esac
  shift
done
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
  input)
    answer=$(sed -n "${n}p" "$dir/inputs" 2>/dev/null)
    if [ -z "$answer" ]; then exit 1; fi
    if [ "$answer" = "@value" ]; then answer=$value; fi
    printf '%s\n' "$answer"
    ;;
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

# set_inputs <line>...: the answers the stub gives to successive `gum input` calls.
set_inputs() {
  printf '%s\n' "$@" > "$STUBS/inputs"
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
    --source "$REPO_ROOT" --config "$CONFIG" ${args[@]+"${args[@]}"} "$CONFIG_TMPL" </dev/null
}

# gum_calls <subcommand>: the recorded calls of that subcommand.
gum_calls() {
  grep -F "$1 #" "$STUBS/calls" 2>/dev/null || true
}

# no_gum_calls: the stub was never run.
no_gum_calls() {
  [ ! -e "$STUBS/calls" ]
}

@test "prompt: a first init pre-fills the defaults right after the AI submenu" {
  need_pty
  printf '[data]\n' > "$CONFIG"
  set_inputs @value @value
  render_tty GUM_STUB_TOP='5)' GUM_STUB_AI=opencode
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "$HOME/worktrees"'* ]]
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]
  # Order: top picker, AI submenu, then the two directory prompts.
  [ "$(sed -n 1p "$STUBS/calls" | cut -d' ' -f1-2)" = "choose #1:" ]
  [ "$(sed -n 2p "$STUBS/calls" | cut -d' ' -f1-2)" = "choose #2:" ]
  [ "$(sed -n 3p "$STUBS/calls" | cut -d' ' -f1-2)" = "input #1:" ]
  [ "$(sed -n 4p "$STUBS/calls" | cut -d' ' -f1-2)" = "input #2:" ]
  [ "$(wc -l < "$STUBS/calls" | tr -d ' ')" = 4 ]
  gum_calls input | sed -n 1p | grep -Fq '[--value] [$HOME/worktrees]'
  gum_calls input | sed -n 2p | grep -Fq '[--value] [$HOME/agents]'
}

@test "prompt: a re-init pre-fills the saved values and keeps them on Enter" {
  need_pty
  seed_ai_config 'worktreesDir = "~/src/worktrees"' 'agentsDir = "/srv/agents"'
  set_inputs @value @value
  render_tty DOTFILES_WORKTREES_DIR=/opt/seeded DOTFILES_AGENTS_DIR=/opt/seeded
  [ "$status" -eq 0 ]
  gum_calls input | sed -n 1p | grep -Fq '[--value] [~/src/worktrees]'
  gum_calls input | sed -n 2p | grep -Fq '[--value] [/srv/agents]'
  [[ "$output" == *'worktreesDir = "~/src/worktrees"'* ]]
  [[ "$output" == *'agentsDir = "/srv/agents"'* ]]
}

@test "prompt: the env seed pre-fills a host with no saved value" {
  need_pty
  seed_ai_config
  set_inputs @value @value
  render_tty DOTFILES_WORKTREES_DIR=/opt/seeded-wt DOTFILES_AGENTS_DIR='~/seeded/agents'
  [ "$status" -eq 0 ]
  gum_calls input | sed -n 1p | grep -Fq '[--value] [/opt/seeded-wt]'
  gum_calls input | sed -n 2p | grep -Fq '[--value] [~/seeded/agents]'
  [[ "$output" == *'worktreesDir = "/opt/seeded-wt"'* ]]
  [[ "$output" == *'agentsDir = "~/seeded/agents"'* ]]
}

@test "prompt: a typed gum answer overrides the pre-fill and is stored verbatim" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/old-wt"'
  set_inputs '/opt/typed-wt/' '~/typed/agents'
  render_tty
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "/opt/typed-wt/"'* ]]
  [[ "$output" == *'agentsDir = "~/typed/agents"'* ]]
}

@test "prompt: Escape in Gum keeps the shown value and does not ask twice" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/kept-wt"'
  : > "$STUBS/inputs"
  render_tty
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "/srv/kept-wt"'* ]]
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]
  [ "$(gum_calls input | wc -l | tr -d ' ')" = 2 ]
}

@test "prompt: without Gum a typed prompt is pre-filled and an answer overrides it" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/saved-wt"'
  render_tty PATH=/usr/bin:/bin
  [ "$status" -eq 0 ]
  no_gum_calls
  [[ "$output" == *'worktreesDir = "/srv/saved-wt"'* ]]
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]

  render_tty PATH=/usr/bin:/bin -- -p "$WT_TITLE=/opt/typed-wt" -p "$AG_TITLE=~/typed/agents"
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "/opt/typed-wt"'* ]]
  [[ "$output" == *'agentsDir = "~/typed/agents"'* ]]
}

@test "prompt: no controlling terminal keeps the pre-fill and never opens a prompt" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/saved-wt"'
  set_inputs /opt/never-used /opt/never-used
  CTTY_MODE=--none
  render_tty DOTFILES_AGENTS_DIR=/opt/seeded-agents -- -p "$WT_TITLE=/opt/ignored" -p "$AG_TITLE=/opt/ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "/srv/saved-wt"'* ]]
  [[ "$output" == *'agentsDir = "/opt/seeded-agents"'* ]]
  [ -z "$(gum_calls input)" ]
}

@test "prompt: a tty stdin without a controlling terminal never prompts" {
  need_pty
  # chezmoi's own promptString fails here (no /dev/tty), so the template must not
  # reach it; the simulated answers would win if the gate let it through.
  seed_ai_config 'worktreesDir = "/srv/saved-wt"'
  CTTY_MODE=--stdin-only
  render_tty PATH=/usr/bin:/bin -- -p "$WT_TITLE=/opt/ignored" -p "$AG_TITLE=/opt/ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "/srv/saved-wt"'* ]]
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]
}

@test "prompt: a terminal without a tty stdin keeps the pre-fill and never prompts" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/saved-wt"'
  set_inputs /opt/never-used /opt/never-used
  CTTY_MODE=--ctty
  render_tty -- -p "$WT_TITLE=/opt/ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "/srv/saved-wt"'* ]]
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]
  [ -z "$(gum_calls input)" ]
}

@test "prompt: DOTFILES_NO_TUI skips every prompt and keeps the pre-fill" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/saved-wt"'
  set_inputs /opt/never-used /opt/never-used
  render_tty DOTFILES_NO_TUI=1 -- -p "$WT_TITLE=/opt/ignored" -p "$AG_TITLE=/opt/ignored"
  [ "$status" -eq 0 ]
  no_gum_calls
  [[ "$output" == *'worktreesDir = "/srv/saved-wt"'* ]]
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]
}

@test "prompt: a host without AI selected is never asked and keeps its values" {
  need_pty
  printf '[data]\n    componentSelection = "1 2 3"\n    worktreesDir = "/srv/saved-wt"\n    agentsDir = "/srv/saved-agents"\n' > "$CONFIG"
  set_inputs /opt/never-used /opt/never-used
  render_tty DOTFILES_WORKTREES_DIR=/opt/seeded -- -p "$WT_TITLE=/opt/ignored"
  [ "$status" -eq 0 ]
  [ -z "$(gum_calls input)" ]
  [[ "$output" == *'worktreesDir = "/srv/saved-wt"'* ]]
  [[ "$output" == *'agentsDir = "/srv/saved-agents"'* ]]
}

@test "prompt: a package update re-init (cup) does not reopen the directory prompts" {
  need_pty
  seed_ai_config 'worktreesDir = "/srv/saved-wt"'
  set_inputs /opt/never-used /opt/never-used
  render_tty DOTFILES_PACKAGE_UPDATE=1 -- -p "$WT_TITLE=/opt/ignored"
  [ "$status" -eq 0 ]
  [ -z "$(gum_calls input)" ]
  [[ "$output" == *'worktreesDir = "/srv/saved-wt"'* ]]
}

@test "prompt: chezmoi apply never prompts, even with Gum and a terminal" {
  need_pty
  printf '[data]\nworktreesDir = "/opt/worktrees"\n[data.components]\nzsh = true\n[data.components.ai]\nopencode = true\n' > "$CONFIG"
  set_inputs /opt/never-used /opt/never-used
  run env HOME="$TEST_HOME" PATH="$STUBS:/usr/bin:/bin" GUM_STUB_DIR="$STUBS" CTTY_LOG="$TTY_LOG" \
    python3 "$CTTY" --stdin-tty "$CHEZMOI" apply --source "$REPO_ROOT" --config "$CONFIG" \
    --destination "$TEST_HOME" --exclude=scripts,externals --refresh-externals=never \
    "$TEST_HOME/.zshenv"
  [ "$status" -eq 0 ]
  no_gum_calls
  grep -Fxq "export DOTFILES_WORKTREES_DIR='/opt/worktrees'" "$TEST_HOME/.zshenv"
}

@test "prompt: a bad Gum answer is explained and asked again" {
  need_pty
  seed_ai_config
  set_inputs relative/path /srv/good-wt @value
  render_tty
  [ "$status" -eq 0 ]
  [[ "$output" == *'worktreesDir = "/srv/good-wt"'* ]]
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]
  [ "$(gum_calls input | wc -l | tr -d ' ')" = 3 ]
  grep -Fq 'Not a usable directory' "$TTY_LOG"
}

@test "prompt: three bad answers fail with the existing clear error" {
  need_pty
  seed_ai_config
  set_inputs relative/path relative/path relative/path
  render_tty
  [ "$status" -ne 0 ]
  [[ "$output" == *"data.worktreesDir must be an absolute path"* ]]
  [ "$(gum_calls input | wc -l | tr -d ' ')" = 3 ]
}

@test "prompt: a bad typed answer is asked again and then fails clearly" {
  need_pty
  seed_ai_config
  render_tty PATH=/usr/bin:/bin -- -p "$WT_TITLE=/tmp/it's"
  [ "$status" -ne 0 ]
  [[ "$output" == *"data.worktreesDir must name a directory using only"* ]]
}

@test "prompt: an unusable saved value is replaced by the default, never run by the shell" {
  need_pty
  # A quote in a saved value would end the single-quoted --value word in the Gum
  # command; the injected command must not run and the default is shown instead.
  seed_ai_config "agentsDir = \"/tmp/x'; touch $TEST_HOME/pwned; echo '\""
  set_inputs @value @value
  render_tty
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_HOME/pwned" ]
  gum_calls input | sed -n 2p | grep -Fq '[--value] [$HOME/agents]'
  [[ "$output" == *'agentsDir = "$HOME/agents"'* ]]
  grep -Fq 'agentsDir value is not usable' "$TTY_LOG"
}

@test "prompt: a real chezmoi init stores a typed answer and pre-fills it next time" {
  need_pty
  local persisted="$TEST_HOME/.config/chezmoi/chezmoi.toml"
  mkdir -p "$(dirname "$persisted")"
  printf '[data]\n    componentSelection = "5"\n    aiSelection = "opencode"\n[data.components.ai]\n    opencode = true\n' > "$persisted"
  set_inputs /opt/typed-wt '~/typed/agents'
  run env HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_STATE_HOME="$TEST_HOME/.local/state" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" PATH="$STUBS:/usr/bin:/bin" GUM_STUB_DIR="$STUBS" \
    CTTY_LOG="$TTY_LOG" DOTFILES_INSTALL_MODE=configs \
    python3 "$CTTY" --stdin-tty "$CHEZMOI" init --source "$REPO_ROOT"
  [ "$status" -eq 0 ]
  grep -Fq 'worktreesDir = "/opt/typed-wt"' "$persisted"
  grep -Fq 'agentsDir = "~/typed/agents"' "$persisted"

  # Re-init: the typed values are the pre-fill, and Enter keeps them even when the
  # env seeds say otherwise.
  rm -f "$STUBS/calls" "$STUBS"/n.*
  set_inputs @value @value
  run env HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" XDG_STATE_HOME="$TEST_HOME/.local/state" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" PATH="$STUBS:/usr/bin:/bin" GUM_STUB_DIR="$STUBS" \
    CTTY_LOG="$TTY_LOG" DOTFILES_INSTALL_MODE=configs \
    DOTFILES_WORKTREES_DIR=/tmp/other DOTFILES_AGENTS_DIR=/tmp/other \
    python3 "$CTTY" --stdin-tty "$CHEZMOI" init --source "$REPO_ROOT"
  [ "$status" -eq 0 ]
  gum_calls input | sed -n 1p | grep -Fq '[--value] [/opt/typed-wt]'
  gum_calls input | sed -n 2p | grep -Fq '[--value] [~/typed/agents]'
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
