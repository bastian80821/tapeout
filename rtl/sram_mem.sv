`timescale 1ns / 1ps
//
// 32-bit memory built from four 8-bit SRAM macros.
//
// Parameters
//   WORDS   depth in 32-bit words.
//
// Interface
//   Word-addressed. wstrb selects which bytes are written; wstrb = 0 is a read.
//   Reads are SYNCHRONOUS: rdata is valid the cycle after en is asserted.
//   Read-during-write returns the previous contents.
//   Contents are undefined at power-up and must be loaded before use.
//
// Build modes
//   default                  behavioural model, same timing. Simulation and FPGA.
//   +define+USE_SRAM_MACRO   instantiates four gf180mcu 512x8 macros.
//
// TODO: the macro port names and polarities below are unverified against the
// PDK. They are active low (CEN low = selected, GWEN low = write). Confirm
// before tapeout.
//
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
            rdata <= {lane3[addr], lane2[addr], lane1[addr], lane0[addr]};
        end
    end
`endif
endmodule
