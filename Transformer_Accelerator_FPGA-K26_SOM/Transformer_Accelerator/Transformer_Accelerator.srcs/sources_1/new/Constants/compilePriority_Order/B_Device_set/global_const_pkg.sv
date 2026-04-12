`include "NUMBERS.svh"

package global_const_pkg;

  localparam int FMAP_TYPE = `N_BF16_SIZE;
  localparam int FMAP_TYPE_MIXED_PRECISION = `N_FP32_SIZE;

  localparam int WEIGHT_TYPE = `N_SIZEOF_INT4;
  localparam int gemv_pipeline_cnt = 4;
  localparam int gemm_pipeline_cnt = 1;

endpackage : global_const_pkg
