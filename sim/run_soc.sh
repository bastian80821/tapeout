#!/usr/bin/env bash
# Run programs through the full SoC: serial boot, execution, serial output.
# Slower than run_iverilog.sh because every byte is shifted in bit by bit.
#   ./sim/run_soc.sh                 # default sample of tests
#   ./sim/run_soc.sh all             # every test (slow)
#   ./sim/run_soc.sh addi            # one test
set -u
WHICH=${1:-sample}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/rtl/soc.sv $ROOT/rtl/core_mc.sv $ROOT/rtl/decoder.sv $ROOT/rtl/imm_gen.sv \
     $ROOT/rtl/mem_access.sv $ROOT/rtl/alu.sv $ROOT/rtl/register_file.sv \
     $ROOT/rtl/sram_mem.sv $ROOT/rtl/uart_rx.sv $ROOT/rtl/uart_tx.sv \
     $ROOT/rtl/bootloader.sv $ROOT/tb/soc_tb.sv"
OUT=$(mktemp -d)/soc
iverilog -g2012 -s soc_tb -o "$OUT" $SRC 2>&1 | grep -viE "sorry:|constant selects" || true

case "$WHICH" in
  all)     LIST=$(ls "$ROOT"/tests/*.hex | sort) ;;
  sample)  LIST=$(for t in rv32e_test simple auipc jal lui addi lw sw beq; do echo "$ROOT/tests/$t.hex"; done) ;;
  *)       LIST="$ROOT/tests/$WHICH.hex" ;;
esac

pass=0; fail=0
for h in $LIST; do
  r=$(timeout 900 vvp "$OUT" +HEX="$h" 2>/dev/null | grep -E "^(PASS|FAIL|TIMEOUT)")
  printf "%s\n" "$r"
  case "$r" in PASS*) pass=$((pass+1));; *) fail=$((fail+1));; esac
done
echo "------------------------------------------------"
echo "SoC : $pass passed, $fail failed"
[ $fail -gt 0 ] && exit 1
exit 0
