#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/scripts/common.sh"
}

@test "NodeSource deb822 source uses Node 24 nodistro" {
  run render_deb822_source \
    "https://deb.nodesource.com/node_24.x" \
    "nodistro" \
    "/etc/apt/keyrings/nodesource.asc" \
    "arm64"

  [ "$status" -eq 0 ]
  [ "$output" = "Types: deb
URIs: https://deb.nodesource.com/node_24.x
Suites: nodistro
Components: main
Architectures: arm64
Signed-By: /etc/apt/keyrings/nodesource.asc" ]
}

@test "Trivy deb822 source uses the generic suite" {
  run render_deb822_source \
    "https://aquasecurity.github.io/trivy-repo/deb" \
    "generic" \
    "/etc/apt/keyrings/trivy.asc" \
    "amd64"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Suites: generic"* ]]
  [[ "$output" == *"Architectures: amd64"* ]]
}

@test "release architecture mappings cover Debian amd64 and arm64" {
  [ "$(tflint_release_arch x86_64)" = "amd64" ]
  [ "$(tflint_release_arch aarch64)" = "arm64" ]
  [ "$(tenv_release_arch x86_64)" = "x86_64" ]
  [ "$(tenv_release_arch aarch64)" = "arm64" ]
  run ! tflint_release_arch riscv64
  run ! tenv_release_arch riscv64
}

@test "release checksum verification accepts the selected asset only" {
  local tmp_dir asset
  tmp_dir=$(mktemp -d)
  asset="tool_linux_arm64.tar.gz"
  printf 'verified payload\n' > "$tmp_dir/$asset"
  (
    cd "$tmp_dir"
    sha256sum "$asset" > checksums.txt
    printf '%064d  unrelated.zip\n' 0 >> checksums.txt
  )

  run verify_release_checksum "$tmp_dir" checksums.txt "$asset"
  rm -rf "$tmp_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"$asset: OK"* ]]
}

@test "Node major verification requires Node 24" {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  printf '#!/usr/bin/env sh\nprintf "v24.18.0\\n"\n' > "$tmp_dir/node"
  chmod +x "$tmp_dir/node"

  PATH="$tmp_dir:$PATH" run verify_node_major 24
  [ "$status" -eq 0 ]

  PATH="$tmp_dir:$PATH" run verify_node_major 22
  rm -rf "$tmp_dir"
  [ "$status" -ne 0 ]
}

@test "development package plan uses NodeSource, Trivy, TFLint, and tenv without Hadolint" {
  local planner="$REPO_ROOT/scripts/package-plan.sh"

  run env DOTFILES_PLAN_OS=debian DOTFILES_PLAN_ASSUME_MISSING=1 \
    INSTALL_NEOVIM=true bash "$planner" --records
  [ "$status" -eq 0 ]
  [[ "$output" == *$'apt\tnodejs\tplanned\tNodeSource Node.js 24 apt repository'* ]]
  [[ "$output" == *$'apt\ttrivy\tplanned\tAqua Security apt repository'* ]]
  [[ "$output" == *$'github-release\ttflint\tplanned\t'* ]]
  [[ "$output" == *$'github-release\ttenv\tplanned\t'* ]]
  [[ "$output" != *$'apt\tnpm\t'* ]]
  [[ "$output" != *$'\thadolint\t'* ]]

  run env DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1 \
    INSTALL_NEOVIM=true bash "$planner" --records
  [ "$status" -eq 0 ]
  [[ "$output" == *$'brew-formula\ttenv\tplanned\t'* ]]
  [[ "$output" == *$'brew-formula\ttrivy\tplanned\t'* ]]
  [[ "$output" != *$'\thadolint\t'* ]]
}
