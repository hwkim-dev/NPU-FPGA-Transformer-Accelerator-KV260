`include "DEVICE_INFO.svh"
`include "GLOBAL_CONST.svh"

package memory_control_pkg;

  localparam int FMAP_L2_CACHE_OUT_CNT = 32;

  localparam int HP_PORT_SINGLE_IN_BIT = `DEVICE_HP_SINGLE_LANE_MAX_IN_BIT;
  localparam int HP_PORT_CNT = `DEVICE_HP_CNT;

  localparam int HP_PORT_MAX_IN_BIT = HP_PORT_SINGLE_IN_BIT * HP_PORT_CNT;

  localparam int WEIGHT_BIT_WIDTH = global_const_pkg::WEIGHT_TYPE;

  localparam int HP_PORT_SINGLE_IN_WEIGHT = HP_PORT_SINGLE_IN_BIT / WEIGHT_BIT_WIDTH;
  localparam int HP_PORT_TOTAL_IN_WEIGHT = HP_PORT_MAX_IN_BIT / WEIGHT_BIT_WIDTH;

endpackage : memory_control_pkg
