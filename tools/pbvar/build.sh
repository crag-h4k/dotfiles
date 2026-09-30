#!/usr/bin/env bash
# tools/pbvar/build.sh
# Cross-compile pbvar for the platforms the dotfiles targets, into tools/pbvar/dist/
# (a gitignored build staging dir). CI (.github/workflows/pbvar-build.yaml) uploads
# these as GitHub Release assets; chezmoi then fetches the arch-matched one to
# ~/.local/bin/pbvar (home/.chezmoiexternal.toml). Pure Go (CGO_ENABLED=0), so every
# target builds from one host. -trimpath keeps the output independent of the build
# directory. Runnable by hand to smoke-test a cross-build.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
mkdir -p dist

platforms=(
    "darwin arm64"
    "linux arm64"
    "linux amd64"
)

for p in "${platforms[@]}"; do
    read -r goos goarch <<<"$p"
    out="dist/pbvar_${goos}_${goarch}"
    echo "building $out"
    CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
        go build -trimpath -ldflags="-s -w" -o "$out" .
done

echo "done:"
ls -1 dist/pbvar_*
