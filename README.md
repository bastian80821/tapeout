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

```sh
./sim/run_iverilog.sh 16        # core only, all tests
./sim/run_iverilog.sh 32        # same at 32 registers
./sim/run_soc.sh                # full SoC, program loaded over serial
```

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
docs/AREA.md          area numbers
```
