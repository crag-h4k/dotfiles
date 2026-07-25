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

@test "GitHub CLI deb822 source uses the stable suite and canonical keyring" {
  run render_deb822_source \
    "https://cli.github.com/packages" \
    "stable" \
    "/etc/apt/keyrings/githubcli-archive-keyring.gpg" \
    "amd64"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Suites: stable"* ]]
  [[ "$output" == *"Signed-By: /etc/apt/keyrings/githubcli-archive-keyring.gpg"* ]]
}

@test "Debian repository management reuses an active host Deb822 definition" {
  local stub_dir apt_root sudo_log curl_log external_source
  stub_dir="${BATS_TEST_TMPDIR}/external-stubs"
  apt_root="${BATS_TEST_TMPDIR}/external-root"
  sudo_log="${BATS_TEST_TMPDIR}/external-sudo.log"
  curl_log="${BATS_TEST_TMPDIR}/external-curl.log"
  external_source="$apt_root/etc/apt/sources.list.d/apt.sources"
  mkdir -p "$stub_dir" "$(dirname "$external_source")" "$apt_root/usr/share/keyrings"
  printf '%s\n' \
    'Types: deb' \
    'URIs: https://cli.github.com/packages/' \
    'Suites: stable' \
    'Components: main' \
    'Signed-By: /usr/share/keyrings/githubcli-archive-keyring.gpg' \
    >"$external_source"
  printf 'existing key\n' >"$apt_root/usr/share/keyrings/githubcli-archive-keyring.gpg"

  cat >"$stub_dir/sudo" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$DOTFILES_SUDO_LOG"
exit 91
STUB
  cat >"$stub_dir/curl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$DOTFILES_CURL_LOG"
exit 92
STUB
  chmod +x "$stub_dir/sudo" "$stub_dir/curl"

  run env PATH="$stub_dir:$PATH" \
    DOTFILES_APT_ROOT="$apt_root" DOTFILES_APT_ARCH=arm64 \
    DOTFILES_SUDO_LOG="$sudo_log" DOTFILES_CURL_LOG="$curl_log" \
    bash -c "source '$REPO_ROOT/scripts/common.sh'; ensure_gh_apt_repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GitHub CLI apt repo already configured elsewhere"* ]]
  [ ! -e "$apt_root/etc/apt/sources.list.d/github-cli.sources" ]
  [ ! -e "$sudo_log" ]
  [ ! -e "$curl_log" ]
}

@test "Debian repository management removes its duplicate beside a host definition" {
  local stub_dir apt_root sudo_log curl_log external_source managed_source
  stub_dir="${BATS_TEST_TMPDIR}/duplicate-stubs"
  apt_root="${BATS_TEST_TMPDIR}/duplicate-root"
  sudo_log="${BATS_TEST_TMPDIR}/duplicate-sudo.log"
  curl_log="${BATS_TEST_TMPDIR}/duplicate-curl.log"
  external_source="$apt_root/etc/apt/sources.list.d/apt.sources"
  managed_source="$apt_root/etc/apt/sources.list.d/github-cli.sources"
  mkdir -p "$stub_dir" "$(dirname "$external_source")"
  printf '%s\n' \
    'Types: deb' \
    'URIs: https://cli.github.com/packages/' \
    'Suites: stable' \
    'Components: main' \
    'Signed-By: /usr/share/keyrings/githubcli-archive-keyring.gpg' \
    >"$external_source"
  render_deb822_source \
    "https://cli.github.com/packages" \
    "stable" \
    "/etc/apt/keyrings/githubcli-archive-keyring.gpg" \
    "arm64" >"$managed_source"

  cat >"$stub_dir/sudo" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$DOTFILES_SUDO_LOG"
exec "$@"
STUB
  cat >"$stub_dir/curl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$DOTFILES_CURL_LOG"
exit 92
STUB
  chmod +x "$stub_dir/sudo" "$stub_dir/curl"

  run env PATH="$stub_dir:$PATH" \
    DOTFILES_APT_ROOT="$apt_root" DOTFILES_APT_ARCH=arm64 \
    DOTFILES_SUDO_LOG="$sudo_log" DOTFILES_CURL_LOG="$curl_log" \
    bash -c "source '$REPO_ROOT/scripts/common.sh'; ensure_gh_apt_repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"removing duplicate managed source"* ]]
  [ -f "$external_source" ]
  [ ! -e "$managed_source" ]
  [ "$(wc -l <"$sudo_log")" -eq 1 ]
  grep -Fq "rm -f -- $managed_source" "$sudo_log"
  [ ! -e "$curl_log" ]
}

