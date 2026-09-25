`timescale 1ns / 1ps
// riskyC1-MC : multicycle RV32I/RV32E core for the gf180 tapeout.
//
// Same datapath modules as the pipelined riskyC1 (decoder, imm_gen, alu,
// mem_access, register_file) driven by a 5-state FSM instead of pipeline
// registers. Two reasons for the change:
//
//   1. Area. The pipeline costs 400-500 flops of stage registers plus the
//      forwarding network and hazard logic, for throughput this chip does not
//      need.
//   2. Memory. SRAM macros read synchronously: data is valid the cycle AFTER
//      the address is presented. A single-cycle core cannot absorb that at all
//      (its PC advances every clock), and a pipeline needs a real load-use
//      interlock. A multicycle FSM absorbs it for the cost of one state,
//      because it already spends a whole cycle on fetch.
//
// Cycle counts:  ALU / branch / jump 3,  store 4,  load 5.
//
// NREGS selects the base ISA: 32 for RV32I, 16 for RV32E. The instruction
// encoding is identical in both, so nothing upstream of the register file
// changes.
module core_mc #(
    parameter int NREGS = 32
) (
    input  logic        clk,
    input  logic        rst,

    // Synchronous memory port. rdata is valid one cycle after en is asserted.
    output logic        mem_en,
    output logic [31:0] mem_addr,     // BYTE address
    output logic [31:0] mem_wdata,
    output logic [3:0]  mem_wstrb,    // 0 = read
    input  logic [31:0] mem_rdata,

    // Observability: pulses high for one cycle as each instruction completes.
    output logic        retire,
    output logic [31:0] retire_pc
);
    typedef enum logic [2:0] {
        S_FETCH, S_FETCH_W, S_EXEC, S_MEM, S_MEM_W
    } state_e;

    state_e      state;
    logic [31:0] pc, ir;

    // ---------------- decode (combinational; ir is stable across states) ----
    logic [4:0] rd, rs1, rs2;
    logic [2:0] func3, imm_sel;
    logic [3:0] alu_op;
    logic       reg_write, alu_src, branch, jmp, jmpr, mem_read, mem_write, lui, auipc;

    decoder u_decoder (
        .inst(ir), .opc(), .rd(rd), .rs1(rs1), .rs2(rs2),
        .func3(func3), .func7(),
        .reg_write(reg_write), .imm_sel(imm_sel), .alu_op(alu_op),
        .alu_src(alu_src), .branch(branch), .jmp(jmp), .jmpr(jmpr),
        .mem_read(mem_read), .mem_write(mem_write), .lui(lui), .auipc(auipc)
    );

    logic [31:0] imm;
    imm_gen u_imm_gen (.inst(ir), .ctrl(imm_sel), .imm(imm));

    // ---------------- register file ----------------
    logic [31:0] rs1_data, rs2_data, wb_data;
    logic        rf_we;

    register_file #(.NREGS(NREGS), .BYPASS(1'b0)) u_rf (
        .clk(clk),
        .rs1_addr(rs1), .rs1_data(rs1_data),
        .rs2_addr(rs2), .rs2_data(rs2_data),
        .rd_we(rf_we), .rd_addr(rd), .rd_data(wb_data)
    );

    // ---------------- ALU ----------------
    logic [31:0] alu_b, alu_result;
    assign alu_b = alu_src ? imm : rs2_data;
    alu u_alu (.a(rs1_data), .b(alu_b), .ctrl(alu_op), .res(alu_result));

    // ---------------- branch comparison ----------------
    // Kept out of the ALU: for branches the decoder leaves alu_op at ADD so the
    // ALU is free for address arithmetic, so the comparison needs its own path.
    logic eq, lt, ltu, branch_taken;
    assign eq  = (rs1_data == rs2_data);
    assign lt  = ($signed(rs1_data) < $signed(rs2_data));
    assign ltu = (rs1_data < rs2_data);

    always_comb begin
        case (func3)
            3'b000:  branch_taken = branch &  eq;    // beq
            3'b001:  branch_taken = branch & ~eq;    // bne
            3'b100:  branch_taken = branch &  lt;    // blt
            3'b101:  branch_taken = branch & ~lt;    // bge
            3'b110:  branch_taken = branch &  ltu;   // bltu
            3'b111:  branch_taken = branch & ~ltu;   // bgeu
            default: branch_taken = 1'b0;
        endcase
    end

    // ---------------- byte / halfword handling ----------------
    logic [31:0] st_wdata, load_data;
    logic [3:0]  st_wstrb;

    mem_access u_mem_access (
        .func3(func3), .addr_lo(alu_result[1:0]), .mem_write(mem_write),
        .store_data(rs2_data), .w_data(st_wdata), .w_strb(st_wstrb),
        .raw_rdata(mem_rdata), .load_data(load_data)
    );

    // ---------------- next PC ----------------
    logic [31:0] next_pc;
    always_comb begin
        if      (branch_taken) next_pc = pc + imm;
        else if (jmp)          next_pc = pc + imm;
        else if (jmpr)         next_pc = (rs1_data + imm) & 32'hFFFF_FFFE;
        else                   next_pc = pc + 32'd4;
    end

    // ---------------- writeback mux ----------------
    always_comb begin
        if      (lui)        wb_data = imm;
        else if (auipc)      wb_data = pc + imm;
        else if (jmp | jmpr) wb_data = pc + 32'd4;
        else if (mem_read)   wb_data = load_data;
        else                 wb_data = alu_result;
    end

    // ---------------- memory port ----------------
    always_comb begin
        mem_en    = 1'b0;
        mem_addr  = 32'd0;
        mem_wdata = 32'd0;
        mem_wstrb = 4'b0000;
        case (state)
            S_FETCH: begin
                mem_en   = 1'b1;
                mem_addr = pc;
            end
            S_MEM: begin
                mem_en    = 1'b1;
                mem_addr  = {alu_result[31:2], 2'b00};
                mem_wdata = st_wdata;
                mem_wstrb = mem_write ? st_wstrb : 4'b0000;
            end
            default: ;
        endcase
    end

    // Register write: in EXEC for ALU-class instructions, in MEM_W for loads.
    assign rf_we = reg_write & ( (state == S_EXEC && !mem_read && !mem_write)
                               | (state == S_MEM_W) );

    assign retire    = (state == S_EXEC && !mem_read && !mem_write)
                     | (state == S_MEM  &&  mem_write)
                     | (state == S_MEM_W);
    assign retire_pc = pc;

    // ---------------- FSM ----------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_FETCH;
            pc    <= 32'd0;
            ir    <= 32'd0;
        end else begin
            case (state)
                S_FETCH:   state <= S_FETCH_W;
                S_FETCH_W: begin ir <= mem_rdata; state <= S_EXEC; end
                S_EXEC: begin
                    if (mem_read | mem_write) state <= S_MEM;
                    else begin pc <= next_pc; state <= S_FETCH; end
                end
                S_MEM: begin
                    if (mem_read) state <= S_MEM_W;
                    else begin pc <= next_pc; state <= S_FETCH; end
                end
                S_MEM_W: begin pc <= next_pc; state <= S_FETCH; end
                default:   state <= S_FETCH;
            endcase
        end
    end
endmodule
