/*

Base_Address:

Dimension_Count:

Stride_Size:

Block_Size:

*/


`timescale 1ns / 1ps

module FMAP_AGU #(
    parameter ADDR_WIDTH = 32
) (
    input logic clk,
    input logic rst_n,
    input logic init,
    input logic step,


    input logic [ADDR_WIDTH-1:0] Base_Address,
    input logic [          15:0] Stride_Size,
    input logic [           7:0] Block_Size,
    input logic [          15:0] Col_Max,

    output logic [ADDR_WIDTH-1:0] OUT_Mem_Addr,
    output logic                  OUT_Addr_Valid
);

  logic [ADDR_WIDTH-1:0] current_addr;
  logic [ADDR_WIDTH-1:0] row_start_addr;
  logic [          15:0] col_cnt;

  assign OUT_Mem_Addr = current_addr;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      current_addr   <= '0;
      row_start_addr <= '0;
      col_cnt        <= '0;
      OUT_Addr_Valid <= 1'b0;
    end else if (init) begin
      current_addr   <= Base_Address;
      row_start_addr <= Base_Address;
      col_cnt        <= '0;
      OUT_Addr_Valid <= 1'b1;
    end else if (step) begin

      if (col_cnt + Block_Size >= Col_Max) begin
        current_addr   <= row_start_addr + Stride_Size;
        row_start_addr <= row_start_addr + Stride_Size;
        col_cnt        <= '0;
      end else begin

        current_addr <= current_addr + Block_Size;
        col_cnt      <= col_cnt + Block_Size;
      end
    end
  end

endmodule

