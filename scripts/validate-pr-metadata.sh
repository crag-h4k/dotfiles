#!/usr/bin/env bash
# Validate the source branch and squash-merge title used by Release Please.
set -euo pipefail

fail() {
    printf 'PR metadata: %s\n' "$*" >&2
    exit 1
}

branch=${PR_HEAD_REF:-${1:-}}
title=${PR_TITLE:-${2:-}}

[[ -n "$branch" ]] || fail "PR_HEAD_REF is empty"
[[ -n "$title" ]] || fail "PR_TITLE is empty"

case "$branch" in
    release-please--branches--* | dependabot/* | renovate/*)
        printf 'PR metadata: exempt automation branch %s\n' "$branch"
        exit 0
        ;;
    feat/*) expected_type=feat ;;
    fix/* | hotfix/*) expected_type=fix ;;
    deps/*) expected_type=deps ;;
    docs/*) expected_type=docs ;;
    chore/*) expected_type=chore ;;
    ci/*) expected_type=ci ;;
    refactor/*) expected_type=refactor ;;
    *)
        fail "branch '$branch' must start with feat/, fix/, hotfix/, deps/, docs/, chore/, ci/, or refactor/"
        ;;
esac

branch_slug=${branch#*/}
if [[ ! "$branch_slug" =~ ^[a-z0-9][a-z0-9._/-]*$ ]]; then
    fail "branch suffix '$branch_slug' must use lowercase letters, digits, '.', '_', '/', or '-'"
fi

title_pattern="^${expected_type}(\\([a-z0-9._/-]+\\))?!?:[[:space:]]+[^[:space:]].*$"
if [[ ! "$title" =~ $title_pattern ]]; then
    fail "branch '$branch' requires a title like '${expected_type}(scope): description' or '${expected_type}: description'"
fi

printf 'PR metadata: %s -> %s\n' "$branch" "$title"
