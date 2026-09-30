`timescale 1ns/1ps
//
// Unit testbench for sram_mem. Byte, halfword and word writes to every lane,
// read back one cycle later.
//
module sram_mem_tb;
    parameter int WORDS = 256;
    localparam int AW = $clog2(WORDS);

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic          en = 0;
    logic [AW-1:0] addr = 0;
    logic [31:0]   wdata = 0;
    logic [3:0]    wstrb = 0;
    logic [31:0]   rdata;

    sram_mem #(.WORDS(WORDS)) dut (.*);

    // ---------------- checks ----------------
    integer n_checks = 0, n_fail = 0;
    task automatic check(input logic cond, input [8*64:1] what);
        begin
            n_checks = n_checks + 1;
            if (!cond) begin
                n_fail = n_fail + 1;
                $display("  check failed at %0t: %0s", $time, what);
            end
        end
    endtask

    task automatic report;
        begin
            if (n_checks == 0)    $display("FAIL    sram_mem  no checks written yet");
            else if (n_fail != 0) $display("FAIL    sram_mem  %0d of %0d checks failed", n_fail, n_checks);
            else                  $display("PASS    sram_mem  %0d checks", n_checks);
            if (n_checks == 0 || n_fail != 0) $fatal(1, "Simulation failed");
            $finish;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;

        // Write tests here. Suggested:
        //   - write a word, read it back the next cycle
        //   - wstrb = 0001, 0010, 0100, 1000: only that lane changes
        //   - en = 0 with wstrb set: nothing is written
        //   - first and last address

        report;
    end
endmodule
