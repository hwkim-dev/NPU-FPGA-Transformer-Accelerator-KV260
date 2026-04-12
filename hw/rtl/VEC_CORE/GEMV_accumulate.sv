`timescale 1ns / 1ps

`include "GEMV_Vec_Matrix_MUL.svh"
`include "GLOBAL_CONST.svh"

// GEMV Operation
//
// [Shape]
// vector (1, N)
// dot Matrix (N, M)
// result (1, M)
//
// calc/per clk: Vec(1,32) dot Mat(32,32) = 32
// gemv_cycle: 512 clk
// Throughput/per clk: 1
// Throughput/per-GEMV: 512 (1p/clk * 512clk)
// GEMV-PIPE-CNT: 4
// 512 * 4 = 2048
// GEMV Throughput per [cycle]: (1, 2048)
//
// ===| Warning |===
// Before we send result to ACP
// results must type-casted FP32 to BF16(2Byte)
// and find e-Max and align by 32Groups



module GEMV_accumulate
  import vec_core_pkg::*;
#(
    parameter gemv_cfg_t param = VecCoreDefaultCfg
) (
    input logic clk,
    input logic rst_n,
    input logic [dtype_pkg::FixedMantWidth+2:0] IN_reduction_result,

    input logic init,
    input logic IN_valid,

    input logic [16:0] IN_num_recur,

    output logic [dtype_pkg::FixedMantWidth+2:0] OUT_GEMV_result_vector[0:param.gemv_batch - 1],
    output logic OUT_acc_valid
);

  logic [dtype_pkg::FixedMantWidth+2:0] GEMV_result_vector[0:param.gemv_batch - 1];

  // 2^9 == 512
  logic [8:0] res_vec_idx;
  logic [16:0] num_recur;
  logic [11:0] index_of_result;

  // Preventing flip-flop replication: Direct-wire the internal accumulation register to the output port
  assign OUT_GEMV_result_vector = GEMV_result_vector;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      OUT_acc_valid <= 0;
      res_vec_idx   <= 0;
      num_recur     <= 0;
      for (int vec_idx = 0; vec_idx < param.gemv_batch; vec_idx++) begin
        GEMV_result_vector[vec_idx] <= '0;
      end
    end else if (init) begin
      // new GEMV Acc start init pipeline
      res_vec_idx <= 0;
      num_recur   <= IN_num_recur;
    end else begin

      OUT_acc_valid <= 0;

      if (IN_valid && ~OUT_acc_valid) begin
        GEMV_result_vector[res_vec_idx] <= GEMV_result_vector[res_vec_idx] + IN_reduction_result;

        // Modulo-2^N counter": Intended Overflow 509-> 510-> 511-> 0-> 1
        res_vec_idx <= res_vec_idx + 1;
        num_recur <= num_recur - 1;
      end

      if (num_recur == 0 && ~OUT_acc_valid) begin
        OUT_acc_valid <= 1;
      end
    end
  end

endmodule
