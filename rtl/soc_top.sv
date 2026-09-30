`timescale 1ns / 1ps
//
// Dual core SoC top level. Declares every net between blocks.
//
// Parameters
//   NREGS      16 = RV32E, 32 = RV32I.
//   RAW        RAM byte address bits. 10 = 1 KiB, 11 = 2 KiB (Plan A).
//   CLK_FREQ   system clock in Hz, sets the UART baud divider.
//   BAUD_RATE  UART baud rate.
//
// Address map (13-bit bus address, b_addr[12] selects MMIO)
//   0x0000              RAM
//   0x1000              UART_DATA    write: transmit the low byte
//   0x1004              UART_STATUS  read: bit 0 = transmitter busy
//   0x1008              LOCK         read: old value, then set; write: clear
//   0x100C              CORE_ID      read: 0 or 1
//   0x1010              EXIT         write: set this core's exit flag
//
// Bus requesters, by b_src index
//   0 bootloader, 1 core 0 data, 2 core 1 data, 3 core 0 I-cache, 4 core 1 I-cache
//
module soc_top #(
    parameter int NREGS     = 16,
    parameter int RAW       = 10,
    parameter int CLK_FREQ  = 50_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst,           // synchronous, active high
    input  logic       uart_rx,
    output logic       uart_tx,
    output logic       done,          // both cores have written EXIT

    // Debug, left unconnected on the chip
    output logic       dbg_core_run,
    output logic       dbg_lock,
    output logic [1:0] dbg_exit
);
    localparam int SAW = RAW - 2;     // SRAM word address bits

    // ---------------- serial receive and bootloader ----------------
    logic [7:0]  rx_data;
    logic        rx_valid;

    logic        boot_req;
    logic [12:0] boot_addr;
    logic [31:0] boot_wdata;
    logic [3:0]  boot_wstrb;
    logic        loading, core_run;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart_rx (
        .clk(clk), .rst(rst), .rx(uart_rx),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    bootloader u_boot (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .boot_req(boot_req), .boot_addr(boot_addr), .boot_wdata(boot_wdata),
        .core_run(core_run), .loading(loading)
    );

    assign boot_wstrb = 4'b1111;

    // ---------------- global control ----------------
    logic core_rst, flush;
    assign core_rst = rst | ~core_run;
    assign flush    = ~core_run;

    // ---------------- shared read data ----------------
    logic [31:0] bus_rdata;

    // ---------------- core 0 ----------------
    logic        i0_req, i0_valid;
    logic [12:0] i0_addr;
    logic [31:0] i0_rdata;
    logic        d0_req, d0_gnt;
    logic [12:0] d0_addr;
    logic [31:0] d0_wdata;
    logic [3:0]  d0_wstrb;
    logic        c0_retire;
    logic [31:0] c0_retire_pc;

    core #(.NREGS(NREGS)) u_core0 (
        .clk(clk), .rst(core_rst),
        .i_req(i0_req), .i_addr(i0_addr), .i_valid(i0_valid), .i_rdata(i0_rdata),
        .d_req(d0_req), .d_addr(d0_addr), .d_wdata(d0_wdata), .d_wstrb(d0_wstrb),
        .d_gnt(d0_gnt), .d_rdata(bus_rdata),
        .retire(c0_retire), .retire_pc(c0_retire_pc)
    );

    logic        ic0_req, ic0_gnt;
    logic [12:0] ic0_addr;
    logic [31:0] ic0_wdata;
    logic [3:0]  ic0_wstrb;

    icache #(.RAW(RAW)) u_icache0 (
        .clk(clk), .rst(rst), .flush(flush),
        .i_req(i0_req), .i_addr(i0_addr), .i_valid(i0_valid), .i_rdata(i0_rdata),
        .ic_req(ic0_req), .ic_addr(ic0_addr), .ic_wdata(ic0_wdata), .ic_wstrb(ic0_wstrb),
        .ic_gnt(ic0_gnt), .bus_rdata(bus_rdata)
    );

    // ---------------- core 1 ----------------
    logic        i1_req, i1_valid;
    logic [12:0] i1_addr;
    logic [31:0] i1_rdata;
    logic        d1_req, d1_gnt;
    logic [12:0] d1_addr;
    logic [31:0] d1_wdata;
    logic [3:0]  d1_wstrb;
    logic        c1_retire;
    logic [31:0] c1_retire_pc;

    core #(.NREGS(NREGS)) u_core1 (
        .clk(clk), .rst(core_rst),
        .i_req(i1_req), .i_addr(i1_addr), .i_valid(i1_valid), .i_rdata(i1_rdata),
        .d_req(d1_req), .d_addr(d1_addr), .d_wdata(d1_wdata), .d_wstrb(d1_wstrb),
        .d_gnt(d1_gnt), .d_rdata(bus_rdata),
        .retire(c1_retire), .retire_pc(c1_retire_pc)
    );

    logic        ic1_req, ic1_gnt;
    logic [12:0] ic1_addr;
    logic [31:0] ic1_wdata;
    logic [3:0]  ic1_wstrb;

    icache #(.RAW(RAW)) u_icache1 (
        .clk(clk), .rst(rst), .flush(flush),
        .i_req(i1_req), .i_addr(i1_addr), .i_valid(i1_valid), .i_rdata(i1_rdata),
        .ic_req(ic1_req), .ic_addr(ic1_addr), .ic_wdata(ic1_wdata), .ic_wstrb(ic1_wstrb),
        .ic_gnt(ic1_gnt), .bus_rdata(bus_rdata)
    );

    // ---------------- arbiter ----------------
    logic        b_valid;
    logic [12:0] b_addr;
    logic [31:0] b_wdata;
    logic [3:0]  b_wstrb;
    logic [2:0]  b_src;

    arbiter u_arbiter (
        .clk(clk), .rst(rst), .loading(loading),
        .boot_req(boot_req), .boot_addr(boot_addr), .boot_wdata(boot_wdata), .boot_wstrb(boot_wstrb),
        .d0_req(d0_req),   .d0_addr(d0_addr),   .d0_wdata(d0_wdata),   .d0_wstrb(d0_wstrb),   .d0_gnt(d0_gnt),
        .d1_req(d1_req),   .d1_addr(d1_addr),   .d1_wdata(d1_wdata),   .d1_wstrb(d1_wstrb),   .d1_gnt(d1_gnt),
        .ic0_req(ic0_req), .ic0_addr(ic0_addr), .ic0_wdata(ic0_wdata), .ic0_wstrb(ic0_wstrb), .ic0_gnt(ic0_gnt),
        .ic1_req(ic1_req), .ic1_addr(ic1_addr), .ic1_wdata(ic1_wdata), .ic1_wstrb(ic1_wstrb), .ic1_gnt(ic1_gnt),
        .b_valid(b_valid), .b_addr(b_addr), .b_wdata(b_wdata), .b_wstrb(b_wstrb), .b_src(b_src)
    );

    // ---------------- address decode and read select ----------------
    logic           s_en;
    logic [SAW-1:0] s_addr;
    logic [31:0]    s_wdata, s_rdata;
    logic [3:0]     s_wstrb;

    logic           m_en, m_we, m_core;
    logic [2:0]     m_addr;
    logic [7:0]     m_wdata;
    logic [31:0]    m_rdata;

    addr_decode #(.RAW(RAW)) u_decode (
        .clk(clk),
        .b_valid(b_valid), .b_addr(b_addr), .b_wdata(b_wdata), .b_wstrb(b_wstrb), .b_src(b_src),
        .s_en(s_en), .s_addr(s_addr), .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_rdata(s_rdata),
        .m_en(m_en), .m_addr(m_addr), .m_we(m_we), .m_wdata(m_wdata), .m_core(m_core), .m_rdata(m_rdata),
        .bus_rdata(bus_rdata)
    );

    // ---------------- SRAM ----------------
    sram_mem #(.WORDS(1 << SAW)) u_sram (
        .clk(clk),
        .en(s_en), .addr(s_addr), .wdata(s_wdata), .wstrb(s_wstrb),
        .rdata(s_rdata)
    );

    // ---------------- MMIO and serial transmit ----------------
    logic       tx_start, tx_busy;
    logic [7:0] tx_data;

    mmio u_mmio (
        .clk(clk), .rst(rst), .core_run(core_run),
        .m_en(m_en), .m_addr(m_addr), .m_we(m_we), .m_wdata(m_wdata), .m_core(m_core),
        .m_rdata(m_rdata),
        .tx_start(tx_start), .tx_data(tx_data), .tx_busy(tx_busy),
        .done(done), .dbg_lock(dbg_lock), .dbg_exit(dbg_exit)
    );

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart_tx (
        .clk(clk), .rst(rst),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx(uart_tx), .tx_busy(tx_busy)
    );

    assign dbg_core_run = core_run;
endmodule