# Area budget

## Measured (team synthesis, gf180, um^2)

| module | V1 (32 regs) | V2 (RV32E) | delta |
|---|---|---|---|
| regfile | 122,288 | 58,149 | **-64,139** |
| control / glue | 30,329 | 30,371 | +42 |
| alu | 16,644 | 17,463 | +819 |
| mem_access | 2,755 | 2,755 | 0 |
| imm_gen | 1,183 | 1,183 | 0 |
| decoder | 573 | 573 | 0 |
| **total** | **173,772** | **110,493** | **-63,279 (-36.4%)** |

`mem_access`, `imm_gen` and `decoder` are byte-for-byte identical, which is the
empirical proof that RV32E touches nothing in the decode path.

## Units

Yosys reports liberty area units, which for gf180mcu are **um^2**.

```
173,772 um^2 = 0.174 mm^2      NOT 1.8 mm^2
110,493 um^2 = 0.110 mm^2      NOT 1.1 mm^2
```

Sanity check: the V2 core holds about 564 flops (480 regfile + PC + IR + FSM).
At ~110 um^2 per flop in this 5V library, 0.110 mm^2 is about 1,000
flop-equivalents, which is right. 1.1 mm^2 would be 10,280 flop-equivalents in a
core with 564 flops.

## Per-flop constant

Derived from the team's own regfile synthesis: 122,288 um^2 holds 992 flops plus
two 32:1 read mux trees (~10-16k um^2), so **a flop costs roughly 107-113 um^2**.
That lets any structure be priced by counting flops.

This constant predicted the V2 core at 110,875 um^2 before it was synthesised.
The measured value is 110,493, an error of 0.35%.

## Corrections to the 1.56 mm^2 budget

**RV32E saving is understated.** 2 x 0.0633 = 0.127 mm^2 of *logic*, which sits
above the placement-density divisor, so in die area it is 0.127 / 0.45 =
**0.281 mm^2**.

**The L1 cache costs more than it saves.** 0.064 each is 0.128 logic = 0.284 mm^2
of die. A 2-way 8-set cache is 16 lines, roughly 64 bytes, in front of a 1 KiB
SRAM that already answers in one cycle. It hides no latency, and MSI coherence
is the highest-risk item in the project. Dropping it saves as much as RV32E.

**The SRAM figure needs the LEF.** 0.225 mm^2 for 512 bytes implies the macro is
only ~2x denser than flip-flops, which is far too low for real SRAM. It is now
the largest single line in the budget.

**45% placement density is conservative** for a standard-cell design; 55-60% is
normal and would cut the logic portion by a quarter.

## Recomputed: RV32E, no cache

| | logic (mm^2) | die at 0.45 |
|---|---|---|
| 2 x RV32E core | 0.221 | 0.491 |
| bus, arbiter, MMIO, UART, ROM | 0.022 | 0.049 |
| SRAM macros (as quoted) | - | 0.450 |
| **total** | | **0.990** |

Down from 1.56 mm^2. At 60% density the logic portion drops to 0.405, giving
0.855 mm^2.

## For contrast: the original flop memory

`imem` (4 KB) + `dmem` (4 KB) = 65,536 flops = **7.0 mm^2**.

They only worked on the FPGA because Vivado silently inferred block RAM, which
is itself a hard macro the vendor put in the fabric. ASIC synthesis has no such
option and builds flip-flops.
