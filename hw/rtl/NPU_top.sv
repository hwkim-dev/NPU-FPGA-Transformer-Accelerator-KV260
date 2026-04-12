`include "GLOBAL_CONST.svh"
`timescale 1ns / 1ps
`include "GEMM_Array.svh"
`include "mem_IO.svh"
`include "npu_interfaces.svh"
`include "GLOBAL_CONST.svh"

/**
 * Module: NPU_top
 * Target: Kria KV260 @ 400MHz
 *
 * Architecture V2 (SystemVerilog Interface Version):
 * - HPC0/HPC1: Combined to form 256-bit Feature Map caching bus.
 * - HP0~HP3: Dedicated to high-throughput Weight streaming.
 * - HPM (MMIO): Centralized control & VLIW Instruction issuing.
 * - ACP: Coherent Result Output.
 */
module NPU_top (
    // Clock & Reset
    input logic clk_core,
    input logic rst_n_core,

    input logic clk_axi,
    input logic rst_axi_n,

    // Control Plane (MMIO)
    input  logic [31:0] mmio_npu_vliw,
    output logic [31:0] mmio_npu_stat,

    axil_if.slave S_AXIL_CTRL,

    // AXI4-Stream Interfaces (Clean & Modern)
    // |================================|
    // | Weight M dot M Input (256-bit) |
    // | Systolic 128bit                |
    // | (V dot M)'s support 128bit     |
    // |================================|
    axis_if.slave S_AXI_HP0_WEIGHT,
    axis_if.slave S_AXI_HP1_WEIGHT,

    // | Weight V dot M Input (256-bit) |
    axis_if.slave S_AXI_HP2_WEIGHT,
    axis_if.slave S_AXI_HP3_WEIGHT,


    // ACP      = featureMAP in, out (Full-Duplex), read & write at same time
    axis_if.slave  S_AXIS_ACP_FMAP,   // Feature Map Input 0 (128-bit, HPC0)
    axis_if.master M_AXIS_ACP_RESULT  // Final Result Output (128-bit)

);

  memory_op_t memcpy_cmd_wire;

  logic GEMV_op_x64_valid_wire;
  logic GEMM_op_x64_valid_wire;
  logic memcpy_op_x64_valid_wire;
  logic memset_op_x64_valid_wire;

  instruction_op_x64_t instruction;

  logic fifo_full_wire;


  npu_controller_top #() u_npu_controller_top (
      .clk(clk_core),
      .rst_n(rst_n_core),
      .i_clear(i_clear),

      .S_AXIL_CTRL(S_AXIL_CTRL),

      .OUT_GEMV_op_x64_valid  (GEMV_op_x64_valid_wire),
      .OUT_GEMM_op_x64_valid  (GEMM_op_x64_valid_wire),
      .OUT_memcpy_op_x64_valid(memcpy_op_x64_valid_wire),
      .OUT_memset_op_x64_valid(memset_op_x64_valid_wire),

      .OUT_memset_op_x64(instruction)
  );

  GEMM_control_uop_t   GEMM_uop_wire;
  GEMV_control_uop_t   GEMV_uop_wire;
  memory_control_uop_t LOAD_uop_wire;
  memory_set_uop_t     mem_set_uop;

  Global_Scheduler #() u_Global_Scheduler (
      .clk_core  (clk_core),
      .rst_n_core(rst_n_core),

      .IN_GEMV_op_x64_valid  (GEMV_op_x64_valid_wire),
      .IN_GEMM_op_x64_valid  (GEMM_op_x64_valid_wire),
      .IN_memcpy_op_x64_valid(memcpy_op_x64_valid_wire),
      .IN_memset_op_x64_valid(memset_op_x64_valid_wire),

      .instruction(instruction),

      .OUT_GEMM_uop(GEMM_uop_wire),
      .OUT_GEMV_uop(GEMV_uop_wire),
      .OUT_LOAD_uop(LOAD_uop_wire),
      .OUT_mem_set_uop(mem_set_uop)
  );

  mem_dispatcher #() u_mem_dispatcher (
      .clk_core  (clk_core),
      .rst_n_core(rst_n_core),

      .clk_axi  (clk_axi),
      .rst_axi_n(rst_axi_n),

      // ACP      = featureMAP in, out (Full-Duplex), read & write at same time
      .S_AXIS_ACP_FMAP  (S_AXIS_ACP_FMAP),   // Feature Map Input 0 (128-bit, HPC0)
      .M_AXIS_ACP_RESULT(M_AXIS_ACP_RESULT), // Final Result Output (128-bit)

      .IN_LOAD_uop(LOAD_uop_wire),
      .IN_mem_set_uop(mem_set_uop),

      .OUT_fifo_full(fifo_full_wire)
  );


  // ===| FMap Preprocessing Pipeline (The Common Path) |=======
  logic [`FIXED_MANT_WIDTH-1:0] fmap_broadcast       [0:`ARRAY_SIZE_H-1];
  logic                         fmap_broadcast_valid;
  logic [  `BF16_EXP_WIDTH-1:0] cached_emax_out      [0:`ARRAY_SIZE_H-1];

  preprocess_fmap u_fmap_pre (
      .clk(clk_core),
      .rst_n(rst_n_core),
      .i_clear(npu_clear),

      // HPC Streaming Inputs
      .S_AXIS_ACP_FMAP(S_AXIS_ACP_FMAP),
      //.S_AXIS_FMAP1(S_AXIS_HPC1),

      // Control
      .i_rd_start(global_sram_rd_start),

      // Preprocessed Outputs (to Branch Engines)
      .o_fmap_broadcast(fmap_broadcast),
      .o_fmap_valid(fmap_broadcast_valid),
      .o_cached_emax(cached_emax_out)
  );


  logic [127:0] weight_fifo_data[0:3];

  mem_HP_buffer u_HP_buffer (
      // ===| Clock & Reset |======================================
      .clk_core(clk_core),  // 400MHz
      .rst_n_core(rst_n_core),
      .clk_axi(clk_axi),  // 250MHz
      .rst_axi_n(rst_axi_n),

      // ===| HP Ports (Weight) - AXI Side |=======================
      .S_AXI_HP0_WEIGHT(S_AXI_HP0_WEIGHT),
      .S_AXI_HP1_WEIGHT(S_AXI_HP1_WEIGHT),
      .S_AXI_HP2_WEIGHT(S_AXI_HP2_WEIGHT),
      .S_AXI_HP3_WEIGHT(S_AXI_HP3_WEIGHT),

      // ===| Weight Stream - Core Side (To L1 or Dispatcher) |====
      .M_CORE_HP0_WEIGHT(M_CORE_HP0_WEIGHT),
      .M_CORE_HP1_WEIGHT(M_CORE_HP1_WEIGHT),
      .M_CORE_HP2_WEIGHT(M_CORE_HP2_WEIGHT),
      .M_CORE_HP3_WEIGHT(M_CORE_HP3_WEIGH)
  );


  import vec_core_pkg::*;

  GEMV_top #(
      .param(VecCoreDefaultCfg)
  ) u_GEMV_top (
      .clk(clk),
      .rst_n(rst_n),
      .IN_weight_valid_A(M_CORE_HP0_WEIGHT.tvalid),
      .IN_weight_valid_B(M_CORE_HP1_WEIGHT.tvalid),
      .IN_weight_valid_C(M_CORE_HP2_WEIGHT.tvalid),
      .IN_weight_valid_D(M_CORE_HP3_WEIGHT.tvalid),

      .IN_weight_A(M_CORE_HP0_WEIGHT.tdata),
      .IN_weight_B(M_CORE_HP1_WEIGHT.tdata),
      .IN_weight_C(M_CORE_HP2_WEIGHT.tdata),
      .IN_weight_D(M_CORE_HP3_WEIGHT.tdata),

      .OUT_weight_ready_A(M_CORE_HP0_WEIGHT.tready),
      .OUT_weight_ready_B(M_CORE_HP1_WEIGHT.tready),
      .OUT_weight_ready_C(M_CORE_HP2_WEIGHT.tready),
      .OUT_weight_ready_D(M_CORE_HP3_WEIGHT.tready),

      .IN_fmap_broadcast(IN_fmap_broadcast),
      .IN_fmap_broadcast_valid(IN_fmap_broadcast_valid),
      .IN_num_recur(IN_num_recur),
      .IN_cached_emax_out(IN_cached_emax_out),
      .activated_lane(activated_lane),

      //[param.fmap_type_mixed_precision - 1:0]
      .OUT_final_fmap_A(),
      .OUT_final_fmap_B(),
      .OUT_final_fmap_C(),
      .OUT_final_fmap_D(),

      .OUT_result_valid_A(),
      .OUT_result_valid_B(),
      .OUT_result_valid_C(),
      .OUT_result_valid_D()
  );

  // 3. Systolic Array Engine (Modularized)
  logic [`DSP48E2_POUT_SIZE-1:0] raw_res_sum      [0:`ARRAY_SIZE_H-1];
  logic                          raw_res_sum_valid[0:`ARRAY_SIZE_H-1];
  logic [   `BF16_EXP_WIDTH-1:0] delayed_emax_32  [0:`ARRAY_SIZE_H-1];

  GEMM_systolic_top u_systolic_engine (
      .clk(clk_core),
      .rst_n(rst_n_core),
      .i_clear(npu_clear),

      .global_weight_valid(global_weight_valid),
      .global_inst(global_inst),
      .global_inst_valid(global_inst_valid),

      .fmap_broadcast(fmap_broadcast),
      .fmap_broadcast_valid(fmap_broadcast_valid),

      .cached_emax_out(cached_emax_out),

      // Weight Input from FIFO (Direct)
      .weight_fifo_data (M_CORE_HP0_WEIGHT.tdata),
      .weight_fifo_valid(M_CORE_HP0_WEIGHT.tvalid),
      .weight_fifo_ready(M_CORE_HP0_WEIGHT.tready),

      .raw_res_sum(raw_res_sum),
      .raw_res_sum_valid(raw_res_sum_valid),
      .delayed_emax_32(delayed_emax_32)
  );

  // 4. Output Pipeline (Result Normalization -> Result Packer -> FIFO)
  // Normalizers
  logic [`BF16_WIDTH-1:0] norm_res_seq      [0:`ARRAY_SIZE_H-1];
  logic                   norm_res_seq_valid[0:`ARRAY_SIZE_H-1];


  genvar n;
  generate
    for (n = 0; n < `ARRAY_SIZE_H; n++) begin : gen_norm
      gemm_result_normalizer u_norm_seq (
          .clk(clk_core),
          .rst_n(rst_n_core),
          .data_in(raw_res_sum[n]),
          .e_max(delayed_emax_32[n]),
          .valid_in(raw_res_sum_valid[n]),
          .data_out(norm_res_seq[n]),
          .valid_out(norm_res_seq_valid[n])
      );
    end
  endgenerate

  // Packer
  logic [`AXI_DATA_WIDTH-1:0] packed_res_data;
  logic                       packed_res_valid;
  logic                       packed_res_ready;

  FROM_gemm_result_packer u_packer (
      .clk(clk_core),
      .rst_n(rst_n_core),
      .row_res(norm_res_seq),
      .row_res_valid(norm_res_seq_valid),
      .packed_data(packed_res_data),
      .packed_valid(packed_res_valid),
      .packed_ready(packed_res_ready),
      .o_busy(packer_busy_status)
  );


  // Status Assignment
  assign mmio_npu_stat[1] = 1'b0;
  assign mmio_npu_stat[31:2] = 30'd0;

endmodule
