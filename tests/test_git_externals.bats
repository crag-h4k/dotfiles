#!/usr/bin/env bats
# tests/test_git_externals.bats
# Verify selected chezmoi git externals update only through clean fast-forwards.
# shellcheck source-path=SCRIPTDIR

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  # shellcheck source=../scripts/common.sh
  source "$REPO_ROOT/scripts/common.sh"
  export GIT_AUTHOR_NAME="Dotfiles Test"
  export GIT_AUTHOR_EMAIL="dotfiles@example.invalid"
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
  export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  REMOTE="$BATS_TEST_TMPDIR/remote"
  EXTERNAL="$BATS_TEST_TMPDIR/external"
  git init -q "$REMOTE"
  git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
  advance_ref "$REMOTE" refs/heads/main "initial"
  git clone -q "$REMOTE" "$EXTERNAL"
}

advance_ref() {
  local repo="$1" ref="$2" message="$3" parent commit tree
  parent=$(git -C "$repo" rev-parse --verify "$ref" 2>/dev/null || true)
  tree=$(git -C "$repo" mktree </dev/null)
  if [[ -n "$parent" ]]; then
    commit=$(printf '%s\n' "$message" | git -C "$repo" commit-tree "$tree" -p "$parent")
  else
    commit=$(printf '%s\n' "$message" | git -C "$repo" commit-tree "$tree")
  fi
  git -C "$repo" update-ref "$ref" "$commit"
  printf '%s\n' "$commit"
}

@test "git external advances by fast-forward" {
  local wanted
  wanted=$(advance_ref "$REMOTE" refs/heads/main "remote update")
  run update_git_external sample "$REMOTE" "$EXTERNAL"
  [ "$status" -eq 0 ]
  [ "$(git -C "$EXTERNAL" rev-parse HEAD)" = "$wanted" ]
}

@test "git external skips a dirty checkout" {
  local before
  before=$(git -C "$EXTERNAL" rev-parse HEAD)
  printf 'local\n' >"$EXTERNAL/untracked"
  advance_ref "$REMOTE" refs/heads/main "remote update" >/dev/null
  run update_git_external sample "$REMOTE" "$EXTERNAL"
  [ "$status" -eq 2 ]
  [ "$(git -C "$EXTERNAL" rev-parse HEAD)" = "$before" ]
  [[ "$output" == *"local changes present; skipped"* ]]
}

@test "git external follows an alternate configured tracking remote" {
  local alternate="$BATS_TEST_TMPDIR/alternate" wanted
  git clone -q "$REMOTE" "$alternate"
  git -C "$EXTERNAL" remote add mirror "$alternate"
  git -C "$EXTERNAL" config branch.main.remote mirror
  git -C "$EXTERNAL" config branch.main.merge refs/heads/main
  git -C "$EXTERNAL" fetch -q mirror
  wanted=$(advance_ref "$alternate" refs/heads/main "mirror update")
  run update_git_external sample "$alternate" "$EXTERNAL"
  [ "$status" -eq 0 ]
  [ "$(git -C "$EXTERNAL" rev-parse HEAD)" = "$wanted" ]
}

@test "git external skips a mismatched declared URL" {
  local other="$BATS_TEST_TMPDIR/other"
  git clone -q "$REMOTE" "$other"
  run update_git_external sample "$other" "$EXTERNAL"
  [ "$status" -eq 2 ]
  [[ "$output" == *"does not match the declared external"* ]]
}

@test "git external skips a non-repository path" {
  local not_repo="$BATS_TEST_TMPDIR/not-repo"
  mkdir -p "$not_repo"
  run update_git_external sample "$REMOTE" "$not_repo"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a git repository"* ]]
}

@test "git external skips detached HEAD" {
  git -C "$EXTERNAL" checkout -q --detach
  run update_git_external sample "$REMOTE" "$EXTERNAL"
  [ "$status" -eq 2 ]
  [[ "$output" == *"detached HEAD"* ]]
}

@test "git external skips a locally ahead branch" {
  local before
  before=$(advance_ref "$EXTERNAL" refs/heads/main "local ahead")
  run update_git_external sample "$REMOTE" "$EXTERNAL"
  [ "$status" -eq 2 ]
  [ "$(git -C "$EXTERNAL" rev-parse HEAD)" = "$before" ]
  [[ "$output" == *"local branch is ahead"* ]]
}

@test "git external skips diverged branches" {
  local before
  advance_ref "$REMOTE" refs/heads/main "remote update" >/dev/null
  before=$(advance_ref "$EXTERNAL" refs/heads/main "local update")
  run update_git_external sample "$REMOTE" "$EXTERNAL"
  [ "$status" -eq 2 ]
  [ "$(git -C "$EXTERNAL" rev-parse HEAD)" = "$before" ]
  [[ "$output" == *"diverged"* ]]
}

@test "git external leaves missing materialization to chezmoi" {
  local selected="$BATS_TEST_TMPDIR/selected"
  run update_git_external selected "$REMOTE" "$selected"
  [ "$status" -eq 2 ]
  [ ! -e "$selected" ]
  [[ "$output" == *"chezmoi must materialize it"* ]]
}

@test "installer-owned Git runtime clones when missing" {
  local runtime="$BATS_TEST_TMPDIR/runtime"
  run install_or_update_git_runtime runtime "$REMOTE" "$runtime"
  [ "$status" -eq 0 ]
  [ -d "$runtime/.git" ]
  [ "$(git -C "$runtime" rev-parse HEAD)" = "$(git -C "$REMOTE" rev-parse HEAD)" ]
}

@test "git external reports tracking-remote fetch failure" {
  local missing="$BATS_TEST_TMPDIR/missing-remote"
  git -C "$EXTERNAL" remote set-url origin "$missing"
  run update_git_external sample "$missing" "$EXTERNAL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fetch from tracking remote origin failed"* ]]
}
