`timescale 1ns / 1ps
// 32-bit memory built from four 8-bit SRAM macros.
//
// WHY THIS EXISTS
// The original imem/dmem infer block RAM on an FPGA, which costs no logic. On
// an ASIC there is nothing to infer: synthesis builds them from flip-flops, and
// 4 KB of flops is roughly 3.5 mm^2 against a 0.5 mm^2 budget. This wrapper
// swaps that for hard SRAM macros, which are roughly an order of magnitude
// denser because the bitcell is custom-drawn and the read mux tree disappears
// into the macro's internal decoder and sense amps.
//
// THE ONE BEHAVIOURAL DIFFERENCE, AND IT MATTERS
// Macro reads are SYNCHRONOUS. rdata is valid the cycle AFTER the address is
// presented, not combinationally in the same cycle. The original dmem did:
//     assign r_data = {mem3[ridx], ...};   // combinational
// which is what let riskyC1 resolve load-use without a stall. That guarantee is
// gone. In a multicycle FSM this costs nothing: present the address in one
// state, consume rdata in the next. In a pipeline it would require a real
// load-use stall, which is an independent reason the multicycle core is the
// right choice for this chip.
//
// Byte writes work by strobing only the lanes being written, which maps onto
// the four separate macros exactly as the original four byte-lane arrays did.
module sram_mem #(
    parameter int WORDS = 512,                 // 512 words x 32b = 2 KB
    parameter int AW    = $clog2(WORDS)
) (
    input  logic          clk,
    input  logic          en,                  // perform an access this cycle
    input  logic [AW-1:0] addr,                // WORD address, not byte
    input  logic [31:0]   wdata,
    input  logic [3:0]    wstrb,               // per-byte write enable; 0 = read
    output logic [31:0]   rdata                // valid one cycle after en
);

`ifdef USE_SRAM_MACRO
    //-----------------------------------------------------------------------
    // Hard macro instantiation.
    //
    // VERIFY THESE PORT NAMES AND POLARITIES AGAINST THE PDK before taping out.
    // The gf180mcu SRAM macros use active-LOW enables, which is the classic way
    // to lose a week: CEN low means selected, GWEN low means write.
    //-----------------------------------------------------------------------
    genvar lane;
    generate
        for (lane = 0; lane < 4; lane++) begin : g_lane
            gf180mcu_fd_ip_sram__sram512x8m8wm1 u_sram (
                .CLK   (clk),
                .CEN   (~en),                      // active low chip enable
                .GWEN  (~wstrb[lane]),             // active low write enable
                .WEN   (8'h00),                    // per-bit mask, all bits on
                .A     (addr),
                .D     (wdata[lane*8 +: 8]),
                .Q     (rdata[lane*8 +: 8]),
                .VDD   (1'b1),
                .VSS   (1'b0)
            );
        end
    endgenerate
`else
    //-----------------------------------------------------------------------
    // Behavioural model with identical timing: synchronous read, byte strobes.
    // Use this for simulation and for FPGA prototyping so the RTL above and
    // below the wrapper is exercised with the real one-cycle read latency.
    //-----------------------------------------------------------------------
    logic [7:0] lane0 [0:WORDS-1];
    logic [7:0] lane1 [0:WORDS-1];
    logic [7:0] lane2 [0:WORDS-1];
    logic [7:0] lane3 [0:WORDS-1];

    always_ff @(posedge clk) begin
        if (en) begin
            if (wstrb[0]) lane0[addr] <= wdata[7:0];
            if (wstrb[1]) lane1[addr] <= wdata[15:8];
            if (wstrb[2]) lane2[addr] <= wdata[23:16];
            if (wstrb[3]) lane3[addr] <= wdata[31:24];
            // Read-during-write returns the OLD contents on these macros.
            rdata <= {lane3[addr], lane2[addr], lane1[addr], lane0[addr]};
        end
    end
`endif
endmodule
