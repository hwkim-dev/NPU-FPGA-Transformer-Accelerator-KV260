`timescale 1ns / 1ps
`include "GEMM_Array.svh"
`include "npu_interfaces.svh"
`include "GLOBAL_CONST.svh"

import isa_pkg::*;

module ctrl_npu_decoder (
    input logic clk,
    input logic rst_n,
    input logic [`ISA_WIDTH-1:0] IN_raw_instruction,
    input logic raw_instruction_pop_valid,

    output logic OUT_fetch_PC_ready,


    //output instruction_t OUT_inst,
    output logic OUT_GEMV_op_x64_valid;
    //output GEMV_op_x64_t  OUT_GEMV_op_x64;

    output logic OUT_GEMM_op_x64_valid;
    //output GEMM_op_x64_t  OUT_GEMM_op_x64;

    output logic OUT_memcpy_op_x64_valid;
    //output memcpy_op_x64_t OUT_memcpy_op_x64;

    output logic OUT_memset_op_x64_valid;
    //output memcpy_op_x64_t OUT_memset_op_x64;
    output instruction_op_x64_t [59:0] OUT_op_x64;
);

  logic [3:0] OUT_valid;
  assign OUT_GEMV_op_x64_valid = OUT_valid[0];
  assign OUT_GEMM_op_x64_valid = OUT_valid[1];
  assign OUT_memcpy_op_x64_valid = OUT_valid[2];
  assign OUT_memset_op_x64_valid = OUT_valid[3];

  VLIW_instruction_x64 instruction_VLIW_x64;


  always_ff @(posedge clk) begin
    if(!rst_n) begin
      OUT_valid <= 3'b000;
      OUT_fetch_PC_ready <= `TRUE;
    end else begin
      if(raw_instruction_pop_valid) begin

        OUT_memcpy_VALID <= raw_instruction_pop_valid;
        OUT_op_x64 <= IN_raw_instruction[3 +:59];

      end else begin

        OUT_valid <= 3'b000;

      end
    end
  end

endmodule

/*
case (o_inst.opcode)
    OP_GEMV: begin
      OUT_GEMV_op_x64  <= GEMV_op_x64_t'(IN_raw_instruction[3 +:59]);
      OUT_valid <= 3'b0001;
    end
    OP_GEMM: begin
      OUT_GEMM_op_x64 <= GEMM_op_x64_t'(IN_raw_instruction[3 +:59]);
      OUT_valid <= 3'b0010;
    end
    OP_MEMCPY: begin
      OUT_memcpy_op_x64 <= memcpy_op_x64_t'(IN_raw_instruction[3 +:59]);
      OUT_valid <= 3'b0100;
    end
    OP_MEMSET: begin
      OUT_memset_op_x64 <= memset_op_x64_t'(IN_raw_instruction[3 +:59]);
      OUT_valid <= 3'b1000;
    end
    default: o_valid <= 1'b0;  // unknown opcode
endcase
*/