@test "Debian repository management ignores disabled external definitions" {
  local stub_dir apt_root sudo_log curl_log external_source managed_source
  stub_dir="${BATS_TEST_TMPDIR}/disabled-stubs"
  apt_root="${BATS_TEST_TMPDIR}/disabled-root"
  sudo_log="${BATS_TEST_TMPDIR}/disabled-sudo.log"
  curl_log="${BATS_TEST_TMPDIR}/disabled-curl.log"
  external_source="$apt_root/etc/apt/sources.list.d/disabled.sources"
  managed_source="$apt_root/etc/apt/sources.list.d/github-cli.sources"
  mkdir -p "$stub_dir" "$(dirname "$external_source")"
  printf '%s\n' \
    'Types: deb' \
    'URIs: https://cli.github.com/packages' \
    'Suites: stable' \
    'Components: main' \
    'Signed-By: /usr/share/keyrings/githubcli-archive-keyring.gpg' \
    'Enabled: no' \
    >"$external_source"

  cat >"$stub_dir/sudo" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$DOTFILES_SUDO_LOG"
exec "$@"
STUB
  cat >"$stub_dir/curl" <<'STUB'
#!/bin/sh
out=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out=$2; shift 2 ;;
        -*) shift ;;
        *) shift ;;
    esac
done
printf '%s\n' "$*" >>"$DOTFILES_CURL_LOG"
printf 'stub signing key\n' >"$out"
STUB
  chmod +x "$stub_dir/sudo" "$stub_dir/curl"

  run env PATH="$stub_dir:$PATH" \
    DOTFILES_APT_ROOT="$apt_root" DOTFILES_APT_ARCH=arm64 \
    DOTFILES_SUDO_LOG="$sudo_log" DOTFILES_CURL_LOG="$curl_log" \
    bash -c "source '$REPO_ROOT/scripts/common.sh'; ensure_gh_apt_repo"
  [ "$status" -eq 0 ]
  [ -f "$managed_source" ]
  grep -q '^Signed-By: /etc/apt/keyrings/githubcli-archive-keyring.gpg$' "$managed_source"
  [ "$(wc -l <"$sudo_log")" -eq 3 ]
}

