package GEMV_const_pkg;

  localparam int THROUGHPUT = 1;
  localparam int GEMV_BATCH = 512;
  localparam int GEMV_CYCLE = 512;
  localparam int GEMV_LINE_CNT = ;

  typedef struct packed {
    int num_gemv_pipeline;

    int throughput;
    int gemv_batch;
    int gemv_cycle;

    int fixed_mant_width;
    int weight_width;
    int weight_cnt;

    int fmap_cache_out_cnt;
  } gemv_cfg_t;

  localparam gemv_cfg_t GEMV_ACC_DEFAULT_CFG = '{
      num_gemv_pipeline: global_const_pkg::gemv_pipeline_cnt,

      throughput: THROUGHPUT,
      gemv_batch: GEMV_BATCH,
      gemv_cycle: GEMV_CYCLE,

      fixed_mant_width: float_emax_align_pkg::FIXED_MANT_WIDTH,
      weight_width: memory_control_pkg::WEIGHT_BIT_WIDTH,
      weight_cnt: memory_control_pkg::HP_PORT_SINGLE_IN_WEIGHT,

      fmap_cache_out_cnt: memory_control_pkg::FMAP_L2_CACHE_OUT_CNT,
      fmap_type_mixed_precision: global_const_pkg::FMAP_TYPE_MIXED_PRECISION
  };

endpackage : GEMV_const_pkg

/*
package npu_types_pkg;
  typedef struct packed {
    int width;
    int depth;
    int block_size;
    int stride_size;
    // ... 나머지 파라미터들
  } cfg_t;
endpackage


interface npu_if #(
    parameter npu_types_pkg::cfg_t CFG
) (
    input clk,
    rst_n
);
  // 20개의 신호를 여기에 정의
  logic [CFG.width-1:0] data_in;
  logic [CFG.width-1:0] data_out;
  logic                 valid;
  logic                 ready;
  // ... 나머지 16개 신호들

  // 방향 설정을 위한 modport (Master/Slave 구분)
  modport master(output data_in, valid, input data_out, ready);
  modport slave(input data_in, valid, output data_out, ready);
endinterface

interface npu_if #(parameter npu_types_pkg::cfg_t CFG) (input clk, rst_n);
    // 20개의 신호를 여기에 정의
    logic [CFG.width-1:0] data_in;
    logic [CFG.width-1:0] data_out;
    logic                 valid;
    logic                 ready;
    // ... 나머지 16개 신호들

    // 방향 설정을 위한 modport (Master/Slave 구분)
    modport master (output data_in, valid, input data_out, ready);
    modport slave  (input data_in, valid, output data_out, ready);
endinterface


*/
