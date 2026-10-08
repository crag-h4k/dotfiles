#!/usr/bin/env bash
# .github/scripts/prepare-macos-runner.sh
# Normalize only GitHub's disposable ARM64 macOS runner, not a workstation.
set -euo pipefail

[[ "${GITHUB_ACTIONS:-false}" == true ]] || {
    printf 'macOS runner preparation is restricted to GitHub Actions\n' >&2
    exit 1
}
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
    printf 'macOS deployment requires a native ARM64 runner\n' >&2
    exit 1
}

brew untap aws/tap 2>/dev/null || true

prefix=$(brew --prefix)
# The runner force-links retired OpenSSL 1.1 into the shared bin directory.
# Unlink that keg before dependencies upgrade OpenSSL 3; never force-overwrite.
if [[ -L "$prefix/bin/openssl" && "$(readlink "$prefix/bin/openssl")" == *'/openssl@1.1/'* ]]; then
    brew unlink openssl@1.1
fi