@test "Debian repository management uses stubbed privilege and is idempotent" {
  local stub_dir apt_root sudo_log curl_log
  stub_dir="${BATS_TEST_TMPDIR}/apt-stubs"
  apt_root="${BATS_TEST_TMPDIR}/apt-root"
  sudo_log="${BATS_TEST_TMPDIR}/sudo.log"
  curl_log="${BATS_TEST_TMPDIR}/curl.log"
  mkdir -p "$stub_dir"

  cat >"$stub_dir/sudo" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$DOTFILES_SUDO_LOG"
exec "$@"
STUB
  cat >"$stub_dir/curl" <<'STUB'
#!/bin/sh
out=
url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out=$2; shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
    esac
done
printf '%s\n' "$url" >>"$DOTFILES_CURL_LOG"
printf 'stub signing key for %s\n' "$url" >"$out"
STUB
  chmod +x "$stub_dir/sudo" "$stub_dir/curl"

  run env PATH="$stub_dir:$PATH" \
    DOTFILES_APT_ROOT="$apt_root" DOTFILES_APT_ARCH=arm64 \
    DOTFILES_SUDO_LOG="$sudo_log" DOTFILES_CURL_LOG="$curl_log" \
    bash -c \
    "source '$REPO_ROOT/scripts/common.sh'; ensure_gh_apt_repo; ensure_nodesource_apt_repo; ensure_trivy_apt_repo"
  [ "$status" -eq 0 ]

  [ -f "$apt_root/etc/apt/sources.list.d/github-cli.sources" ]
  [ -f "$apt_root/etc/apt/sources.list.d/nodesource.sources" ]
  [ -f "$apt_root/etc/apt/sources.list.d/trivy.sources" ]
  grep -q '^URIs: https://cli.github.com/packages$' \
    "$apt_root/etc/apt/sources.list.d/github-cli.sources"
  grep -q '^Suites: nodistro$' \
    "$apt_root/etc/apt/sources.list.d/nodesource.sources"
  grep -q '^Suites: generic$' \
    "$apt_root/etc/apt/sources.list.d/trivy.sources"
  [ "$(awk '$0 == "Architectures: arm64" { count++ } END { print count + 0 }' \
    "$apt_root"/etc/apt/sources.list.d/*.sources)" -eq 3 ]
  [ "$(wc -l <"$sudo_log")" -eq 9 ]
  [ "$(wc -l <"$curl_log")" -eq 3 ]

  rm -f "$sudo_log" "$curl_log"
  run env PATH="$stub_dir:$PATH" \
    DOTFILES_APT_ROOT="$apt_root" DOTFILES_APT_ARCH=arm64 \
    DOTFILES_SUDO_LOG="$sudo_log" DOTFILES_CURL_LOG="$curl_log" \
    bash -c \
    "source '$REPO_ROOT/scripts/common.sh'; ensure_gh_apt_repo; ensure_nodesource_apt_repo; ensure_trivy_apt_repo"
  [ "$status" -eq 0 ]
  [ ! -e "$sudo_log" ]
  [ ! -e "$curl_log" ]
}

