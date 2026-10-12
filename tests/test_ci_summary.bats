#!/usr/bin/env bats
# tests/test_ci_summary.bats

setup() {
    export REPO_ROOT
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export SUMMARY_FILE="$BATS_TEST_TMPDIR/deployment-summary.md"
}

@test "CI summary reports every gate and phase on a clean run" {
    run env \
        PR_METADATA_RESULT=success \
        PREK_RESULT=success \
        TRIXIE_BUILD=success \
        TRIXIE_INSTALL=success \
        TRIXIE_SMOKE=success \
        TRIXIE_ARM64_BUILD=success \
        TRIXIE_ARM64_INSTALL=success \
        TRIXIE_ARM64_SMOKE=success \
        MACOS_BUILD=success \
        MACOS_INSTALL=success \
        MACOS_SMOKE=success \
        "$REPO_ROOT/.github/scripts/render-deployment-summary.sh" "$SUMMARY_FILE"

    [ "$status" -eq 0 ]
    # Five gate verdicts plus nine deployment phase cells.
    [ "$(grep -o ':white_check_mark: passed' "$SUMMARY_FILE" | wc -l | tr -d ' ')" -eq 14 ]
    grep -F '| PR metadata |' "$SUMMARY_FILE"
    grep -F '| prek |' "$SUMMARY_FILE"
    grep -F '| Debian Trixie x86-64 |' "$SUMMARY_FILE"
    grep -F '| Debian Trixie ARM64 |' "$SUMMARY_FILE"
    grep -F '| macOS ARM64 |' "$SUMMARY_FILE"
}

@test "CI summary surfaces a failed gate (e.g. PR metadata) even when deployments pass" {
    run env \
        PR_METADATA_RESULT=failure \
        PREK_RESULT=success \
        TRIXIE_BUILD=success \
        TRIXIE_INSTALL=success \
        TRIXIE_SMOKE=success \
        TRIXIE_ARM64_BUILD=success \
        TRIXIE_ARM64_INSTALL=success \
        TRIXIE_ARM64_SMOKE=success \
        MACOS_BUILD=success \
        MACOS_INSTALL=success \
        MACOS_SMOKE=success \
        "$REPO_ROOT/.github/scripts/render-deployment-summary.sh" "$SUMMARY_FILE"

    [ "$status" -eq 0 ]
    grep -F '| PR metadata | :x: failed |' "$SUMMARY_FILE"
}

@test "CI summary preserves failed, skipped, cancelled, and unavailable outcomes" {
    run env \
        PR_METADATA_RESULT=success \
        PREK_RESULT=failure \
        TRIXIE_BUILD=success \
        TRIXIE_INSTALL=failure \
        TRIXIE_SMOKE=skipped \
        TRIXIE_ARM64_BUILD=success \
        TRIXIE_ARM64_INSTALL=success \
        TRIXIE_ARM64_SMOKE=success \
        MACOS_BUILD=cancelled \
        MACOS_INSTALL= \
        MACOS_SMOKE=success \
        "$REPO_ROOT/.github/scripts/render-deployment-summary.sh" "$SUMMARY_FILE"

    [ "$status" -eq 0 ]
    grep -F '| prek | :x: failed |' "$SUMMARY_FILE"
    grep -F ':x: failed' "$SUMMARY_FILE"
    grep -F ':fast_forward: skipped' "$SUMMARY_FILE"
    grep -F ':warning: cancelled' "$SUMMARY_FILE"
    grep -F ':grey_question: unavailable' "$SUMMARY_FILE"
    # Trixie rolls up to failed (a failing phase); macOS rolls up to cancelled.
    grep -F '| Debian Trixie x86-64 | :x: failed |' "$SUMMARY_FILE"
    grep -F '| Debian Trixie ARM64 | :white_check_mark: passed |' "$SUMMARY_FILE"
    grep -F '| macOS ARM64 | :warning: cancelled |' "$SUMMARY_FILE"
}

@test "CI summary reports an ARM64 failure separately from successful x86-64" {
    run env PR_METADATA_RESULT=success PREK_RESULT=success \
        TRIXIE_BUILD=success TRIXIE_INSTALL=success TRIXIE_SMOKE=success \
        TRIXIE_ARM64_BUILD=success TRIXIE_ARM64_INSTALL=failure TRIXIE_ARM64_SMOKE=skipped \
        MACOS_BUILD=success MACOS_INSTALL=success MACOS_SMOKE=success \
        "$REPO_ROOT/.github/scripts/render-deployment-summary.sh" "$SUMMARY_FILE"
    [ "$status" -eq 0 ]
    grep -F '| Debian Trixie x86-64 | :white_check_mark: passed |' "$SUMMARY_FILE"
    grep -F '| Debian Trixie ARM64 | :x: failed |' "$SUMMARY_FILE"
    grep -F '| macOS ARM64 | :white_check_mark: passed |' "$SUMMARY_FILE"
}

