// ===| DEPRECATED — use npu_arch.svh + kv260_device.svh instead |===============
// This file is kept as a compatibility shim so existing `include "GLOBAL_CONST.svh"
// statements continue to work during the migration period.
// Do NOT add new constants here. Add to npu_arch.svh or kv260_device.svh.
// ===============================================================================

`ifndef GLOBAL_CONST_SVH
`define GLOBAL_CONST_SVH

`include "NUMBERS.svh"
`include "kv260_device.svh"
`include "npu_arch.svh"

// ===| Legacy aliases (kept for backward compatibility) |=======================

// Boolean
`define TRUE  1'b1
`define FALSE 1'b0

// Matrix cache alignment options
`define ALIGN_VERTICAL    2'b01
`define ALIGN_HORIZONTAL  2'b11

// HP weight count helpers (now derived via mem_pkg, kept as macro for port use)
`define HP_PORT_MAX_WIDTH    `HP_TOTAL_WIDTH
`define HP_PORT_SINGLE_WIDTH `HP_SINGLE_WIDTH
`define HP_PORT_CNT          `DEVICE_HP_PORT_CNT

// DSP48E2 port sizes (legacy names)
`define DSP48E2_POUT_SIZE    `DSP_P_OUT_WIDTH
`define DSP48E2_A_WIDTH      `DEVICE_DSP_A_WIDTH
`define DSP48E2_B_WIDTH      `DEVICE_DSP_B_WIDTH
`define PREG_SIZE            `DSP_P_OUT_WIDTH
`define MREG_SIZE            `DSP_P_OUT_WIDTH

// MAC unit input sizes (kept for GEMM_systolic_top parameter defaults)
// H = INT4 weight packed into DSP B-port (18-bit / 4-bit = 4 weights per DSP column)
// V = fixed-point mantissa width (27-bit, fits in DSP A-port 30-bit)
`define GEMM_MAC_UNIT_IN_H   4
`define GEMM_MAC_UNIT_IN_V   `FIXED_MANT_WIDTH

// Legacy: FMAP cache size
`define FMAP_CACHE_OUT_SIZE  `FP32_WIDTH


// ISA width alias
`define ISA_WIDTH            `ISA_WIDTH

`endif // GLOBAL_CONST_SVH
