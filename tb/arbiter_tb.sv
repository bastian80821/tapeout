`timescale 1ns/1ps
//
// Unit testbench for arbiter. Drive the five request bundles, check grants and
// the forwarded b_* bundle against the rules in rtl/bus/arbiter.sv.
//
module arbiter_tb;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic        loading = 0;
    logic        boot_req = 0;  logic [12:0] boot_addr = 0; logic [31:0] boot_wdata = 0; logic [3:0] boot_wstrb = 4'b1111;
    logic        d0_req = 0;    logic [12:0] d0_addr = 0;   logic [31:0] d0_wdata = 0;   logic [3:0] d0_wstrb = 0;   logic d0_gnt;
    logic        d1_req = 0;    logic [12:0] d1_addr = 0;   logic [31:0] d1_wdata = 0;   logic [3:0] d1_wstrb = 0;   logic d1_gnt;
    logic        ic0_req = 0;   logic [12:0] ic0_addr = 0;  logic [31:0] ic0_wdata = 0;  logic [3:0] ic0_wstrb = 0;  logic ic0_gnt;
    logic        ic1_req = 0;   logic [12:0] ic1_addr = 0;  logic [31:0] ic1_wdata = 0;  logic [3:0] ic1_wstrb = 0;  logic ic1_gnt;
    logic        b_valid;
    logic [12:0] b_addr;
    logic [31:0] b_wdata;
    logic [3:0]  b_wstrb;
    logic [2:0]  b_src;

    arbiter dut (.*);

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
            if (n_checks == 0)    $display("FAIL    arbiter  no checks written yet");
            else if (n_fail != 0) $display("FAIL    arbiter  %0d of %0d checks failed", n_fail, n_checks);
            else                  $display("PASS    arbiter  %0d checks", n_checks);
            if (n_checks == 0 || n_fail != 0) $fatal(1, "Simulation failed");
            $finish;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;

        // Write tests here. Suggested:
        //   - one requester alone is granted in the same cycle
        //   - never more than one grant per cycle, over many random cycles
        //   - four requesters held high: each granted within 4 cycles
        //   - loading = 1: only boot is granted, cores are ignored
        //   - b_addr, b_wdata, b_wstrb, b_src match the granted bundle

        report;
    end
endmodule
