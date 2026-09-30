`timescale 1ns/1ps
//
// Unit testbench for addr_decode. Check routing to SRAM and MMIO, m_core,
// and that bus_rdata selects the target of the previous cycle's access.
//
module addr_decode_tb;
    parameter int RAW = 10;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic           b_valid = 0;
    logic [12:0]    b_addr = 0;
    logic [31:0]    b_wdata = 0;
    logic [3:0]     b_wstrb = 0;
    logic [2:0]     b_src = 0;
    logic           s_en;
    logic [RAW-3:0] s_addr;
    logic [31:0]    s_wdata;
    logic [3:0]     s_wstrb;
    logic [31:0]    s_rdata = 32'h5555_5555;
    logic           m_en, m_we, m_core;
    logic [2:0]     m_addr;
    logic [7:0]     m_wdata;
    logic [31:0]    m_rdata = 32'hAAAA_AAAA;
    logic [31:0]    bus_rdata;

    addr_decode #(.RAW(RAW)) dut (.*);

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
            if (n_checks == 0)    $display("FAIL    addr_decode  no checks written yet");
            else if (n_fail != 0) $display("FAIL    addr_decode  %0d of %0d checks failed", n_fail, n_checks);
            else                  $display("PASS    addr_decode  %0d checks", n_checks);
            if (n_checks == 0 || n_fail != 0) $fatal(1, "Simulation failed");
            $finish;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;

        // Write tests here. Suggested:
        //   - b_valid = 0: s_en and m_en both low for any address
        //   - RAM address: s_en high, s_addr = b_addr[RAW-1:2], m_en low
        //   - 0x1008 read from b_src = 2: m_en, m_addr = 2, m_we = 0, m_core = 1
        //   - bus_rdata shows s_rdata or m_rdata according to the previous
        //     cycle's b_addr[12]

        report;
    end
endmodule
