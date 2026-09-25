`timescale 1ns/1ps
// Runs a riscv-tests hex image on core_mc and reports PASS / FAIL / TIMEOUT.
//
// Memory map (unified, von Neumann):
//   0x0000 - 0x0FFF   RAM, 1024 words, SYNCHRONOUS read (models an SRAM macro)
//   0x1000            UART data   (write: transmit low byte)
//   0x1004            UART status (read: bit 0 = busy; always 0 here)
//
// riscv_test.h prints 'P' on pass, or 'F' plus two hex digits of TESTNUM on
// failure, then halts in a self-jump. This bench watches the memory port.
module core_mc_tb;

    parameter integer NREGS   = 32;
    parameter integer TIMEOUT = 400000;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    wire        mem_en, retire;
    wire [31:0] mem_addr, mem_wdata, retire_pc;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;

    core_mc #(.NREGS(NREGS)) dut (
        .clk(clk), .rst(rst),
        .mem_en(mem_en), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .retire(retire), .retire_pc(retire_pc)
    );

    // ---------------- unified memory, synchronous read ----------------
    localparam integer WORDS = 1024;
    reg [31:0] ram [0:WORDS-1];

    wire [31:0] widx     = mem_addr >> 2;
    wire        sel_ram  = (mem_addr < (WORDS*4));
    wire        sel_uart = (mem_addr >= 32'h1000) && (mem_addr < 32'h2000);
    reg  [31:0] wmask;

    always @(posedge clk) begin
        if (mem_en && sel_ram) begin
            // Byte strobes applied as a mask: iverilog mishandles part-selects
            // on an array element with a variable index.
            wmask = {{8{mem_wstrb[3]}}, {8{mem_wstrb[2]}},
                     {8{mem_wstrb[1]}}, {8{mem_wstrb[0]}}};
            ram[widx] <= (ram[widx] & ~wmask) | (mem_wdata & wmask);
            mem_rdata <= ram[widx];
        end else if (mem_en && sel_uart) begin
            mem_rdata <= 32'd0;          // UART status: never busy
        end
    end

    // ---------------- UART monitor ----------------
    reg        done   = 0;
    reg        failed = 0;
    reg [7:0]  c0 = 8'h00, c1 = 8'h00, c2 = 8'h00;
    integer    nchar  = 0;

    always @(posedge clk) begin
        if (!rst && mem_en && sel_uart && (mem_wstrb != 4'b0000)
                 && (mem_addr[11:0] == 12'h000)) begin
            if      (nchar == 0) c0 = mem_wdata[7:0];
            else if (nchar == 1) c1 = mem_wdata[7:0];
            else if (nchar == 2) c2 = mem_wdata[7:0];
            nchar = nchar + 1;
            if (mem_wdata[7:0] == "P") done = 1;
            if (c0 == "F" && nchar >= 3) begin done = 1; failed = 1; end
        end
    end

    // ---------------- run ----------------
    integer      cycles = 0;
    integer      i;
    reg [8*64:1] hexfile;

    initial begin
        if (!$value$plusargs("HEX=%s", hexfile)) hexfile = "test.hex";
        for (i = 0; i < WORDS; i = i + 1) ram[i] = 32'h0;
        $readmemh(hexfile, ram);

        repeat (4) @(posedge clk);
        rst = 0;

        while (!done && cycles < TIMEOUT) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!done)
            $display("TIMEOUT %0s  after %0d cycles (pc=%08x)", hexfile, cycles, retire_pc);
        else if (failed)
            $display("FAIL    %0s  testnum=%c%c", hexfile, c1, c2);
        else
            $display("PASS    %0s  (%0d cycles)", hexfile, cycles);
        $finish;
    end
endmodule
