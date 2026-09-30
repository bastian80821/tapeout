`timescale 1ns / 1ps
//
// Memory-mapped registers. Answers every access with one cycle of latency, like
// the SRAM, so the bus never waits.
//
//   m_addr  address  name         read                       write
//   0       0x1000   UART_DATA    0                          tx_start pulse, tx_data = m_wdata
//   1       0x1004   UART_STATUS  bit 0 = tx_busy            ignored
//   2       0x1008   LOCK         bit 0 = lock, then lock=1  lock = 0
//   3       0x100C   CORE_ID      bit 0 = m_core             ignored
//   4       0x1010   EXIT         bits 1:0 = exit            exit[m_core] = 1
//   5       0x1014   LOCK_PEEK    bit 0 = lock (optional)    ignored
//   6, 7             unused       0                          ignored
//
// m_rdata is registered: it carries the read result of the previous cycle's
// access. lock and exit clear while core_run is low. done = exit[0] & exit[1].
//
module mmio (
    input  logic        clk,
    input  logic        rst,
    input  logic        core_run,

    input  logic        m_en,
    input  logic [2:0]  m_addr,
    input  logic        m_we,
    input  logic [7:0]  m_wdata,
    input  logic        m_core,
    output logic [31:0] m_rdata,

    output logic        tx_start,
    output logic [7:0]  tx_data,
    input  logic        tx_busy,

    output logic        done,
    output logic        dbg_lock,
    output logic [1:0]  dbg_exit
);
    // Stub: outputs tied off until implemented.
    assign m_rdata  = '0;
    assign tx_start = 1'b0;
    assign tx_data  = '0;
    assign done     = 1'b0;
    assign dbg_lock = 1'b0;
    assign dbg_exit = '0;
endmodule
