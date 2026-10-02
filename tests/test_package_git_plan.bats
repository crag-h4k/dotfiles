#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2030,SC2031
# Bats gives each test its own environment.

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
    GIT_INDEX_VERSION GIT_CONFIG_PARAMETERS
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=../scripts/common.sh
  source "$ROOT/scripts/common.sh"
  # shellcheck source=../scripts/package-resolve.sh
  source "$ROOT/scripts/package-resolve.sh"
  export GIT_AUTHOR_NAME="Dotfiles Test" GIT_AUTHOR_EMAIL="dotfiles@example.invalid"
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  REMOTE="$BATS_TEST_TMPDIR/remote"
  EXTERNAL="$BATS_TEST_TMPDIR/external"
  git init -q "$REMOTE"
  git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
  advance_ref "$REMOTE" refs/heads/main initial >/dev/null
  git clone -q "$REMOTE" "$EXTERNAL"
  origin="$REMOTE" probe="$EXTERNAL" policy=floating
  source=git-runtime name=sample current=- candidate=- reason=-
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

@test "Git plan compares remote revisions without changing checkout refs or FETCH_HEAD" {
  local before wanted refs
  before=$(git -C "$EXTERNAL" rev-parse HEAD)
  refs=$(git -C "$EXTERNAL" show-ref)
  printf 'preserve fetch head\n' >"$EXTERNAL/.git/FETCH_HEAD"
  wanted=$(advance_ref "$REMOTE" refs/heads/main update)
  _resolve_git
  [ "$status" = update ]
  [ "$current" = "$before" ]
  [ "$candidate" = "$wanted" ]
  [ "$policy" = branch:main ]
  [ "$(git -C "$EXTERNAL" show-ref)" = "$refs" ]
  [ "$(cat "$EXTERNAL/.git/FETCH_HEAD")" = 'preserve fetch head' ]
  [ -z "$(git -C "$EXTERNAL" status --porcelain)" ]
}

@test "current Git plan avoids fetching objects" {
  _resolve_git
  [ "$status" = installed ]
  [ "$current" = "$candidate" ]
  [ ! -e "$EXTERNAL/.git/FETCH_HEAD" ]
}

@test "Git execution installs the approved commit when remote advances again" {
  local approved newer
  approved=$(advance_ref "$REMOTE" refs/heads/main approved)
  _resolve_git
  newer=$(advance_ref "$REMOTE" refs/heads/main newer)
  run apply_git_package git-runtime sample "$origin" "$probe" "$current" "$candidate" "$policy"
  [ "$status" -eq 0 ]
  [ "$(git -C "$EXTERNAL" rev-parse HEAD)" = "$approved" ]
  [ "$(git -C "$EXTERNAL" rev-parse HEAD)" != "$newer" ]
}

@test "Git execution rejects checkout changes after approval" {
  advance_ref "$REMOTE" refs/heads/main approved >/dev/null
  _resolve_git
  local before="$current"
  printf 'local work\n' >"$EXTERNAL/untracked"
  run apply_git_package git-runtime sample "$origin" "$probe" "$current" "$candidate" "$policy"
  [ "$status" -eq 1 ]
  [[ "$output" == *'local changes present'* ]]
  [ "$(git -C "$EXTERNAL" rev-parse HEAD)" = "$before" ]
}

@test "Git plan blocks dirty detached ahead and diverged checkouts" {
  printf 'local work\n' >"$EXTERNAL/untracked"
  _resolve_git
  [ "$status" = blocked ]
  [ "$reason" = 'local changes present' ]
  rm "$EXTERNAL/untracked"
  git -C "$EXTERNAL" checkout -q --detach
  _resolve_git
  [ "$status" = blocked ]
  [ "$reason" = 'detached HEAD' ]
  git -C "$EXTERNAL" checkout -q main
  advance_ref "$EXTERNAL" refs/heads/main local >/dev/null
  _resolve_git
  [ "$status" = blocked ]
  [[ "$reason" == *'ahead'* ]]
  advance_ref "$REMOTE" refs/heads/main remote >/dev/null
  _resolve_git
  [ "$status" = blocked ]
  [[ "$reason" == *'diverged'* ]]
}

@test "Git plan rejects a mismatched declared origin and a failed lookup" {
  origin="$BATS_TEST_TMPDIR/missing"
  _resolve_git
  [ "$status" = blocked ]
  [[ "$reason" == *'does not match'* ]]
  git -C "$EXTERNAL" remote set-url origin "$origin"
  _resolve_git
  [ "$status" = blocked ]
  [ "$reason" = 'tracking branch lookup failed' ]
}

@test "missing Git runtime installs its approved branch and commit" {
  probe="$BATS_TEST_TMPDIR/runtime"
  _resolve_git
  [ "$status" = planned ]
  [ ! -e "$probe" ]
  local approved="$candidate"
  advance_ref "$REMOTE" refs/heads/main later >/dev/null
  run apply_git_package git-runtime sample "$origin" "$probe" "$current" "$candidate" "$policy"
  [ "$status" -eq 0 ]
  [ "$(git -C "$probe" rev-parse HEAD)" = "$approved" ]
  [ "$(git -C "$probe" symbolic-ref --short HEAD)" = main ]
  [ "$(git -C "$probe" config branch.main.merge)" = refs/heads/main ]
}

