`timescale 1ns / 1ps

//GEMM

GEMM연산은 클럭당 featureMAP을 32개 = 128개 필요로 한다.


module fmap_l2_fifo #(
    // --- Data Format Parameters ---
    parameter int MANT_WIDTH = 8,  // Width of 1 mantissa
    parameter int EXP_WIDTH  = 8,  // Width of shared Emax
    parameter int GROUP_SIZE = 32, // 32 mantissas per group

    // --- FIFO Depth & Watermark Parameters ---
    parameter int FIFO_DEPTH     = 64,
    parameter int HIGH_WATERMARK = 57,  // Approx 90% of 64
    parameter int LOW_WATERMARK  = 6    // Approx 10% of 64
) (
    input logic clk,
    input logic rst_n,

    // ==========================================
    // Input Port: From Global Cache
    // ==========================================
    input logic IN_global_wr_en,
    input logic [(GROUP_SIZE * MANT_WIDTH) + EXP_WIDTH - 1:0] IN_global_data,

    // Flow control signal to Global Cache (1: Send data, 0: Stop sending)
    output logic OUT_global_fetch_req,

    // ==========================================
    // Output Port: To Compute Pipeline
    // ==========================================
    input logic IN_pipe_rd_en,
    output logic [(GROUP_SIZE * MANT_WIDTH) + EXP_WIDTH - 1:0] OUT_pipe_data,

    // Status flags
    output logic OUT_empty,
    output logic OUT_full
);

  // --- Internal Constants & Types ---
  localparam int DATA_WIDTH = (GROUP_SIZE * MANT_WIDTH) + EXP_WIDTH;
  localparam int ADDR_WIDTH = $clog2(FIFO_DEPTH);

  // BRAM inference attribute
  (* ram_style = "block" *)logic [DATA_WIDTH-1:0] mem_array  [0:FIFO_DEPTH-1];

  // --- FIFO Pointers (Extra bit for full/empty condition calculation) ---
  logic [  ADDR_WIDTH:0] wr_ptr;
  logic [  ADDR_WIDTH:0] rd_ptr;
  logic [  ADDR_WIDTH:0] data_count;

  // --- Status Logic ---
  // Calculate how many items are currently in the FIFO
  assign data_count = wr_ptr - rd_ptr;

  assign OUT_empty  = (data_count == 0);
  assign OUT_full   = (data_count == FIFO_DEPTH);

  // ==========================================
  // Write Logic (Global Cache -> FIFO)
  // ==========================================
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr <= '0;
    end else if (IN_global_wr_en && !OUT_full) begin
      mem_array[wr_ptr[ADDR_WIDTH-1:0]] <= IN_global_data;
      wr_ptr <= wr_ptr + 1;
    end
  end

  // ==========================================
  // Read Logic (FIFO -> Compute Pipeline)
  // ==========================================
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_ptr        <= '0;
      OUT_pipe_data <= '0;
    end else if (IN_pipe_rd_en && !OUT_empty) begin
      OUT_pipe_data <= mem_array[rd_ptr[ADDR_WIDTH-1:0]];
      rd_ptr        <= rd_ptr + 1;
    end
  end

  // ==========================================
  // Flow Control Logic (Hysteresis / Watermark)
  // ==========================================
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      // Initially, the FIFO is empty, so request data from Global Cache
      OUT_global_fetch_req <= 1'b1;
    end else begin
      if (data_count >= HIGH_WATERMARK) begin
        // Turn OFF request when FIFO reaches 90% (High Watermark)
        OUT_global_fetch_req <= 1'b0;
      end else if (data_count <= LOW_WATERMARK) begin
        // Turn ON request when FIFO drains to 10% (Low Watermark)
        OUT_global_fetch_req <= 1'b1;
      end
      // Note: If data_count is between LOW and HIGH, it holds the previous state.
    end
  end

endmodule
