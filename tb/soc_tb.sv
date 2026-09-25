`timescale 1ns/1ps
//
// SoC testbench. Exercises the real boot path: a program is shifted in over the
// serial line one bit at a time, the bootloader writes it to memory and releases
// the core, and the transmitted serial output is decoded and checked.
//
// Unlike core_mc_tb, nothing here reaches inside the design. The only contact
// with the DUT is the two serial pins, which is how the chip will actually be
// used.
//
// Select the image with +HEX=<path>.
//
module soc_tb;

    parameter integer NREGS     = 16;
    parameter integer MEM_WORDS = 1024;
    // Deliberately unrealistic baud divider: 20 clocks per bit keeps the
    // simulation short. The ratio is what matters, not the absolute numbers.
    parameter integer CLK_FREQ  = 2_000_000;
    parameter integer BAUD_RATE = 100_000;
    localparam integer CPB      = CLK_FREQ / BAUD_RATE;   // clocks per bit
    parameter integer TIMEOUT   = 3_000_000;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  rx_pin = 1'b1;          // idle high
    wire tx_pin, core_run, retire;
    wire [31:0] retire_pc;

    soc #(.NREGS(NREGS), .MEM_WORDS(MEM_WORDS),
          .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) dut (
        .clk(clk), .rst(rst),
        .uart_rx_pin(rx_pin), .uart_tx_pin(tx_pin),
        .core_run(core_run), .retire(retire), .retire_pc(retire_pc)
    );

    // ---------------- serial transmit (host -> DUT) ----------------
    task automatic send_byte(input [7:0] b);
        integer i;
        begin
            rx_pin = 1'b0;                      // start bit
            repeat (CPB) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx_pin = b[i];                  // LSB first
                repeat (CPB) @(posedge clk);
            end
            rx_pin = 1'b1;                      // stop bit
            repeat (CPB) @(posedge clk);
        end
    endtask

    // ---------------- serial receive (DUT -> host) ----------------
    reg [7:0] got [0:15];
    integer   ngot = 0;

    initial begin : rx_monitor
        reg [7:0] b;
        integer   i;
        forever begin
            @(negedge tx_pin);                  // start bit
            repeat (CPB + CPB/2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = tx_pin;
                repeat (CPB) @(posedge clk);
            end
            if (ngot < 16) got[ngot] = b;
            ngot = ngot + 1;
        end
    end

    // ---------------- load the image and run ----------------
    reg [31:0] img [0:MEM_WORDS-1];
    reg [8*256:1] hexfile;
    integer nwords, i, cycles;

    initial begin
        if (!$value$plusargs("HEX=%s", hexfile))
        hexfile = "C:/Users/Bmars/Desktop/riskyC1_MC/reference/riskyC1-mc/tests/rv32e_test.hex";
        for (i = 0; i < MEM_WORDS; i = i + 1) img[i] = 32'hFFFF_FFFF;
        $readmemh(hexfile, img);

        // how many words are actually in the file
        nwords = 0;
        for (i = 0; i < MEM_WORDS; i = i + 1)
            if (img[i] !== 32'hFFFF_FFFF) nwords = i + 1;

        repeat (10) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        // word count, little-endian
        send_byte(nwords[7:0]);
        send_byte(nwords[15:8]);
        send_byte(nwords[23:16]);
        send_byte(nwords[31:24]);
        // program
        for (i = 0; i < nwords; i = i + 1) begin
            send_byte(img[i][7:0]);
            send_byte(img[i][15:8]);
            send_byte(img[i][23:16]);
            send_byte(img[i][31:24]);
        end

        if (!core_run) begin
            $display("FAIL    %0s  bootloader did not release the core", hexfile);
            $finish;
        end

        cycles = 0;
        while (ngot == 0 && cycles < TIMEOUT) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (ngot == 0)
            $display("TIMEOUT %0s  no serial output after %0d cycles (pc=%08x)",
                     hexfile, cycles, retire_pc);
        else if (got[0] == "P")
            $display("PASS    %0s  (%0d words loaded, first char '%c')",
                     hexfile, nwords, got[0]);
        else
            $display("FAIL    %0s  first char '%c' (0x%02x)", hexfile, got[0], got[0]);
        $finish;
    end
endmodule
