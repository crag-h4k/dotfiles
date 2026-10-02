#!/usr/bin/env bats
# shellcheck source-path=SCRIPTDIR

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
    GIT_INDEX_VERSION GIT_CONFIG_PARAMETERS
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=../scripts/common.sh
  source "$ROOT/scripts/common.sh"
  export GIT_AUTHOR_NAME="Dotfiles Test" GIT_AUTHOR_EMAIL="dotfiles@example.invalid"
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
  SOURCE="$BATS_TEST_TMPDIR/source"
  REMOTE="$BATS_TEST_TMPDIR/palette"
  git init -q "$REMOTE"
  mkdir "$REMOTE/base16"
  printf 'scheme: Fixture\n' >"$REMOTE/base16/fixture.yaml"
  git -C "$REMOTE" add base16/fixture.yaml
  commit_tree "$REMOTE"
  git init -q "$SOURCE"
  git -C "$SOURCE" submodule add -q "$REMOTE" vendor/tinted-schemes
  commit_tree "$SOURCE"
}

commit_tree() {
  local tree commit
  tree=$(git -C "$1" write-tree)
  commit=$(printf 'fixture\n' | git -C "$1" commit-tree "$tree")
  git -C "$1" update-ref HEAD "$commit"
}

@test "current pinned palette is checked without changing either index" {
  local source_index palette_index
  touch -t 202001010000 "$SOURCE/vendor/tinted-schemes/base16/fixture.yaml"
  source_index=$(cksum "$SOURCE/.git/index")
  palette_index=$(cksum "$SOURCE/.git/modules/vendor/tinted-schemes/index")
  run ensure_pinned_palette "$SOURCE"
  [ "$status" -eq 0 ]
  [[ "$output" == *'already current'* ]]
  [ "$(cksum "$SOURCE/.git/index")" = "$source_index" ]
  [ "$(cksum "$SOURCE/.git/modules/vendor/tinted-schemes/index")" = "$palette_index" ]
}

@test "shared source and submodule trust is scoped to canonical read commands" {
  local link="$BATS_TEST_TMPDIR/source-link" config_before
  ln -s "$SOURCE" "$link"
  config_before=$(cksum "$SOURCE/.git/config")
  export GIT_TEST_ASSUME_DIFFERENT_OWNER=1
  run ensure_pinned_palette "$link"
  [ "$status" -eq 0 ]
  [[ "$output" == *'already current'* ]]
  [ "$(cksum "$SOURCE/.git/config")" = "$config_before" ]
}

@test "owner initializes a missing palette at the pinned commit" {
  local clone="$BATS_TEST_TMPDIR/clone" expected
  expected=$(git -C "$SOURCE/vendor/tinted-schemes" rev-parse HEAD)
  git clone -q "$SOURCE" "$clone"
  run ensure_pinned_palette "$clone"
  [ "$status" -eq 0 ]
  [ "$(git -C "$clone/vendor/tinted-schemes" rev-parse HEAD)" = "$expected" ]
  [ -f "$clone/vendor/tinted-schemes/base16/fixture.yaml" ]
}

@test "existing palette edits remain untouched at the pinned commit" {
  printf 'scheme: Local edit\n' >"$SOURCE/vendor/tinted-schemes/base16/fixture.yaml"
  run ensure_pinned_palette "$SOURCE"
  [ "$status" -eq 0 ]
  [[ "$output" == *'already current'* ]]
  [ "$(cat "$SOURCE/vendor/tinted-schemes/base16/fixture.yaml")" = 'scheme: Local edit' ]
}

@test "missing tracked palette files are not accepted as a complete checkout" {
  rm "$SOURCE/vendor/tinted-schemes/base16/fixture.yaml"
  run ensure_pinned_palette "$SOURCE"
  [ "$status" -ne 0 ]
  [[ "$output" == *'missing files or an unexpected commit'* ]]
  [ ! -e "$SOURCE/vendor/tinted-schemes/base16/fixture.yaml" ]
}
