`timescale 1ns / 1ps
`include "GEMM_Array.svh"
`include "GLOBAL_CONST.svh"

import isa_pkg::*;

module Global_Scheduler #(
) (
    input logic clk_core,
    input logic rst_n_core,

    input logic IN_GEMV_op_x64_valid,
    input logic IN_GEMM_op_x64_valid,
    input logic IN_memcpy_op_x64_valid,
    input logic IN_memset_op_x64_valid,

    instruction_op_x64_t instruction,

    output gemm_control_uop_t   OUT_GEMM_uop,
    output GEMV_control_uop_t   OUT_GEMV_uop,
    output memory_control_uop_t OUT_LOAD_uop,
    output memory_set_uop_t     OUT_mem_set_uop
);

  memory_control_uop_t LOAD_uop;
  memory_control_uop_t STORE_uop;

  GEMM_control_uop_t GEMM_uop;
  GEMV_control_uop_t GEMV_uop;
  memory_set_uop_t mem_set_uop;

  GEMV_op_x64_t GEMV_op_x64;
  memcpy_op_x64_t memcpy_op_x64;
  GEMM_op_x64_t GEMM_op_x64;
  memset_op_x64_t memset_op_x64;

  always_ff @(posedge clk_core) begin
    if (!rst_n_core) begin
    end else begin
      if (IN_memset_op_x64_valid) begin
        mem_set_uop <= '{
            which_cache   : memset_op_x64.dest_cache,
            dest_addr     : memset_op_x64.dest_addr,
            a_value       : memset_op_x64.a_value,
            b_value       : memset_op_x64.b_value,
            c_value       : memset_op_x64.c_value
        };
      end
    end
  end

  always_ff @(posedge clk_core) begin
    if (!rst_n_core) begin
    end else begin
      if (IN_memcpy_op_x64_valid) begin
        LOAD_uop <= '{
            data_dest      : {memcpy_op_x64.from_device, memcpy_op_x64.to_device},
            dest_addr      : memcpy_op_x64.dest_addr,
            src_addr       : memcpy_op_x64.src_addr,
            shape_ptr_addr : memcpy_op_x64.shape_ptr_addr,
            async          : memcpy_op_x64.async
        };
      end
    end
  end

  always_ff @(posedge clk_core) begin
    if (!rst_n_core) begin
    end else begin
      if (IN_GEMM_op_x64_valid) begin
        LOAD_uop <= '{
            data_dest      : from_L2_to_L1_GEMM,
            src_addr       : GEMM_op_x64.src_addr,
            shape_ptr_addr : GEMM_op_x64.shape_ptr_addr,
            async          : GEMM_op_x64.async
        };

        GEMM_uop <= '{
            flags_t         : GEMM_op_x64.flags,
            ptr_addr_t      : GEMM_op_x64.size_ptr_addr,
            parallel_lane_t : GEMM_op_x64.parallel_lane
        };

        STORE_uop <= '{
            data_dest      : from_GEMM_res_to_L2,
            dest_addr      : GEMM_op_x64.dest_addr,
            shape_ptr_addr : GEMM_op_x64.shape_ptr_addr,
            async          : GEMM_op_x64.async
        };
      end
    end
  end


  always_ff @(posedge clk_core) begin
    if (!rst_n_core) begin
    end else begin
      if (IN_GEMV_op_x64_valid) begin
        LOAD_uop <= '{
            data_dest      : from_L2_to_L1_GEMV,
            src_addr       : GEMM_op_x64.src_addr,
            shape_ptr_addr : GEMM_op_x64.shape_ptr_addr,
            async          : GEMM_op_x64.async
        };

        GEMM_uop <= '{
            flags_t         : GEMV_op_x64.flags,
            ptr_addr_t      : GEMV_op_x64.size_ptr_addr,
            parallel_lane_t : GEMV_op_x64.parallel_lane
        };

        STORE_uop <= '{
            data_dest      : from_GEMV_res_to_L2,
            dest_addr      : GEMM_op_x64.dest_addr,
            shape_ptr_addr : GEMM_op_x64.shape_ptr_addr,
            async          : GEMM_op_x64.async
        };
      end
    end
  end





endmodule
