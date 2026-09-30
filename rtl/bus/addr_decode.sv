`timescale 1ns / 1ps
//
// Address decode and read select. Routes the granted access to the SRAM or to
// MMIO, and selects which target's read data goes back on bus_rdata.
//
// Parameters
//   RAW   RAM byte address bits. SRAM word address is RAW-2 bits.
//
// Behaviour
//   s_en    = b_valid & ~b_addr[12]
//   s_addr  = b_addr[RAW-1:2]
//   s_wdata = b_wdata,  s_wstrb = b_wstrb
//
//   m_en    = b_valid &  b_addr[12]
//   m_addr  = b_addr[4:2]            register select
//   m_we    = |b_wstrb
//   m_wdata = b_wdata[7:0]           every MMIO register is word aligned
//   m_core  = (b_src == 2)           1 when core 1's data port is the source
//
//   sel_q  <= b_addr[12] every cycle
//   bus_rdata = sel_q ? m_rdata : s_rdata
//
//   Both targets return read data one cycle after the access, so bus_rdata is
//   valid exactly one cycle after the grant.
//
module addr_decode #(
    parameter int RAW = 10
) (
    input  logic           clk,

    input  logic           b_valid,
    input  logic [12:0]    b_addr,
    input  logic [31:0]    b_wdata,
    input  logic [3:0]     b_wstrb,
    input  logic [2:0]     b_src,

    output logic           s_en,
    output logic [RAW-3:0] s_addr,
    output logic [31:0]    s_wdata,
    output logic [3:0]     s_wstrb,
    input  logic [31:0]    s_rdata,

    output logic           m_en,
    output logic [2:0]     m_addr,
    output logic           m_we,
    output logic [7:0]     m_wdata,
    output logic           m_core,
    input  logic [31:0]    m_rdata,

    output logic [31:0]    bus_rdata
);
    // Stub: outputs tied off until implemented.
    assign s_en      = 1'b0;
    assign s_addr    = '0;
    assign s_wdata   = '0;
    assign s_wstrb   = '0;
    assign m_en      = 1'b0;
    assign m_addr    = '0;
    assign m_we      = 1'b0;
    assign m_wdata   = '0;
    assign m_core    = 1'b0;
    assign bus_rdata = '0;
endmodule
