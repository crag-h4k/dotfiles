#!/usr/bin/env bats
# tests/test_git_wt.bats
# `git wt` (home/dot_local/bin/executable_git-wt): flat worktrees under
# $DOTFILES_WORKTREES_DIR/<repo>-<slug>. Every repository, remote, and worktree
# root is a disposable fixture; nothing touches the network or the real home.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
GIT_WT_SRC="$REPO_ROOT/home/dot_local/bin/executable_git-wt"

setup() {
  # A commit hook exports these; the fixtures must use their own repositories.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
    GIT_INDEX_VERSION GIT_CONFIG_PARAMETERS DOTFILES_WORKTREES_DIR
  local real
  real="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="$real/home"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  mkdir -p "$HOME/bin"
  cp "$GIT_WT_SRC" "$HOME/bin/git-wt"
  chmod +x "$HOME/bin/git-wt"
  export PATH="$HOME/bin:$PATH"
  git config --global user.name "Test User"
  git config --global user.email test@example.invalid
  git config --global init.defaultBranch main
  git config --global advice.detachedHead false
  WT="$real/worktrees"
  export DOTFILES_WORKTREES_DIR="$WT"
  # A bare "remote" on disk and a clone of it named proj.
  git init -q --bare "$real/remote.git"
  git clone -q "$real/remote.git" "$real/proj" 2>/dev/null
  git -C "$real/proj" commit -q --allow-empty -m first
  git -C "$real/proj" push -q origin main 2>/dev/null
  git -C "$real/proj" remote set-head origin main
  PROJ="$real/proj"
  REMOTE="$real/remote.git"
}

last_line() { printf '%s\n' "$output" | tail -n 1; }

# advance_remote: one new commit on the remote's main, not yet fetched by proj.
advance_remote() {
  local other="$BATS_TEST_TMPDIR/other"
  git clone -q "$REMOTE" "$other" 2>/dev/null
  git -C "$other" commit -q --allow-empty -m second
  git -C "$other" push -q origin main 2>/dev/null
  git -C "$other" rev-parse HEAD
}

