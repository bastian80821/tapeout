# riskyC1-MC

Multicycle RV32I / RV32E core for the Aussie Chip Collective gf180 tapeout.

Derived from [riskyC1](https://github.com/bastian80821/riskyC1), a 5-stage
pipelined RV32I core that passes 38/38 of the official `riscv-tests` rv32ui
suite on a Spartan-7. This version replaces the pipeline with a 5-state FSM for
area and for compatibility with synchronous SRAM macros.

## Status

| Configuration | Suite | Result |
|---|---|---|
| NREGS=32 (RV32I) | 38 official riscv-tests rv32ui | **38 / 38 pass** |
| NREGS=16 (RV32E) | 38 official riscv-tests rv32ui | **38 / 38 pass** |
| NREGS=16 (RV32E) | hand-written RV32E self-test | pass |
| ALU vs original riskyC1 ALU | 203,744 vectors | 0 mismatches |
| SRAM wrapper | byte / halfword / word, sync read | pass |

## Quick start

```sh
git clone https://github.com/<org>/riskyC1-mc.git
cd riskyC1-mc

# Icarus Verilog (fast, no licence)
./sim/run_iverilog.sh 32        # RV32I, all tests
./sim/run_iverilog.sh 16        # RV32E, all tests
./sim/run_iverilog.sh 16 addi   # one test

# Vivado XSim
vivado -mode batch -source sim/run_vivado.tcl -tclargs 16
```

Expected output:

```
PASS    tests/add.hex  (1290 cycles)
...
------------------------------------------------
NREGS=16 : 38 passed, 0 failed
```

## Why multicycle

1. **Area.** The pipeline costs 400–500 stage-register flops plus forwarding and
   hazard logic, roughly 0.05 mm² per core at ~110 um²/flop, for throughput this
   chip does not need.
2. **Memory.** SRAM macros read synchronously: data is valid the cycle *after*
   the address. A single-cycle core cannot absorb that (its PC advances every
   clock); a pipeline needs a real load-use interlock. The multicycle FSM
   absorbs it for one extra state.

FSM:

```
S_FETCH    present PC, mem_en=1
S_FETCH_W  instruction valid on mem_rdata -> IR
S_EXEC     decode, regfile read, ALU; non-memory ops write back and update PC
S_MEM      present address; stores issue here and update PC
S_MEM_W    load data valid; write back and update PC
```

Cycles per instruction: ALU / branch / jump 3, store 4, load 5.

## RV32E

Set `NREGS=16`. The instruction encoding is unchanged (register fields are 5
bits in both bases), so the decoder, immediate generator and ALU are untouched.
Only the register array shrinks, which is where 36% of the core area went.

**All 38 official tests pass unmodified at NREGS=16.** A static scan of the
binaries suggests otherwise (register fields up to x29 and x31 appear), but that
scan decodes each test's *data* section as instructions. The executed code stays
within x0..x15.

x16..x31 degrade to x0: reads return zero, writes are dropped. They are *not*
aliased onto x0..x15 by truncating the address, because aliasing would let RV32I
code appear to work whenever aliased pairs were never live at the same time,
which is a silent and misleading failure mode.

## Known trap: the register-file bypass

`register_file.sv` takes a `BYPASS` parameter.

* `BYPASS=1` for the **pipelined** core. `rd_data` comes from the writeback
  stage, i.e. a different instruction, so forwarding it to a read port is both
  correct and necessary.
* `BYPASS=0` for **this** core. In multicycle (and single-cycle) the write
  target is the instruction currently reading its own operands, so the bypass
  closes a combinational loop:

```
rs1_data -> ALU -> wb_data -> rd_data -> bypass -> rs1_data
```

The simulator spins until it is killed. Anyone writing a non-pipelined wrapper
around this register file will hit it, and it is not obvious.

## Memory

`rtl/sram_mem.sv` presents a 32-bit memory built from four 8-bit macros, with
byte strobes mapping onto the lanes. Two build modes:

* default: behavioural model with **identical timing** (synchronous read), for
  simulation and FPGA prototyping
* `+define+USE_SRAM_MACRO`: instantiates `gf180mcu_fd_ip_sram__sram512x8m8wm1`

**The macro port names and polarities are written from memory and have not been
checked against the PDK.** They are active-low (CEN low = selected, GWEN low =
write). Verify before tapeout.

Testbench memory map (unified, von Neumann):

```
0x0000 - 0x0FFF   RAM, 1024 words, synchronous read
0x1000            UART data   (write: transmit low byte)
0x1004            UART status (read: bit 0 = busy)
```

## Layout

```
rtl/core_mc.sv        multicycle core, parameterised NREGS
rtl/register_file.sv  parameterised NREGS + BYPASS, no `initial` in synthesis
rtl/alu.sv            shared adder and shifter, 28% fewer cells than original
rtl/sram_mem.sv       4 x 8-bit macro wrapper, synchronous read, byte strobes
rtl/decoder.sv        unchanged from riskyC1
rtl/imm_gen.sv        unchanged from riskyC1
rtl/mem_access.sv     unchanged from riskyC1
tb/core_mc_tb.sv      runs a hex image, watches the UART for P / F
tests/*.hex           38 official riscv-tests + one RV32E self-test
tools/mk_rv32e_test.py  generates the RV32E self-test (x0..x15 only)
sim/run_iverilog.sh   batch runner, Icarus
sim/run_vivado.tcl    batch runner, Vivado XSim
docs/AREA.md          area budget and where it goes
```

## Next: dual core

This is the single-core foundation. The multicore layer is not built yet:

* **Arbiter and request mux.** One grant per cycle; the loser stalls by holding
  `mem_en` and waiting, which the FSM already tolerates.
* **Lock register.** A shared memory-mapped byte where a *read* returns the old
  value and sets it to 1 in the same cycle, and a write clears it. Because the
  arbiter grants one core per cycle, that read-and-set cannot interleave, which
  gives atomic test-and-set from plain `LB`/`SB`. No new instructions needed.
* **CORE_ID.** Read-only byte returning 0 or 1, hardwired per core. Both cores
  boot the same image and diverge on it.
* **EXIT.** Per-core halt flag; when both are set, drive a done pin.

Demo program: both cores sum a slice of a shared array, accumulating into a
shared total behind the lock, then set EXIT. Correct final total proves identity
divergence, shared-memory communication and mutual exclusion in ~40
instructions, observable on a pin without a UART.

## Contributing

Branch off `main`, open a PR, and make sure `./sim/run_iverilog.sh 32` and
`./sim/run_iverilog.sh 16` both report 38 passed before requesting review.
