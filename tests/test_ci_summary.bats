#!/usr/bin/env bats

setup() {
    export REPO_ROOT
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export SUMMARY_FILE="$BATS_TEST_TMPDIR/deployment-summary.md"
}

@test "deployment summary reports every successful phase" {
    run env \
        TRIXIE_BUILD=success \
        TRIXIE_INSTALL=success \
        TRIXIE_SMOKE=success \
        MACOS_BUILD=success \
        MACOS_INSTALL=success \
        MACOS_SMOKE=success \
        "$REPO_ROOT/.github/scripts/render-deployment-summary.sh" "$SUMMARY_FILE"

    [ "$status" -eq 0 ]
    [ "$(grep -o ':white_check_mark: passed' "$SUMMARY_FILE" | wc -l | tr -d ' ')" -eq 8 ]
    grep -F '| Debian Trixie |' "$SUMMARY_FILE"
    grep -F '| macOS |' "$SUMMARY_FILE"
}

@test "deployment summary preserves failed and skipped phase outcomes" {
    run env \
        TRIXIE_BUILD=success \
        TRIXIE_INSTALL=failure \
        TRIXIE_SMOKE=skipped \
        MACOS_BUILD=cancelled \
        MACOS_INSTALL= \
        MACOS_SMOKE=success \
        "$REPO_ROOT/.github/scripts/render-deployment-summary.sh" "$SUMMARY_FILE"

    [ "$status" -eq 0 ]
    grep -F ':x: failed' "$SUMMARY_FILE"
    grep -F ':fast_forward: skipped' "$SUMMARY_FILE"
    grep -F ':warning: cancelled' "$SUMMARY_FILE"
    grep -F ':warning: unavailable' "$SUMMARY_FILE"
    [ "$(grep -c ':warning: incomplete' "$SUMMARY_FILE")" -eq 1 ]
}
