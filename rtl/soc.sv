`timescale 1ns / 1ps
//
// riskyC1-MC SoC : core, unified memory, bootloader and memory-mapped UART.
//
// Parameters
//   NREGS      16 = RV32E (default), 32 = RV32I.
//   MEM_WORDS  depth of the unified instruction/data memory, in 32-bit words.
//   CLK_FREQ   system clock in Hz, used to derive the UART baud divider.
//   BAUD_RATE  UART baud rate.
//
// Memory map
//   0x0000 .. MEM_WORDS*4-1   RAM, synchronous read
//   0x1000                    UART data   (write: transmit the low byte)
//   0x1004                    UART status (read: bit 0 = transmitter busy)
//
// Boot sequence
//   Memory contents are undefined at power-up. The bootloader owns the memory
//   port and holds the core in reset until a program has been received over
//   serial, then asserts core_run and releases it.
//
//   Host protocol, little-endian: 4 bytes of word count N, then N*4 bytes of
//   program. Sending a further 4 bytes restarts the load and re-resets the core.
//
// Memory arbitration
//   Two requesters: the bootloader while loading, the core afterwards. They are
//   mutually exclusive by construction, since the core is held in reset until
//   loading completes, so no round-robin arbiter is needed here. The dual-core
//   version replaces this mux with a real arbiter and adds the second core.
//
module soc #(
    parameter int NREGS     = 16,
    parameter int MEM_WORDS = 1024,
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  logic clk,
    input  logic rst,        // power-on reset, resets the bootloader too
    input  logic uart_rx_pin,
    output logic uart_tx_pin,

    // observability
    output logic core_run,
    output logic retire,
    output logic [31:0] retire_pc
);
    localparam int AW = $clog2(MEM_WORDS);

    // ---------------- serial receive and bootloader ----------------
    logic [7:0] rx_data;
    logic       rx_valid;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .rst(rst), .rx(uart_rx_pin),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    logic        boot_we, loading;
    logic [31:0] boot_waddr, boot_wdata;

    bootloader u_boot (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .imem_we(boot_we), .imem_waddr(boot_waddr), .imem_wdata(boot_wdata),
        .core_run(core_run), .loading(loading)
    );

    // ---------------- core ----------------
    logic        core_en;
    logic [31:0] core_addr, core_wdata;
    logic [3:0]  core_wstrb;
    logic [31:0] mem_rdata;

    core_mc #(.NREGS(NREGS)) u_core (
        .clk(clk),
        .rst(~core_run),                 // held in reset until the program lands
        .mem_en(core_en), .mem_addr(core_addr), .mem_wdata(core_wdata),
        .mem_wstrb(core_wstrb), .mem_rdata(mem_rdata),
        .retire(retire), .retire_pc(retire_pc)
    );

    // ---------------- request mux ----------------
    logic        req_en;
    logic [31:0] req_addr, req_wdata;
    logic [3:0]  req_wstrb;

    always_comb begin
        if (loading) begin
            req_en    = boot_we;
            req_addr  = boot_waddr;
            req_wdata = boot_wdata;
            req_wstrb = 4'b1111;
        end else begin
            req_en    = core_en;
            req_addr  = core_addr;
            req_wdata = core_wdata;
            req_wstrb = core_wstrb;
        end
    end

    // ---------------- address decode ----------------
    logic sel_ram, sel_uart;
    assign sel_ram  = (req_addr < (MEM_WORDS*4));
    assign sel_uart = (req_addr >= 32'h1000) && (req_addr < 32'h2000);

    // ---------------- memory ----------------
    logic [31:0] ram_rdata;

    sram_mem #(.WORDS(MEM_WORDS)) u_mem (
        .clk(clk),
        .en   (req_en & sel_ram),
        .addr (req_addr[AW+1:2]),
        .wdata(req_wdata),
        .wstrb(req_wstrb),
        .rdata(ram_rdata)
    );

    // ---------------- memory-mapped UART ----------------
    logic       tx_start, tx_busy;
    logic [7:0] tx_data;

    assign tx_start = req_en & sel_uart & (req_wstrb != 4'b0000)
                              & (req_addr[11:0] == 12'h000);
    assign tx_data  = req_wdata[7:0];

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx (
        .clk(clk), .rst(rst),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx(uart_tx_pin), .tx_busy(tx_busy)
    );

    // ---------------- read data mux ----------------
    // Registered to match the memory's one-cycle read latency, so every read on
    // this bus has the same timing regardless of target.
    logic sel_uart_q;
    always_ff @(posedge clk) sel_uart_q <= req_en & sel_uart;

    assign mem_rdata = sel_uart_q ? {31'd0, tx_busy} : ram_rdata;
endmodule