@test "Debian repository management repairs a drifted canonical source through stubs" {
  local stub_dir apt_root sudo_log curl_log source_file
  stub_dir="${BATS_TEST_TMPDIR}/apt-repair-stubs"
  apt_root="${BATS_TEST_TMPDIR}/apt-repair-root"
  sudo_log="${BATS_TEST_TMPDIR}/repair-sudo.log"
  curl_log="${BATS_TEST_TMPDIR}/repair-curl.log"
  source_file="$apt_root/etc/apt/sources.list.d/nodesource.sources"
  mkdir -p "$stub_dir" "$(dirname "$source_file")" "$apt_root/etc/apt/keyrings"
  printf 'stale\n' >"$source_file"
  printf 'old key\n' >"$apt_root/etc/apt/keyrings/nodesource.asc"

  cat >"$stub_dir/sudo" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$DOTFILES_SUDO_LOG"
exec "$@"
STUB
  cat >"$stub_dir/curl" <<'STUB'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out=$2; shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
    esac
done
printf '%s\n' "$url" >>"$DOTFILES_CURL_LOG"
printf 'replacement key\n' >"$out"
STUB
  chmod +x "$stub_dir/sudo" "$stub_dir/curl"

  run env PATH="$stub_dir:$PATH" \
    DOTFILES_APT_ROOT="$apt_root" DOTFILES_APT_ARCH=amd64 \
    DOTFILES_SUDO_LOG="$sudo_log" DOTFILES_CURL_LOG="$curl_log" \
    bash -c \
    "source '$REPO_ROOT/scripts/common.sh'; ensure_nodesource_apt_repo"
  [ "$status" -eq 0 ]
  grep -q '^URIs: https://deb.nodesource.com/node_24.x$' "$source_file"
  [ "$(wc -l <"$sudo_log")" -eq 3 ]
  [ "$(wc -l <"$curl_log")" -eq 1 ]
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

@test "development package plan owns cross-platform CLIs without Gitleaks or Hadolint" {
  local planner="$REPO_ROOT/scripts/package-plan.sh"

  run env DOTFILES_PLAN_OS=debian DOTFILES_PLAN_ASSUME_MISSING=1 \
    INSTALL_NEOVIM=true bash "$planner" --records
  [ "$status" -eq 0 ]
  [[ "$output" == *$'apt\tnodejs\tplanned\tNodeSource Node.js 24 apt repository'* ]]
  [[ "$output" == *$'apt\ttrivy\tplanned\tAqua Security apt repository'* ]]
  [[ "$output" == *$'github-release\ttflint\tplanned\t'* ]]
  [[ "$output" == *$'github-release\ttenv\tplanned\t'* ]]
  [[ "$output" == *$'npm\tmarkdownlint-cli2\tplanned\t'* ]]
  [[ "$output" == *$'apt\tshellcheck\tplanned\t'* ]]
  [[ "$output" == *$'apt\tyamllint\tplanned\t'* ]]
  [[ "$output" == *$'luarocks\tluacheck\tplanned\t'* ]]
  [[ "$output" != *$'apt\tnpm\t'* ]]
  [[ "$output" != *$'\tgitleaks\t'* ]]
  [[ "$output" != *$'\thadolint\t'* ]]

  run env DOTFILES_PLAN_OS=macos DOTFILES_PLAN_ASSUME_MISSING=1 \
    INSTALL_NEOVIM=true bash "$planner" --records
  [ "$status" -eq 0 ]
  [[ "$output" == *$'brew-formula\tmarkdownlint-cli2\tplanned\t'* ]]
  [[ "$output" == *$'brew-formula\tshellcheck\tplanned\t'* ]]
  [[ "$output" == *$'brew-formula\ttenv\tplanned\t'* ]]
  [[ "$output" == *$'brew-formula\ttrivy\tplanned\t'* ]]
  [[ "$output" == *$'brew-formula\tyamllint\tplanned\t'* ]]
  [[ "$output" == *$'brew-formula\tterraform-linters/tap/tflint\tplanned\t'* ]]
  [[ "$output" == *$'luarocks\tluacheck\tplanned\t'* ]]
  [[ "$output" != *$'\tgitleaks\t'* ]]
  [[ "$output" != *$'\thadolint\t'* ]]
}

@test "Neovim uses modern LSP activation and reserves Mason tooling for Gitleaks" {
  local init="$REPO_ROOT/dot_config/nvim/init.lua"
  local scanner="$REPO_ROOT/dot_config/nvim/lua/gitleaks.lua"

  grep -Fq 'vim.lsp.config("*"' "$init"
  grep -Fq 'vim.lsp.config("lua_ls"' "$init"
  grep -Fq 'vim.lsp.enable(lsp_servers)' "$init"
  grep -Fq '"docker_language_server"' "$init"
  grep -Fq 'ensure_installed = lsp_servers' "$init"
  run grep -Fq 'vim.lsp.start(' "$init"
  [ "$status" -ne 0 ]
  run grep -Fq 'lspconfig.configs.' "$init"
  [ "$status" -ne 0 ]

  grep -Fq 'registry.get_package, "gitleaks"' "$init"
  run grep -Fq 'registry.get_package, "markdownlint-cli2"' "$init"
  [ "$status" -ne 0 ]
  grep -Fq '"BufReadPost", "BufWritePost"' "$scanner"
  grep -Fq 'vim.bo[bufnr].buftype ~= ""' "$scanner"
  grep -Fq -- '"--redact"' "$scanner"
  grep -Fq '.gitleaks.toml' "$scanner"
}

@test "Gitleaks policy extends defaults and lazy lock state stays untracked" {
  grep -Fq 'useDefault = true' "$REPO_ROOT/.gitleaks.toml"
  grep -Fq '[[allowlists]]' "$REPO_ROOT/.gitleaks.toml"
  grep -Fxq 'lazy-lock.json' "$REPO_ROOT/.gitignore"

  grep -Fq 'repo: https://github.com/gitleaks/gitleaks' "$REPO_ROOT/.pre-commit-config.yaml"
  grep -Fq 'rev: v8.30.1' "$REPO_ROOT/.pre-commit-config.yaml"
  grep -Fq 'args: [--redact]' "$REPO_ROOT/.pre-commit-config.yaml"
}
