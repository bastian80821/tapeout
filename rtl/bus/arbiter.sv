`timescale 1ns / 1ps
//
// Bus arbiter. Grants at most one of five requesters per cycle and forwards the
// granted request to the address decode.
//
// Requesters, by b_src index
//   0 boot   bootloader. Never waits, so it has no grant output.
//   1 d0     core 0 data port
//   2 d1     core 1 data port
//   3 ic0    core 0 I-cache
//   4 ic1    core 1 I-cache
//
// Each request bundle is x_req, x_addr (13), x_wdata (32), x_wstrb (4).
// x_wstrb = 0000 is a read, anything else a write.
//
// Behaviour
//   loading = 1  grant boot whenever boot_req is high; grant nobody else.
//   loading = 0  round-robin over sources 1..4 with a 2-bit pointer. Search
//                starts at the pointer; after a grant the pointer moves to the
//                source after the one granted. Worst-case wait is 3 cycles.
//   x_gnt is combinational from the req lines and the pointer, high in the same
//   cycle as the request it accepts. At most one grant per cycle.
//   b_valid = any grant this cycle. b_addr, b_wdata, b_wstrb are the granted
//   bundle. b_src is its index. When b_valid is 0 the other b_* outputs are
//   don't-care.
//
// Requesters hold their bundle stable until granted, so no input registering
// is needed here.
//
module arbiter (
    input  logic        clk,
    input  logic        rst,
    input  logic        loading,

    input  logic        boot_req,
    input  logic [12:0] boot_addr,
    input  logic [31:0] boot_wdata,
    input  logic [3:0]  boot_wstrb,

    input  logic        d0_req,
    input  logic [12:0] d0_addr,
    input  logic [31:0] d0_wdata,
    input  logic [3:0]  d0_wstrb,
    output logic        d0_gnt,

    input  logic        d1_req,
    input  logic [12:0] d1_addr,
    input  logic [31:0] d1_wdata,
    input  logic [3:0]  d1_wstrb,
    output logic        d1_gnt,

    input  logic        ic0_req,
    input  logic [12:0] ic0_addr,
    input  logic [31:0] ic0_wdata,
    input  logic [3:0]  ic0_wstrb,
    output logic        ic0_gnt,

    input  logic        ic1_req,
    input  logic [12:0] ic1_addr,
    input  logic [31:0] ic1_wdata,
    input  logic [3:0]  ic1_wstrb,
    output logic        ic1_gnt,

    output logic        b_valid,
    output logic [12:0] b_addr,
    output logic [31:0] b_wdata,
    output logic [3:0]  b_wstrb,
    output logic [2:0]  b_src
);
    // Stub: outputs tied off until implemented.
    assign d0_gnt  = 1'b0;
    assign d1_gnt  = 1'b0;
    assign ic0_gnt = 1'b0;
    assign ic1_gnt = 1'b0;
    assign b_valid = 1'b0;
    assign b_addr  = '0;
    assign b_wdata = '0;
    assign b_wstrb = '0;
    assign b_src   = '0;
endmodule
