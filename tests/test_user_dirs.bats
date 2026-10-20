#!/usr/bin/env bats
# shellcheck disable=SC2016
# tests/test_user_dirs.bats
# The worktrees and agent-notes directories: chezmoi data keys (worktreesDir,
# agentsDir), their env seeds, the shared dotfiles-dir template, the ~/.zshenv
# exports, and the directory-creation script. Everything runs against a
# disposable HOME and config; nothing touches the real home or runs sudo.
# SC2016 is disabled file-wide: literal $HOME and $USER are the values under test.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
CONFIG_TMPL="${REPO_ROOT}/home/.chezmoi.toml.tmpl"
ZSHENV_TMPL="${REPO_ROOT}/home/dot_zshenv.tmpl"
ENSURE_RUN_TMPL="${REPO_ROOT}/home/.chezmoiscripts/run_after_02-ensure-dirs.sh.tmpl"
ENSURE_DIRS="${REPO_ROOT}/scripts/ensure-dirs.sh"

setup() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # A commit hook exports these; chezmoi init shells out to Git.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
    GIT_INDEX_VERSION GIT_CONFIG_PARAMETERS
  unset DOTFILES_WORKTREES_DIR DOTFILES_AGENTS_DIR
  TEST_HOME="${BATS_TEST_TMPDIR}/home"
  CONFIG="${BATS_TEST_TMPDIR}/chezmoi.toml"
  mkdir -p "$TEST_HOME"
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