setup_macos_runner() {
    export TEST_BREW_PREFIX="$BATS_TEST_TMPDIR/brew" BREW_LOG="$BATS_TEST_TMPDIR/brew.log"
    mkdir -p "$TEST_BREW_PREFIX/bin" "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/uname" <<'STUB'
#!/bin/sh
case "$1" in
    -s) printf '%s\n' "${TEST_SYSTEM:-Darwin}" ;;
    -m) printf '%s\n' "${TEST_MACHINE:-arm64}" ;;
esac
STUB
    cat >"$BATS_TEST_TMPDIR/bin/brew" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$BREW_LOG"
case "$1" in
    --prefix) printf '%s\n' "$TEST_BREW_PREFIX" ;;
    unlink)
        [ "${TEST_UNLINK_RESULT:-0}" -eq 0 ] || exit "$TEST_UNLINK_RESULT"
        case "${TEST_UNLINK_EFFECT:-none}" in
            remove) rm "$TEST_BREW_PREFIX/bin/openssl" ;;
            replace)
                rm "$TEST_BREW_PREFIX/bin/openssl"
                ln -s "$TEST_BREW_PREFIX/opt/openssl@3/bin/openssl" "$TEST_BREW_PREFIX/bin/openssl"
                ;;
            none) printf '0 symlinks removed\n' ;;
        esac
        ;;
esac
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/uname" "$BATS_TEST_TMPDIR/bin/brew"
}

@test "macOS CI removes the exact stale runner link when Homebrew removes zero symlinks" {
    setup_macos_runner
    mkdir -p "$TEST_BREW_PREFIX/opt/openssl@1.1/bin"
    printf 'legacy OpenSSL binary\n' >"$TEST_BREW_PREFIX/opt/openssl@1.1/bin/openssl"
    ln -s "$TEST_BREW_PREFIX/opt/openssl@1.1/bin/openssl" "$TEST_BREW_PREFIX/bin/openssl"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" GITHUB_ACTIONS=true \
        "$REPO_ROOT/.github/scripts/prepare-macos-runner.sh"
    [ "$status" -eq 0 ]
    [ "$(cat "$BREW_LOG")" = "untap aws/tap
--prefix
unlink openssl@1.1" ]
    [[ "$output" == *'0 symlinks removed'* ]]
    [ ! -L "$TEST_BREW_PREFIX/bin/openssl" ]
    [ "$(cat "$TEST_BREW_PREFIX/opt/openssl@1.1/bin/openssl")" = 'legacy OpenSSL binary' ]
}

@test "macOS CI accepts a successful Homebrew unlink without a leftover link" {
    setup_macos_runner
    ln -s "$TEST_BREW_PREFIX/opt/openssl@1.1/bin/openssl" "$TEST_BREW_PREFIX/bin/openssl"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" GITHUB_ACTIONS=true TEST_UNLINK_EFFECT=remove \
        "$REPO_ROOT/.github/scripts/prepare-macos-runner.sh"
    [ "$status" -eq 0 ]
    [ ! -L "$TEST_BREW_PREFIX/bin/openssl" ]
    [[ "$output" != *'Removing stale runner link'* ]]
}

@test "macOS CI rechecks the target after Homebrew replaces the link" {
    setup_macos_runner
    ln -s "$TEST_BREW_PREFIX/opt/openssl@1.1/bin/openssl" "$TEST_BREW_PREFIX/bin/openssl"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" GITHUB_ACTIONS=true TEST_UNLINK_EFFECT=replace \
        "$REPO_ROOT/.github/scripts/prepare-macos-runner.sh"
    [ "$status" -eq 0 ]
    [ "$(readlink "$TEST_BREW_PREFIX/bin/openssl")" = "$TEST_BREW_PREFIX/opt/openssl@3/bin/openssl" ]
}

@test "macOS CI preserves a regular OpenSSL file or unrelated legacy symlink" {
    setup_macos_runner
    printf 'local OpenSSL binary\n' >"$TEST_BREW_PREFIX/bin/openssl"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" GITHUB_ACTIONS=true \
        "$REPO_ROOT/.github/scripts/prepare-macos-runner.sh"
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_BREW_PREFIX/bin/openssl")" = 'local OpenSSL binary' ]
    rm "$TEST_BREW_PREFIX/bin/openssl"
    local unrelated="$BATS_TEST_TMPDIR/unrelated/openssl@1.1/bin/openssl"
    ln -s "$unrelated" "$TEST_BREW_PREFIX/bin/openssl"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" GITHUB_ACTIONS=true \
        "$REPO_ROOT/.github/scripts/prepare-macos-runner.sh"
    [ "$status" -eq 0 ]
    [ "$(readlink "$TEST_BREW_PREFIX/bin/openssl")" = "$unrelated" ]
    run grep -F unlink "$BREW_LOG"
    [ "$status" -ne 0 ]
}

