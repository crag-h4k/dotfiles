#!/usr/bin/env bats

setup() {
    export REPO_ROOT
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export SUMMARY_FILE="$BATS_TEST_TMPDIR/deployment-summary.md"
}

@test "CI summary reports every gate and phase on a clean run" {
    run env \
        PR_METADATA_RESULT=success \
        PRE_COMMIT_RESULT=success \
        TRIXIE_BUILD=success \
        TRIXIE_INSTALL=success \
        TRIXIE_SMOKE=success \
        MACOS_BUILD=success \
        MACOS_INSTALL=success \
        MACOS_SMOKE=success \
        "$REPO_ROOT/.github/scripts/render-deployment-summary.sh" "$SUMMARY_FILE"

    [ "$status" -eq 0 ]
    # 4 gate verdicts (pr-metadata, pre-commit, trixie, macos) + 6 phase cells.
    [ "$(grep -o ':white_check_mark: passed' "$SUMMARY_FILE" | wc -l | tr -d ' ')" -eq 10 ]
    grep -F '| PR metadata |' "$SUMMARY_FILE"
    grep -F '| pre-commit |' "$SUMMARY_FILE"
    grep -F '| Debian Trixie |' "$SUMMARY_FILE"
    grep -F '| macOS |' "$SUMMARY_FILE"
}

@test "CI summary surfaces a failed gate (e.g. PR metadata) even when deployments pass" {
    run env \
        PR_METADATA_RESULT=failure \
        PRE_COMMIT_RESULT=success \
        TRIXIE_BUILD=success \
        TRIXIE_INSTALL=success \
        TRIXIE_SMOKE=success \
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
        PRE_COMMIT_RESULT=success \
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
    grep -F ':grey_question: unavailable' "$SUMMARY_FILE"
    # Trixie rolls up to failed (a failing phase); macOS rolls up to cancelled.
    grep -F '| Debian Trixie | :x: failed |' "$SUMMARY_FILE"
    grep -F '| macOS | :warning: cancelled |' "$SUMMARY_FILE"
}
