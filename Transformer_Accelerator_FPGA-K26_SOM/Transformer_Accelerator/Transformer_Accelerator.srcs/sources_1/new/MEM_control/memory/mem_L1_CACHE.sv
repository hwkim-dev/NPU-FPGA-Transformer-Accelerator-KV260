`timescale 1ns / 1ps
`include "gemm_Array.svh"
`include "GLOBAL_CONST.svh"


module mem_L1_CACHE #(
    parameter DATA_WIDTH = `HP_PORT_SINGLE_WIDTH
) (
    input logic clk,
    input logic rst_n,

    axis_if.slave IN_HP0,
    axis_if.slave IN_HP1,
    axis_if.slave IN_HP2,
    axis_if.slave IN_HP3,

    output logic [DATA_WIDTH-1:0] weight_fifo_data [0:`AXI_WEIGHT_PORT_CNT-1],
    output logic                  weight_fifo_valid[0:`AXI_WEIGHT_PORT_CNT-1],
    output logic                  weight_fifo_ready[0:`AXI_WEIGHT_PORT_CNT-1]
);

endmodule
