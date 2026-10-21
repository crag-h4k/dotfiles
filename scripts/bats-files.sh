#!/usr/bin/env bash
# Run independent suites concurrently while keeping each file's tests serial.
set -euo pipefail

jobs=${BATS_NUMBER_OF_PARALLEL_JOBS:-1}
if [[ -z "${BATS_NUMBER_OF_PARALLEL_JOBS:-}" ]] && command -v parallel >/dev/null 2>&1; then
    jobs=4
fi

if [[ "$jobs" == 1 ]]; then
    exec bats --timing --jobs 1 "$@"
fi
exec bats --timing --jobs "$jobs" --no-parallelize-within-files "$@"
