#!/usr/bin/env bash
# Core: ./sim/run_verilator.sh [16|32] [test|all]
# SoC:  ./sim/run_soc.sh [test|sample|all] [16|32]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NREGS=${1:-16}
WHICH=${2:-all}
TOP=${SIM_TOP:-core_mc_tb}
case "$NREGS" in 16|32) ;; *) echo "NREGS must be 16 or 32" >&2; exit 2;; esac
case "$TOP" in core_mc_tb|soc_tb) ;; *) echo "Unknown simulation top: $TOP" >&2; exit 2;; esac
if (( $# > 2 )); then
    echo "Usage: $0 [16|32] [test|all]" >&2
    exit 2
fi
case "$WHICH" in
    all) TESTS=("$ROOT"/tests/*.hex) ;;
    sample) TESTS=(); for t in rv32e_test simple auipc jal lui addi lw sw beq; do
        TESTS+=("$ROOT/tests/$t.hex")
    done ;;
    *) TESTS=("$ROOT/tests/$WHICH.hex") ;;
esac
for h in "${TESTS[@]}"; do
    [[ -f "$h" ]] || { echo "Test image not found: $h" >&2; exit 2; }
done
command -v verilator >/dev/null || { echo "Verilator 5+ is required; run nix develop first." >&2; exit 2; }
command -v timeout >/dev/null || { echo "GNU timeout is required." >&2; exit 2; }

# Keep generated C++, executable, build output and individual test logs together.
BUILD="$ROOT/sim/obj_dir/${TOP}_${NREGS}"
mkdir -p "$BUILD"
echo "Building $TOP (NREGS=$NREGS)..."
if ! verilator --binary --timing --trace --top-module "$TOP" \
    "-GNREGS=$NREGS" --Mdir "$BUILD" -o simulator -j "${JOBS:-2}" \
    "$ROOT"/rtl/*.sv "$ROOT"/rtl/core/*.sv \
    "$ROOT"/rtl/mem/*.sv "$ROOT"/rtl/periph/*.sv \
    "$ROOT/tb/$TOP.sv" >"$BUILD/build.log" 2>&1; then
    cat "$BUILD/build.log" >&2
    exit 1
fi

pass=0; fail=0
for h in "${TESTS[@]}"; do
    name=$(basename "$h" .hex)
    args=("+HEX=$h")
    if [[ ${TRACE:-0} == 1 ]]; then args+=("+TRACE=$BUILD/$name.vcd"); fi
    status=0
    timeout "${SIM_TIMEOUT:-180}" "$BUILD/simulator" "${args[@]}" >"$BUILD/$name.log" 2>&1 || status=$?
    if (( status == 0 )) && grep -q '^PASS ' "$BUILD/$name.log" \
        && ! grep -qE '^(FAIL|TIMEOUT)' "$BUILD/$name.log"; then
        grep '^PASS ' "$BUILD/$name.log"
        pass=$((pass+1))
    else
        echo "FAIL $name (exit $status; log: $BUILD/$name.log)"
        cat "$BUILD/$name.log"
        fail=$((fail+1))
    fi
done
echo "$TOP NREGS=$NREGS : $pass passed, $fail failed"
(( fail == 0 ))
