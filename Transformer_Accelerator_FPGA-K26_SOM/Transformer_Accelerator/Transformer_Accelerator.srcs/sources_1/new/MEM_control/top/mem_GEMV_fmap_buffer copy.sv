`timescale 1ns / 1ps

module dual_input_fifo #(
    parameter int DATA_WIDTH = 264,
    parameter int FIFO_DEPTH = 64
) (
    input logic clk,
    input logic rst_n,

    // ==========================================
    // Input 1: [FROM] Global Cache
    // ==========================================
    input logic global_wr_en,
    input logic [DATA_WIDTH-1:0] global_wr_data,
    output logic global_grant,  // when 1 write FIFO / 0: wait

    // ==========================================
    // Input 2: L2 Cache [FROM]result port
    // ==========================================
    input logic l2_wr_en,
    input logic [DATA_WIDTH-1:0] l2_wr_data,
    output logic l2_grant,  // when 1 write FIFO / 0: wait

    // ==========================================
    // Output: To pipeline
    // ==========================================
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                  empty,
    output logic                  full
);

  // ===| internal FIFO signal |===
  logic                  fifo_wr_en;
  logic [DATA_WIDTH-1:0] fifo_wr_data;

  // FIFO internal memory & pointer
  localparam int ADDR_WIDTH = $clog2(FIFO_DEPTH);
  (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem_array[0:FIFO_DEPTH-1];
  logic [ADDR_WIDTH:0] wr_ptr, rd_ptr;

  assign empty = (wr_ptr == rd_ptr);
  assign full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                 (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

  // ===| (Arbiter & MUX) |===
  // 1: L2 Cache pipeline res
  // 2: Global Cache
  always_comb begin
    fifo_wr_en   = 1'b0;
    fifo_wr_data = '0;
    global_grant = 1'b0;
    l2_grant     = 1'b0;

    if (!full) begin
      if (l2_wr_en) begin
        // always accept when L2 write requested
        fifo_wr_en   = 1'b1;
        fifo_wr_data = l2_wr_data;
        l2_grant     = 1'b1;
      end else if (global_wr_en) begin
        // accpect only when L2 has no request
        fifo_wr_en   = 1'b1;
        fifo_wr_data = global_wr_data;
        global_grant = 1'b1;
      end
    end
  end

  // ===| FIFO memory write and pointer update |===
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr <= '0;
    end else if (fifo_wr_en) begin
      mem_array[wr_ptr[ADDR_WIDTH-1:0]] <= fifo_wr_data;
      wr_ptr <= wr_ptr + 1;
    end
  end

  // ===| FIFO memory read and pointer update |===
  // NOT First-Word Fall-Through (FWFT)
  // normal sync Read (next clk data out when Read Enable)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_ptr  <= '0;
      rd_data <= '0;
    end else if (rd_en && !empty) begin
      rd_data <= mem_array[rd_ptr[ADDR_WIDTH-1:0]];
      rd_ptr  <= rd_ptr + 1;
    end
  end

endmodule
