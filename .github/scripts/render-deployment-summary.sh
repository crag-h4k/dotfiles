#!/usr/bin/env bash
# Render one sticky PR comment summarizing every required CI gate: PR metadata,
# pre-commit, and the build/install/smoke phases for both deployment
# environments. One always-current table so a red gate (for example PR metadata)
# shows up in the comment, not only in the checks list, and the body changes with
# each run instead of sitting on an all-green deployment view.
set -euo pipefail

[[ "$#" -eq 1 ]] || {
    printf 'usage: render-deployment-summary.sh OUTPUT_FILE\n' >&2
    exit 1
}

format_status() {
    case "$1" in
        success) printf ':white_check_mark: passed' ;;
        failure) printf ':x: failed' ;;
        skipped) printf ':fast_forward: skipped' ;;
        cancelled) printf ':warning: cancelled' ;;
        *) printf ':grey_question: unavailable' ;;
    esac
}

# Roll a deployment environment's build/install/smoke phases into one verdict.
overall_status() {
    if [[ "$1" == success && "$2" == success && "$3" == success ]]; then
        printf ':white_check_mark: passed'
    elif [[ "$1" == failure || "$2" == failure || "$3" == failure ]]; then
        printf ':x: failed'
    elif [[ "$1" == cancelled || "$2" == cancelled || "$3" == cancelled ]]; then
        printf ':warning: cancelled'
    else
        printf ':warning: incomplete'
    fi
}

output_file="$1"
{
    printf '### CI summary\n\n'
    printf '| Gate | Result |\n'
    printf '| --- | --- |\n'
    printf '| PR metadata | %s |\n' "$(format_status "${PR_METADATA_RESULT:-}")"
    printf '| pre-commit | %s |\n' "$(format_status "${PRE_COMMIT_RESULT:-}")"
    printf '| Debian Trixie | %s |\n' \
        "$(overall_status "${TRIXIE_BUILD:-}" "${TRIXIE_INSTALL:-}" "${TRIXIE_SMOKE:-}")"
    printf '| macOS | %s |\n' \
        "$(overall_status "${MACOS_BUILD:-}" "${MACOS_INSTALL:-}" "${MACOS_SMOKE:-}")"

    printf '\n#### Deployment phases\n\n'
    printf '| Environment | Build | Install | Smoke test |\n'
    printf '| --- | --- | --- | --- |\n'
    printf '| Debian Trixie | %s | %s | %s |\n' \
        "$(format_status "${TRIXIE_BUILD:-}")" \
        "$(format_status "${TRIXIE_INSTALL:-}")" \
        "$(format_status "${TRIXIE_SMOKE:-}")"
    printf '| macOS | %s | %s | %s |\n' \
        "$(format_status "${MACOS_BUILD:-}")" \
        "$(format_status "${MACOS_INSTALL:-}")" \
        "$(format_status "${MACOS_SMOKE:-}")"

    if [[ -n "${GITHUB_SERVER_URL:-}" &&
        -n "${GITHUB_REPOSITORY:-}" &&
        -n "${GITHUB_RUN_ID:-}" ]]; then
        printf '\n[Open the workflow run](%s/%s/actions/runs/%s)\n' \
            "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID"
    fi
} >"$output_file"