@test "git wt: a new branch lands flat under the root, from origin/HEAD, without tracking" {
  cd "$PROJ"
  run --separate-stderr git wt feat/foo-bar
  [ "$status" -eq 0 ]
  [ "$(last_line)" = "$WT/proj-foo-bar" ]
  # Only the path is on stdout; Git's progress went to stderr.
  [ "$output" = "$WT/proj-foo-bar" ]
  [ "$(git -C "$WT/proj-foo-bar" branch --show-current)" = feat/foo-bar ]
  [ "$(git -C "$WT/proj-foo-bar" rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
  run git -C "$WT/proj-foo-bar" rev-parse --abbrev-ref '@{upstream}'
  [ "$status" -ne 0 ]
  # Flat: nothing nested under a project folder.
  [ "$(ls "$WT")" = proj-foo-bar ]
}

@test "git wt: the slug is the part after the last slash" {
  cd "$PROJ"
  run git wt user/feat/deep-slug
  [ "$status" -eq 0 ]
  [ "$(last_line)" = "$WT/proj-deep-slug" ]
  run git wt plain
  [ "$status" -eq 0 ]
  [ "$(last_line)" = "$WT/proj-plain" ]
}

@test "git wt: an existing branch is checked out as is" {
  cd "$PROJ"
  git branch fix/kept
  git -C "$PROJ" commit -q --allow-empty -m on-main
  run git wt fix/kept origin/main
  [ "$status" -eq 0 ]
  [ "$(last_line)" = "$WT/proj-kept" ]
  [ "$(git -C "$WT/proj-kept" branch --show-current)" = fix/kept ]
  [ "$(git -C "$WT/proj-kept" rev-parse HEAD)" = "$(git rev-parse fix/kept)" ]
  [[ "$output" == *'already exists; checking it out and ignoring origin/main'* ]]
}

@test "git wt: an explicit base, and HEAD without origin/HEAD" {
  cd "$PROJ"
  git commit -q --allow-empty -m local-only
  run git wt feat/from-head HEAD
  [ "$status" -eq 0 ]
  [ "$(git -C "$WT/proj-from-head" rev-parse HEAD)" = "$(git rev-parse HEAD)" ]

  git remote set-head origin --delete
  run git wt feat/no-origin-head
  [ "$status" -eq 0 ]
  [ "$(git -C "$WT/proj-no-origin-head" rev-parse HEAD)" = "$(git rev-parse HEAD)" ]
}

@test "git wt: run from a linked worktree, the repo name is the main worktree's" {
  cd "$PROJ"
  git worktree add -q -b side "$BATS_TEST_TMPDIR/some-other-name" 2>/dev/null
  cd "$BATS_TEST_TMPDIR/some-other-name"
  run git wt feat/from-linked
  [ "$status" -eq 0 ]
  [ "$(last_line)" = "$WT/proj-from-linked" ]
  [ -d "$WT/proj-from-linked" ]
}

@test "git wt: a bare repository uses its name without .git" {
  cd "$REMOTE"
  run git wt feat/bare
  [ "$status" -eq 0 ]
  [ "$(last_line)" = "$WT/remote-bare" ]

  # A bare repository stored as <dir>/.git is named after <dir>.
  local holder="$BATS_TEST_TMPDIR/holder"
  mkdir -p "$holder"
  git clone -q --bare "$REMOTE" "$holder/.git" 2>/dev/null
  cd "$holder/.git"
  run git wt feat/inner
  [ "$status" -eq 0 ]
  [ "$(last_line)" = "$WT/holder-inner" ]
}

@test "git wt: an existing destination is refused and nothing is created" {
  cd "$PROJ"
  mkdir -p "$WT/proj-taken"
  : >"$WT/proj-taken/keep"
  run git wt feat/taken
  [ "$status" -ne 0 ]
  [[ "$output" == *"$WT/proj-taken already exists"* ]]
  [ -f "$WT/proj-taken/keep" ]
  run git show-ref --verify --quiet refs/heads/feat/taken
  [ "$status" -ne 0 ]

  ln -s "$BATS_TEST_TMPDIR/nowhere" "$WT/proj-dangling"
  run git wt feat/dangling
  [ "$status" -ne 0 ]
  [[ "$output" == *'already exists'* ]]
}

@test "git wt: without DOTFILES_WORKTREES_DIR it falls back to \$HOME/worktrees" {
  cd "$PROJ"
  run env -u DOTFILES_WORKTREES_DIR git wt feat/fallback
  [ "$status" -eq 0 ]
  [ "$(last_line)" = "$HOME/worktrees/proj-fallback" ]
  [ -d "$HOME/worktrees/proj-fallback" ]

  run env DOTFILES_WORKTREES_DIR=relative/root git wt feat/relative
  [ "$status" -ne 0 ]
  [[ "$output" == *'must be an absolute path'* ]]
}

@test "git wt: nothing is fetched unless --fetch asks for the base's branch" {
  cd "$PROJ"
  local before newer
  before=$(git rev-parse origin/main)
  newer=$(advance_remote)
  run git wt feat/stale
  [ "$status" -eq 0 ]
  [ "$(git -C "$WT/proj-stale" rev-parse HEAD)" = "$before" ]
  [ "$(git rev-parse origin/main)" = "$before" ]

  run git wt --fetch feat/fresh
  [ "$status" -eq 0 ]
  [ "$(last_line)" = "$WT/proj-fresh" ]
  [ "$(git -C "$WT/proj-fresh" rev-parse HEAD)" = "$newer" ]
  [ "$(git rev-parse origin/main)" = "$newer" ]
  # Only that branch: no tags arrived with it.
  [ -z "$(git tag)" ]

  run git wt --fetch feat/local-base HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *'is not a remote-tracking branch; nothing to fetch'* ]]
}

@test "git wt: help, bad names, and bad usage" {
  cd "$PROJ"
  run git wt -h
  [ "$status" -eq 0 ]
  [[ "$output" == usage:\ git\ wt* ]]
  run git-wt --help
  [ "$status" -eq 0 ]
  [[ "$output" == usage:\ git\ wt* ]]
  run git wt
  [ "$status" -eq 2 ]
  run git wt 'bad..name'
  [ "$status" -ne 0 ]
  [[ "$output" == *'is not a valid branch name'* ]]
  run git wt feat/
  [ "$status" -ne 0 ]
  run git wt --bogus x
  [ "$status" -ne 0 ]
  cd "$BATS_TEST_TMPDIR"
  run git wt feat/outside
  [ "$status" -ne 0 ]
  [[ "$output" == *'not inside a Git repository'* ]]
}

@test "git wt: chezmoi installs it with the git component only" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local config="$BATS_TEST_TMPDIR/chezmoi.toml"
  printf '[data.components.git]\nconfig = false\nignore_global = true\n' >"$config"
  run chezmoi managed --source "$REPO_ROOT" --config "$config" --destination "$HOME" \
    --path-style=relative --include=files
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -Fxq .local/bin/git-wt

  printf '[data.components.git]\nconfig = false\nignore_global = false\n' >"$config"
  run chezmoi managed --source "$REPO_ROOT" --config "$config" --destination "$HOME" \
    --path-style=relative --include=files
  [ "$status" -eq 0 ]
  run grep -Fxq .local/bin/git-wt <<<"$output"
  [ "$status" -ne 0 ]
}