@test "missing Git external remains a chezmoi materialization requirement" {
  probe="$BATS_TEST_TMPDIR/external-missing" source=git-external
  _resolve_git
  [ "$status" = check ]
  [ "$reason" = 'resolve after chezmoi materializes the checkout' ]
  [ ! -e "$probe" ]
}

@test "native discovery expands three aggregate rows once with exact package targets" {
  local bin="$BATS_TEST_TMPDIR/bin" calls="$BATS_TEST_TMPDIR/calls"
  mkdir "$bin"
  cat >"$bin/nvim" <<STUB
#!/bin/sh
printf 'called\\n' >>'$calls'
printf 'neovim-plugin\\tplugin-a\\tupdate\\tfloating\\torigin\\tpath\\told\\texact-sha\\tnew commit\\n'
printf 'treesitter-parsers\\tlua\\tinstalled\\tmanifest\\torigin\\tpath\\trevision\\trevision\\tcurrent\\n'
printf 'mason-packages\\tlua-language-server\\tupdate\\tfloating\\torigin\\tpath\\t1.0.0\\t2.0.0\\tnew release\\n'
STUB
  chmod +x "$bin/nvim"
  PATH="$bin:$PATH"
  _records=($'neovim-plugin\tlazy.nvim plugin set\tinstalled\tfloating\torigin\tpath'
    $'treesitter-parsers\tinstalled parser set\tinstalled\tfloating\torigin\tpath'
    $'mason-packages\tinstalled Mason package set\tinstalled\tfloating\torigin\tpath')
  _resolve_records
  [ "${#_records[@]}" -eq 3 ]
  [[ "${_records[0]}" == $'neovim-plugin\tplugin-a\tupdate'* ]]
  [[ "${_records[2]}" == *$'\t2.0.0\t'* ]]
  [ "$(wc -l <"$calls" | tr -d ' ')" -eq 1 ]
}

@test "native discovery failures stay blocked instead of reporting current" {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir "$bin"
  printf '#!/bin/sh\nexit 1\n' >"$bin/nvim"
  chmod +x "$bin/nvim"
  PATH="$bin:$PATH"
  _records=($'neovim-plugin\tlazy.nvim plugin set\tinstalled\tfloating\torigin\tpath')
  _resolve_records
  [[ "${_records[0]}" == $'neovim-plugin\tlazy.nvim plugin set\tblocked'* ]]
  [[ "${_records[0]}" == *'discovery failed' ]]
}

@test "Git plan does not treat a subdirectory as a managed checkout" {
  mkdir "$EXTERNAL/nested"
  probe="$EXTERNAL/nested"
  _resolve_git
  [ "$status" = blocked ]
  [ "$reason" = 'path is not the repository root' ]
}

@test "Git planning preserves index bytes when tracked file metadata changes" {
  printf 'tracked\n' >"$EXTERNAL/tracked"
  git -C "$EXTERNAL" add tracked
  local tree commit index_before
  tree=$(git -C "$EXTERNAL" write-tree)
  commit=$(printf 'tracked fixture\n' | git -C "$EXTERNAL" commit-tree "$tree" -p HEAD)
  git -C "$EXTERNAL" update-ref refs/heads/main "$commit"
  touch -t 202001010000 "$EXTERNAL/tracked"
  index_before=$(cksum "$EXTERNAL/.git/index")
  _resolve_git
  [ "$(cksum "$EXTERNAL/.git/index")" = "$index_before" ]
}

@test "Git execution rejects another local branch at the same approved commit" {
  advance_ref "$REMOTE" refs/heads/main approved >/dev/null
  _resolve_git
  local before="$current"
  git -C "$EXTERNAL" checkout -q -b other
  git -C "$EXTERNAL" config branch.other.remote origin
  git -C "$EXTERNAL" config branch.other.merge refs/heads/main
  run apply_git_package git-runtime sample "$origin" "$probe" "$current" "$candidate" "$policy"
  [ "$status" -eq 1 ]
  [[ "$output" == *'changed after planning'* ]]
  [ "$(git -C "$EXTERNAL" rev-parse HEAD)" = "$before" ]
}

@test "Git execution does not recreate a checkout removed after approval" {
  advance_ref "$REMOTE" refs/heads/main approved >/dev/null
  _resolve_git
  mv "$EXTERNAL" "$EXTERNAL.renamed"
  run apply_git_package git-runtime sample "$origin" "$probe" "$current" "$candidate" "$policy"
  [ "$status" -eq 1 ]
  [[ "$output" == *'disappeared after planning'* ]]
  [ ! -e "$EXTERNAL" ]
}

