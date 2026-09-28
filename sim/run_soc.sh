#!/usr/bin/env bash
# Usage: ./sim/run_soc.sh [sample|all|test] [16|32]
set -euo pipefail
if (( $# > 2 )); then
    echo "Usage: $0 [sample|all|test] [16|32]" >&2
    exit 2
fi
SIM_TOP=soc_tb exec "$(dirname "$0")/run_verilator.sh" "${2:-16}" "${1:-sample}"
