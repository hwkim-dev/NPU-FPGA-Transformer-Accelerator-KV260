// ===| DEPRECATED — use kv260_device.svh instead |==============================
// This file is kept as a compatibility shim only.
// Do NOT add new constants here.
// ===============================================================================

`ifndef DEVICE_INFO_SVH
`define DEVICE_INFO_SVH

`include "kv260_device.svh"

// Legacy aliases (no trailing semicolons — that was a bug)
`define DEVICE_HP_SINGLE_LANE_MAX_IN_BIT  `DEVICE_HP_SINGLE_WIDTH_BIT
`define DEVICE_HP_CNT                     `DEVICE_HP_PORT_CNT

`endif // DEVICE_INFO_SVH