@test "deferred Git resolution displays and freezes targets once prerequisites exist" {
  export DOTFILES_PACKAGE_PLAN="$BATS_TEST_TMPDIR/plan" DOTFILES_ASSUME_YES=1
  local wanted
  wanted=$(advance_ref "$REMOTE" refs/heads/main approved)
  printf 'git-runtime\tsample\tcheck\tfloating\t%s\t%s\t-\t-\tresolve after Git installation\n' "$REMOTE" "$EXTERNAL" >"$DOTFILES_PACKAGE_PLAN"
  printf 'npm\tuntouched\tinstalled\tpinned:1.0.0\torigin\tpath\t1.0.0\t1.0.0\tcurrent\n' >>"$DOTFILES_PACKAGE_PLAN"
  run package_plan_resolve_deferred_git
  [ "$status" -eq 0 ]
  [[ "$output" == *'To update (1)'* ]]
  [ "$(package_target git-runtime sample)" = "$wanted" ]
  [ "$(package_plan_field git-runtime sample 3)" = update ]
  [ "$(package_target npm untouched)" = 1.0.0 ]
  [ "$(git -C "$EXTERNAL" rev-parse HEAD)" != "$wanted" ]
}

@test "declining a deferred Git plan prevents execution" {
  export DOTFILES_PACKAGE_PLAN="$BATS_TEST_TMPDIR/plan" DOTFILES_ASSUME_YES=0
  export DOTFILES_TTY="$BATS_TEST_TMPDIR/tty"
  printf 'n\n' >"$DOTFILES_TTY"
  advance_ref "$REMOTE" refs/heads/main approved >/dev/null
  printf 'git-runtime\tsample\tcheck\tfloating\t%s\t%s\t-\t-\tresolve after Git installation\n' "$REMOTE" "$EXTERNAL" >"$DOTFILES_PACKAGE_PLAN"
  run package_plan_resolve_deferred_git
  [ "$status" -eq 0 ]
  [ "$(package_plan_field git-runtime sample 3)" = blocked ]
  [ "$(package_plan_field git-runtime sample 9)" = 'resolved Git plan was not approved' ]
}

@test "candidate fetch leaves populated submodule refs unchanged" {
  local child="$BATS_TEST_TMPDIR/child" parent="$BATS_TEST_TMPDIR/parent" checkout="$BATS_TEST_TMPDIR/checkout"
  git init -q "$child"
  git -C "$child" symbolic-ref HEAD refs/heads/main
  advance_ref "$child" refs/heads/main initial >/dev/null
  git init -q "$parent"
  git -C "$parent" symbolic-ref HEAD refs/heads/main
  git -c protocol.file.allow=always -C "$parent" submodule add -q "$child" child
  local tree commit refs wanted
  tree=$(git -C "$parent" write-tree)
  commit=$(printf 'parent\n' | git -C "$parent" commit-tree "$tree")
  git -C "$parent" update-ref refs/heads/main "$commit"
  git -c protocol.file.allow=always clone -q --recurse-submodules "$parent" "$checkout"
  git -C "$checkout" config fetch.recurseSubmodules true
  refs=$(git -C "$checkout/child" show-ref)
  wanted=$(advance_ref "$child" refs/heads/main update)
  git -C "$parent" update-index --cacheinfo "160000,$wanted,child"
  tree=$(git -C "$parent" write-tree)
  commit=$(printf 'parent update\n' | git -C "$parent" commit-tree "$tree" -p HEAD)
  git -C "$parent" update-ref refs/heads/main "$commit"
  origin="$parent" probe="$checkout"
  _resolve_git
  [ "$status" = update ]
  [ "$(git -C "$checkout/child" show-ref)" = "$refs" ]
}

@test "first-host external materialization resolves current without another approval" {
  export DOTFILES_PACKAGE_PLAN="$BATS_TEST_TMPDIR/plan" DOTFILES_ASSUME_YES=0
  export DOTFILES_TTY="$BATS_TEST_TMPDIR/no-terminal"
  probe="$BATS_TEST_TMPDIR/new-external" source=git-external
  _resolve_git
  [ "$status" = check ]
  printf 'git-external\tsample\tcheck\tfloating\t%s\t%s\t-\t-\tresolve after materialization\n' "$REMOTE" "$probe" >"$DOTFILES_PACKAGE_PLAN"
  local wanted
  wanted=$(advance_ref "$REMOTE" refs/heads/main newer)
  git clone -q "$REMOTE" "$probe"
  run package_plan_resolve_deferred_git
  [ "$status" -eq 0 ]
  [[ "$output" == *'Install plan'* ]]
  [[ "$output" != *'Installed (1)'* ]]
  [ "$(package_plan_field git-external sample 3)" = installed ]
  [ "$(package_target git-external sample)" = "$wanted" ]
  [ ! -e "$DOTFILES_TTY" ]
}

@test "a blocked-only deferred plan displays failure without asking approval" {
  export DOTFILES_ASSUME_YES=0 DOTFILES_TTY="$BATS_TEST_TMPDIR/no-terminal"
  local plan="$BATS_TEST_TMPDIR/blocked-plan"
  printf 'git-runtime\tsample\tblocked\tfloating\torigin\tpath\t-\t-\tlookup failed\n' >"$plan"
  run package_plan_confirm "$plan" deferred
  [ "$status" -eq 0 ]
  [[ "$output" == *'Could not check (1)'* ]]
  [ ! -e "$DOTFILES_TTY" ]
}
