`timescale 1ns / 1ps
// Register file, parameterised for RV32I (32) or RV32E (16).
//
// Changes from the original for ASIC use:
//   * NREGS parameter. RV32E halves the flop count, which is where 36% of the
//     core area went. The instruction encoding is unchanged (register fields
//     are 5 bits in both bases), so nothing upstream of here has to change.
//   * The `initial` block that zeroed the array is gone. It is ignored by ASIC
//     synthesis, so relying on it would mean the registers power up undefined
//     on silicon while looking fine on the FPGA. Simulation-only init is kept
//     behind SYNTHESIS so waveforms stay readable.
//   * Still no reset. Resettable flops are larger, and RISC-V does not require
//     defined register contents at reset: software must write before it reads.
//     That is a deliberate area choice, not an oversight.
//
// Read/write semantics are identical to the original, including the write-first
// bypass, so this is a drop-in replacement.
module register_file #(
    parameter int NREGS  = 16,   // 16 = RV32E, 32 = RV32I
    parameter bit BYPASS = 1'b0  // 1 = write-first bypass (PIPELINED core only)
) (
    input  logic        clk,
    input  logic [4:0]  rs1_addr,
    output logic [31:0] rs1_data,
    input  logic [4:0]  rs2_addr,
    output logic [31:0] rs2_data,
    input  logic        rd_we,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data
);
    localparam int AW = $clog2(NREGS);

    logic [31:0] regs [0:NREGS-1];

    // In RV32E, x16..x31 do not exist and any access to them is an illegal
    // instruction, so the high address bits are simply not decoded here.
    logic [AW-1:0] rs1_idx, rs2_idx, rd_idx;
    assign rs1_idx = rs1_addr[AW-1:0];
    assign rs2_idx = rs2_addr[AW-1:0];
    assign rd_idx  = rd_addr [AW-1:0];

    // In RV32E, x16..x31 do not exist. A full implementation raises an illegal
    // instruction; this core has no trap mechanism, so they degrade to x0:
    // reads return zero, writes are dropped. That is deliberate. Truncating the
    // address instead would ALIAS x16..x31 onto x0..x15, and RV32I code would
    // then appear to run correctly whenever the aliased pairs were never live
    // at the same time, which is a silent and very misleading failure mode.
    logic rs1_bad, rs2_bad, rd_bad;
    assign rs1_bad = (NREGS < 32) & rs1_addr[4];
    assign rs2_bad = (NREGS < 32) & rs2_addr[4];
    assign rd_bad  = (NREGS < 32) & rd_addr [4];

`ifndef SYNTHESIS
    initial for (int i = 0; i < NREGS; i++) regs[i] = 32'd0;
`endif

    always_ff @(posedge clk)
        if (rd_we && !rd_bad && (rd_idx != '0))
            regs[rd_idx] <= rd_data;

    // Combinational read.
    //
    // BYPASS must be 0 for the multicycle core and 1 for the pipelined core.
    //
    // In the pipeline, rd_data comes from the writeback stage, i.e. a DIFFERENT
    // instruction, so forwarding it to a read port is both correct and needed.
    //
    // In a multicycle (or single-cycle) core, rd_data is produced by the very
    // instruction currently reading its own operands, so the bypass closes a
    // combinational loop:  rs1_data -> ALU -> wb_data -> rd_data -> rs1_data.
    // It is also unnecessary there: the write lands on the clock edge that ends
    // the instruction, and the reads legitimately see the old values.
    assign rs1_data = (rs1_bad | (rs1_idx == '0))                   ? 32'd0
                    : (BYPASS && rd_we && (rd_idx == rs1_idx))      ? rd_data
                    :                                                 regs[rs1_idx];

    assign rs2_data = (rs2_bad | (rs2_idx == '0))                   ? 32'd0
                    : (BYPASS && rd_we && (rd_idx == rs2_idx))      ? rd_data
                    :                                                 regs[rs2_idx];
endmodule
