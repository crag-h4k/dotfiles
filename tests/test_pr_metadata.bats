#!/usr/bin/env bats

setup() {
    export REPO_ROOT
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export VALIDATOR="$REPO_ROOT/scripts/validate-pr-metadata.sh"
}

@test "feature branches accept matching conventional titles" {
    run env \
        PR_HEAD_REF=feat/documentation-presentation \
        PR_TITLE='feat(repo): document the workstation' \
        "$VALIDATOR"

    [ "$status" -eq 0 ]
}

@test "breaking conventional titles are accepted" {
    run env \
        PR_HEAD_REF=feat/rework-components \
        PR_TITLE='feat(components)!: replace the component schema' \
        "$VALIDATOR"

    [ "$status" -eq 0 ]
}

@test "hotfix branches map to fix titles" {
    run env \
        PR_HEAD_REF=hotfix/tmux-scroll \
        PR_TITLE='fix(tmux): restore wheel scrolling' \
        "$VALIDATOR"

    [ "$status" -eq 0 ]
}

@test "branch and title types must agree" {
    run env \
        PR_HEAD_REF=feat/macos-ci \
        PR_TITLE='fix(ci): add the macOS runner' \
        "$VALIDATOR"

    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a title like 'feat(scope): description'"* ]]
}

@test "unknown branch prefixes fail with the allowed set" {
    run env \
        PR_HEAD_REF=update/readme \
        PR_TITLE='docs: update the README' \
        "$VALIDATOR"

    [ "$status" -eq 1 ]
    [[ "$output" == *"must start with feat/, fix/, hotfix/"* ]]
}

@test "branch suffixes stay lowercase and shell friendly" {
    run env \
        PR_HEAD_REF=feat/Big_Sur \
        PR_TITLE='feat: support Big Sur' \
        "$VALIDATOR"

    [ "$status" -eq 1 ]
    [[ "$output" == *"must use lowercase"* ]]
}

@test "release and dependency automation branches are exempt" {
    for branch in \
        release-please--branches--main \
        dependabot/github_actions/actions-checkout-7 \
        renovate/pre-commit-hooks; do
        run env \
            PR_HEAD_REF="$branch" \
            PR_TITLE='automation owns this title' \
            "$VALIDATOR"

        [ "$status" -eq 0 ]
        [[ "$output" == *"exempt automation branch"* ]]
    done
}
