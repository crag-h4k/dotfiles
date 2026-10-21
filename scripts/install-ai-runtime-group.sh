#!/usr/bin/env bash
# One isolated install group, invoked after the top-level bootstrap and approval.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[[ "${DOTFILES_PACKAGES_APPROVED:-false}" == true && -r "${DOTFILES_PACKAGE_PLAN:-}" ]] ||
    die "runtime installation requires an approved package plan"
group="$1"
result="$2"

case "$group" in
    opencode)
        if [[ "${DOTFILES_NODE_READY:-false}" == true ]]; then
            target=$(package_target npm @opencode/cli)
            package_action_try npm @opencode/cli "OpenCode V2 CLI and matching runtime" \
                env OPENCODE2_VERSION="${target:-${OPENCODE2_VERSION:-latest}}" \
                bash "$SCRIPT_DIR/install-opencode2.sh" || true
        else
            package_skip "OpenCode V2 CLI and matching runtime; Node.js 24+ unavailable"
        fi
        ;;
    shared-npm)
        # These installers all write to ~/.local; never run them concurrently.
        if [[ "${INSTALL_AI_COPILOT:-false}" == true ]]; then
            if [[ "${DOTFILES_NODE_READY:-false}" == true ]]; then
                target=$(package_target npm @github/copilot)
                package_action_try npm @github/copilot "GitHub Copilot CLI" \
                    env COPILOT_VERSION="${target:-${COPILOT_VERSION:-prerelease}}" \
                    bash "$SCRIPT_DIR/install-copilot.sh" || true
            else
                package_skip "GitHub Copilot CLI; Node.js 24+ unavailable"
            fi
        fi
        if [[ "${INSTALL_AI_OPENCODE:-false}" == true ]]; then
            if [[ "${DOTFILES_NODE_READY:-false}" == true ]]; then
                package_action_try npm ssh-mcp "SSH MCP" \
                    env INSTALL_AI_SSH_MCP=true bash "$SCRIPT_DIR/install-ssh-mcp.sh" || true
                package_action_try npm @caveman-ai/cli "Caveman CLI and signed runtime" \
                    env INSTALL_AI_CAVEMAN=true bash "$SCRIPT_DIR/install-caveman.sh" || true
            else
                package_skip "SSH MCP; Node.js 24+ unavailable"
                package_skip "Caveman; Node.js 24+ unavailable"
            fi
        fi
        ;;
    openviking)
        target=$(package_target uv-tool openviking)
        package_action_try uv-tool openviking "OpenViking isolated Python environment" \
            env OPENVIKING_VERSION="${target:-${OPENVIKING_VERSION:-0.5.1.1}}" \
            bash "$SCRIPT_DIR/install-openviking.sh" || true
        ;;
    *) die "unknown runtime group: $group" ;;
esac
printf '%s %s %s\n' "$_package_results_ok" "$_package_results_failed" "$_package_results_skipped" >"$result"