@test "macOS CI leaves a current OpenSSL 3 link unchanged" {
    setup_macos_runner
    ln -s "$TEST_BREW_PREFIX/opt/openssl@3/bin/openssl" "$TEST_BREW_PREFIX/bin/openssl"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" GITHUB_ACTIONS=true \
        "$REPO_ROOT/.github/scripts/prepare-macos-runner.sh"
    [ "$status" -eq 0 ]
    [ "$(readlink "$TEST_BREW_PREFIX/bin/openssl")" = "$TEST_BREW_PREFIX/opt/openssl@3/bin/openssl" ]
    run grep -F unlink "$BREW_LOG"
    [ "$status" -ne 0 ]
}

@test "macOS runner preparation refuses a workstation or Intel runner before Homebrew" {
    setup_macos_runner
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" GITHUB_ACTIONS=false \
        "$REPO_ROOT/.github/scripts/prepare-macos-runner.sh"
    [ "$status" -eq 1 ]
    [ ! -f "$BREW_LOG" ]
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" GITHUB_ACTIONS=true TEST_MACHINE=x86_64 \
        "$REPO_ROOT/.github/scripts/prepare-macos-runner.sh"
    [ "$status" -eq 1 ]
    [ ! -f "$BREW_LOG" ]
}

@test "macOS runner preparation does not hide a failed OpenSSL unlink" {
    setup_macos_runner
    ln -s "$TEST_BREW_PREFIX/opt/openssl@1.1/bin/openssl" "$TEST_BREW_PREFIX/bin/openssl"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" GITHUB_ACTIONS=true TEST_UNLINK_RESULT=1 \
        "$REPO_ROOT/.github/scripts/prepare-macos-runner.sh"
    [ "$status" -eq 1 ]
    [ "$(readlink "$TEST_BREW_PREFIX/bin/openssl")" = "$TEST_BREW_PREFIX/opt/openssl@1.1/bin/openssl" ]
}

@test "CI declares native Linux coverage and requires both deployment results" {
    run python3 - "$REPO_ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
workflow = (root / ".github/workflows/ci.yaml").read_text()
prek = (root / ".github/workflows/prek.yaml").read_text()
for name, runner, arch, machine in [
    ("trixie-deployment", "ubuntu-24.04", "amd64", "x86_64"),
    ("trixie-arm64-deployment", "ubuntu-24.04-arm", "arm64", "aarch64"),
]:
    job = re.search(rf"(?ms)^  {name}:\n(.*?)(?=^  \S|\Z)", workflow)[1]
    assert f"runner: {runner}\n" in job
    assert f"arch: {arch}\n" in job
    assert f"machine: {machine}\n" in job
for name in ["ci", "ci-summary"]:
    job = re.search(rf"(?ms)^  {name}:\n(.*?)(?=^  \S|\Z)", workflow)[1]
    assert "trixie-arm64-deployment" in job
gate = re.search(r"(?ms)^  ci:\n(.*?)(?=^  \S|\Z)", workflow)[1]
assert 'test "$TRIXIE_ARM64_RESULT" = success' in gate
assert "runs-on: ubuntu-24.04\n" in prek
assert "ubuntu-24.04-arm" not in prek
assert "matrix." not in prek
assert "prek run --show-diff-on-failure --color=never --all-files" in prek
assert "luacheck-${{ runner.os }}-${{ runner.arch }}" in prek
pbvar = (root / ".github/workflows/pbvar-build.yaml").read_text()
for runner in ["ubuntu-24.04", "ubuntu-24.04-arm", "macos-15"]:
    assert f"runner: {runner}\n" in pbvar
assert "fail-fast: false" in pbvar
assert '- ".github/workflows/pbvar-build.yaml"' in pbvar
PY
    [ "$status" -eq 0 ]
}
