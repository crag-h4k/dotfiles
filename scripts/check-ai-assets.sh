#!/usr/bin/env bash
# Reject personal or machine-specific data in shareable AI agents and skills.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AI_DIR="$REPO_DIR/ai"

patterns=(
    '/Users/[A-Za-z0-9._-]+'
    '/home/[A-Za-z0-9._-]+'
    '/opt/[A-Za-z0-9._/-]+'
    '([A-Za-z0-9-]+\.)+(lan|local|internal)'
    '(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)[0-9.]+'
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
)

failed=0
for pattern in "${patterns[@]}"; do
    if rg -n --hidden --glob '!skills/interview-coach/UPSTREAM.md' \
        --glob '!skills/interview-coach/README.md' \
        --glob '!skills/interview-coach/releases/**' \
        --glob '!skills/interview-coach/VERSIONS.md' \
        -e "$pattern" "$AI_DIR/agents" "$AI_DIR/skills"; then
        printf 'check-ai-assets: personal or machine-specific pattern matched: %s\n' "$pattern" >&2
        failed=1
    fi
done

if (( failed )); then
    exit 1
fi

printf 'check-ai-assets: shareable agents and skills are clean\n'
