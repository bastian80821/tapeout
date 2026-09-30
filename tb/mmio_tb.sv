`timescale 1ns/1ps
//
// Unit testbench for mmio. Directed access to every register, with read data
// checked one cycle after the access.
//
module mmio_tb;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic        core_run = 1;
    logic        m_en = 0, m_we = 0, m_core = 0;
    logic [2:0]  m_addr = 0;
    logic [7:0]  m_wdata = 0;
    logic [31:0] m_rdata;
    logic        tx_start;
    logic [7:0]  tx_data;
    logic        tx_busy = 0;
    logic        done, dbg_lock;
    logic [1:0]  dbg_exit;

    mmio dut (.*);

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
            if (n_checks == 0)    $display("FAIL    mmio  no checks written yet");
            else if (n_fail != 0) $display("FAIL    mmio  %0d of %0d checks failed", n_fail, n_checks);
            else                  $display("PASS    mmio  %0d checks", n_checks);
            if (n_checks == 0 || n_fail != 0) $fatal(1, "Simulation failed");
            $finish;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;

        // Write tests here. Suggested:
        //   - LOCK read returns 0 then 1; write clears it
        //   - CORE_ID returns m_core
        //   - EXIT from each core; done only after both
        //   - core_run low clears lock and exit
        //   - UART_DATA write pulses tx_start for one cycle with tx_data

        report;
    end
endmodule
