`timescale 1ns / 1ps
`include "GEMM_Array.svh"
`include "GLOBAL_CONST.svh"

module mem_BUFFER (
    // ===| Clock & Reset |======================================
    input logic clk_core,  // 400MHz
    input logic rst_n_core,
    input logic clk_axi,  // 250MHz
    input logic rst_axi_n,

    // ===| ACP Ports (FMAP/KV) |================================
    axis_if.slave  S_AXIS_ACP_FMAP,   // [RX] Data from DDR4 to NPU
    axis_if.master M_AXIS_ACP_RESULT, // [TX] Data from NPU to DDR4

    axis_if.master M_CORE_ACP_RX,  // [RX] Converted to 400MHz Core
    axis_if.slave  S_CORE_ACP_TX   // [TX] Coming from 400MHz Core
);

  //fine Tiny Depth for BRAM CDC
  localparam int BRAM_FIFO_DEPTH = 32;

  // [1] ACP RX FIFO (CDC only: AXI -> Core)
  // FMAP/KV is handled by the massive L2 URAM Cache, so these CDC FIFOs stay TINY.
  xpm_fifo_axis #(
      .FIFO_DEPTH      (BRAM_FIFO_DEPTH),
      .TDATA_WIDTH     (128),
      .FIFO_MEMORY_TYPE("block"),             // BRAM is enough for CDC
      .CLOCKING_MODE   ("independent_clock")
  ) u_acp_rx_fifo (
      .s_aclk(clk_axi),
      .s_aresetn(rst_axi_n),
      .s_axis_tdata(S_AXIS_ACP_FMAP.tdata),
      .s_axis_tvalid(S_AXIS_ACP_FMAP.tvalid),
      .s_axis_tready(S_AXIS_ACP_FMAP.tready),

      .m_aclk(clk_core),
      .m_axis_tdata(M_CORE_ACP_RX.tdata),
      .m_axis_tvalid(M_CORE_ACP_RX.tvalid),
      .m_axis_tready(M_CORE_ACP_RX.tready)
  );

  // [2] ACP TX FIFO (CDC only: Core -> AXI)
  xpm_fifo_axis #(
      .FIFO_DEPTH(BRAM_FIFO_DEPTH),
      .TDATA_WIDTH(128),
      .FIFO_MEMORY_TYPE("block"),
      .CLOCKING_MODE("independent_clock")
  ) u_acp_tx_fifo (
      // a flows FROM the Core domain...
      .s_aclk(clk_core),
      .s_aresetn(rst_n_core),
      .s_axis_tdata(S_CORE_ACP_TX.tdata),
      .s_axis_tvalid(S_CORE_ACP_TX.tvalid),
      .s_axis_tready(S_CORE_ACP_TX.tready),

      //.TO the AXI domain (DDR4)
      .m_aclk(clk_axi),
      .m_axis_tdata(M_AXIS_ACP_RESULT.tdata),
      .m_axis_tvalid(M_AXIS_ACP_RESULT.tvalid),
      .m_axis_tready(M_AXIS_ACP_RESULT.tready)
  );

endmodule
