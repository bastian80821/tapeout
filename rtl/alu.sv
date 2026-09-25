`timescale 1ns / 1ps
// ALU for riskyC1, ASIC-oriented rewrite.
//
// Functionally identical to the original (same ports, same ctrl encoding), but
// restructured to share hardware instead of inferring it three times over:
//
//   original                          this version
//   --------                          ------------
//   a + b            (adder)          one 33-bit adder/subtractor, shared by
//   a - b            (subtractor)     ADD, SUB, SLT and SLTU
//   a <<  b          (barrel shift)   one right-shifter, shared by SLL, SRL
//   a >>  b          (barrel shift)   and SRA. SLL is done by reversing the
//   a >>> b          (barrel shift)   operand in, shifting right, reversing out
//   signed  compare  (comparator)     both comparisons fall out of the
//   unsigned compare (comparator)     subtractor's sign bit and carry out
//
// Bit reversal is pure wiring and costs no cells. The equivalence testbench in
// tb/alu_equiv_tb.sv checks this against the original exhaustively over ctrl
// and shift amounts, plus directed corners and random vectors.
module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  ctrl,
    output logic [31:0] res
);
    localparam logic [3:0] ALU_ADD  = 4'd0;
    localparam logic [3:0] ALU_SUB  = 4'd1;
    localparam logic [3:0] ALU_AND  = 4'd2;
    localparam logic [3:0] ALU_OR   = 4'd3;
    localparam logic [3:0] ALU_XOR  = 4'd4;
    localparam logic [3:0] ALU_SLL  = 4'd5;
    localparam logic [3:0] ALU_SRL  = 4'd6;
    localparam logic [3:0] ALU_SRA  = 4'd7;
    localparam logic [3:0] ALU_SLT  = 4'd8;
    localparam logic [3:0] ALU_SLTU = 4'd9;

    // ---------------- shared adder / subtractor ----------------
    // SUB, SLT and SLTU all need a - b, so they share one carry chain.
    logic        do_sub;
    logic [31:0] b_eff;
    logic [32:0] sum33;

    assign do_sub = (ctrl == ALU_SUB) | (ctrl == ALU_SLT) | (ctrl == ALU_SLTU);
    assign b_eff  = do_sub ? ~b : b;
    assign sum33  = {1'b0, a} + {1'b0, b_eff} + {32'd0, do_sub};

    // Unsigned a < b: subtracting produces no carry out.
    logic ltu;
    assign ltu = ~sum33[32];

    // Signed a < b: if the signs differ, a is smaller exactly when it is
    // negative; otherwise the difference's sign bit answers it.
    logic lt;
    assign lt = (a[31] ^ b[31]) ? a[31] : sum33[31];

    // ---------------- shared right shifter ----------------
    // SLL is a right shift of the bit-reversed operand, reversed back.
    function automatic logic [31:0] rev32(input logic [31:0] x);
        for (int i = 0; i < 32; i++) rev32[i] = x[31-i];
    endfunction

    logic [4:0]         shamt;
    logic [31:0]        shift_src;
    logic               sign_fill;
    logic signed [32:0] shift_ext;
    logic [31:0]        shifted;

    assign shamt     = b[4:0];
    assign shift_src = (ctrl == ALU_SLL) ? rev32(a) : a;
    assign sign_fill = (ctrl == ALU_SRA) ? shift_src[31] : 1'b0;
    assign shift_ext = $signed({sign_fill, shift_src});
    assign shifted   = shift_ext >>> shamt;   // bit 32 replicates, so SRA fills
                                              // with the sign and SRL with zero

    // ---------------- output select ----------------
    always_comb begin
        unique case (ctrl)
            ALU_ADD, ALU_SUB: res = sum33[31:0];
            ALU_AND:          res = a & b;
            ALU_OR:           res = a | b;
            ALU_XOR:          res = a ^ b;
            ALU_SLL:          res = rev32(shifted);
            ALU_SRL, ALU_SRA: res = shifted;
            ALU_SLT:          res = {31'd0, lt};
            ALU_SLTU:         res = {31'd0, ltu};
            default:          res = 32'd0;
        endcase
    end
endmodule
