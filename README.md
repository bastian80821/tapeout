# riskyC1-MC

Multicycle RV32E core and SoC for the gf180 tapeout. Based on
[riskyC1](https://github.com/bastian80821/riskyC1), a 5-stage pipelined RV32I
core that passes the official riscv-tests suite on a Spartan-7.

![SoC block diagram](docs/soc_block_diagram.svg)

## What it is

A single core with unified instruction and data memory, a UART, and a
bootloader that loads programs over serial. RV32E by default, so 16 registers
instead of 32. The instruction encoding is unchanged, only the register file
shrinks.

The core is multicycle rather than pipelined. SRAM macros read synchronously,
so read data arrives the cycle after the address. A pipeline would need a
load-use interlock to handle that. The FSM absorbs it in one extra state.

## Running it

Everything goes through `make`, and CI runs the same targets, so a clean
`make ci` locally means a clean CI run.

```sh
make env                     # check your tools
make lint                    # verilator -Wall on the single-core soc
make synth                   # generic yosys synthesis check (no PDK needed)
make synth-full              # also run ABC gate optimization
make check-top               # elaborate the dual-core soc_top at both RAM plans
make test                    # core and SoC program tests at NREGS=16
make test-core NREGS=32      # core only, 32 registers
make test-soc TEST=sample    # quick SoC boot check
make test-unit BLOCK=arbiter # one block's unit testbench
make waves TEST=addi         # one core test with a VCD
make ci                      # everything CI requires
```

The scripts in `sim/` still work directly; the Makefile only wraps them.

### Tools

- **Nix (Linux or macOS):** `nix develop` gives the exact tool versions CI
  uses, pinned by `flake.lock`. Add a waveform viewer yourself on macOS.
- **Homebrew (macOS):** `brew install verilator icarus-verilog yosys coreutils bash`,
  plus Surfer for waveforms. Verilator must be 5.036 or newer, and bash 4 or
  newer (macOS ships 3.2; `run_unit.sh` needs the newer one).
- **Windows:** WSL2 with Ubuntu, then either option above.

Then run `make env`. It fails on anything `make ci` needs and only warns about
the RISC-V compiler, Spike and cocotb, which nothing needs yet.

Lint runs with `-Wall`. Known harmless warnings are waived one by one in
`tools/lint_waivers.vlt`; any new warning fails the build.

### Unit testbenches

Each block in `rtl/bus`, `rtl/cache`, `rtl/mem` and `rtl/periph` has a unit
testbench in `tb/`. Until its checks are written it prints
`no checks written yet` and fails. When a block's checks are real, add the
block to `UNIT_GATED` in the Makefile; from then on `make ci` and CI require
it to pass.

### CI

Every push to `main` and every pull request runs `.github/workflows/ci.yml`:
environment check, lint, synthesis check, the `soc_top` elaboration check,
core and SoC tests at 16 and 32 registers, and the gated unit testbenches,
inside `nix develop .#ci`. Unfinished unit testbenches run only when requested
with `make test-unit`. CI prints check summaries and failure diagnostics without
uploading log artifacts. The
physical-implementation flow (LibreLane) is not in CI; it runs at milestones
against tagged RTL.

Synthesis runs in a separate job alongside the lint and simulation job. The
default `make synth` skips ABC gate optimization while retaining RTL synthesis,
memory and gate lowering, and netlist checks. `make synth-full` includes ABC.
Both use 16-word RAM for the generic check and limit each
register configuration to two minutes. Override `SYNTH_TIMEOUT` for longer
local investigations. Synthesis prints one result per configuration. Simulation
prints suite totals and captures output temporarily to validate results and show
failure details; it does not save build or per-test logs.
The workflow can also be started manually. Repository rules should require both
the `synthesis` and `toolchain-a` jobs before merging.

### Vivado

Vivado, non-project mode:

```sh
vivado -mode batch -source sim/run_vivado.tcl -tclargs 16
```

For the Vivado GUI, add `rtl/*.sv` as design sources and `tb/core_mc_tb.sv` or
`tb/soc_tb.sv` as simulation top. Pick the test with `-testplusarg HEX=<path>`
in the simulation settings.

## Verification

38 official riscv-tests plus an RV32E self-test pass at both 16 and 32
registers. The same programs pass through the SoC, loaded over simulated
serial and checked by decoding the transmit pin.

`tb/core_mc_tb.sv` preloads memory and watches the memory port. Fast, use it
while working on the core. `tb/soc_tb.sv` only touches the two serial pins, so
it exercises the real boot path. Slow, use it to check the SoC.

## Core

Five states. FETCH presents the PC, FETCH_W latches the instruction, EXEC
decodes and runs the ALU, MEM presents the data address, MEM_W takes the load
result. Non-memory instructions finish in EXEC. Three cycles for ALU, branch
and jump, four for stores, five for loads.

Memory port is byte-addressed with a one-cycle read latency. `mem_wstrb` of
zero means a read.

## Memory map

```
0x0000 - 0x0FFF   RAM
0x1000            UART data, write to transmit
0x1004            UART status, bit 0 is transmitter busy
```

Memory contents are undefined at power-up, so the bootloader holds the core in
reset until a program has been received. The host sends a 4-byte word count
followed by that many little-endian words.

## Things to know

`register_file.sv` has a `BYPASS` parameter. It must be 0 here. The bypass is
only correct when `rd_data` comes from a later pipeline stage. In a multicycle
core the write target is the instruction currently reading its operands, so the
bypass closes a combinational loop through the ALU.

With 16 registers, x16 to x31 read as zero and writes to them are dropped. They
are not aliased onto x0 to x15, so RV32I code that uses them fails rather than
appearing to work.

`sram_mem.sv` has a behavioural model by default and instantiates gf180 macros
under `USE_SRAM_MACRO`. The macro port names and polarities have not been
checked against the PDK.

The UART baud divider is derived from a `CLK_FREQ` parameter that still
defaults to 100 MHz.

## Files

```
rtl/soc.sv            core, memory, bootloader, UART, address decode
rtl/core_mc.sv        multicycle core
rtl/register_file.sv  NREGS and BYPASS parameters
rtl/alu.sv            shared adder and shifter
rtl/sram_mem.sv       four 8-bit macros, synchronous read
rtl/decoder.sv        from riskyC1
rtl/imm_gen.sv        from riskyC1
rtl/mem_access.sv     from riskyC1
rtl/uart_rx.sv        from riskyC1
rtl/uart_tx.sv        from riskyC1
rtl/bootloader.sv     from riskyC1
tb/core_mc_tb.sv      core only
tb/soc_tb.sv          full SoC over serial
tools/mk_rv32e_test.py  generates the RV32E self-test
```
