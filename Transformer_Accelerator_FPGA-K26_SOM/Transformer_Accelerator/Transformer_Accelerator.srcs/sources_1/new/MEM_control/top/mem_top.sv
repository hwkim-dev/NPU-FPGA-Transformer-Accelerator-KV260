








mem_dispatcher #(
) (
    input logic clk_core,    // 400MHz
    input logic rst_n_core,
    input logic clk_axi,     // 250MHz
    input logic rst_axi_n,

    // ===| External AXI-Stream (From PS & DDR4) |=================
    axis_if.slave  S_AXIS_ACP_FMAP,
    axis_if.master M_AXIS_ACP_RESULT, // TO ps.


    input memory_control_uop_t IN_LOAD_uop,
    input memory_set_uop_t     IN_mem_set_uop,

    output logic OUT_fifo_full
);


mem_HP_buffer #(
) (
    // ===| Clock & Reset |======================================
    input logic clk_core,  // 400MHz
    input logic rst_n_core,
    input logic clk_axi,  // 250MHz
    input logic rst_axi_n,

    // ===| HP Ports (Weight) - AXI Side |=======================
    axis_if.slave S_AXI_HP0_WEIGHT,
    axis_if.slave S_AXI_HP1_WEIGHT,
    axis_if.slave S_AXI_HP2_WEIGHT,
    axis_if.slave S_AXI_HP3_WEIGHT,

    // ===| Weight Stream - Core Side (To L1 or Dispatcher) |====
    axis_if.master M_CORE_HP0_WEIGHT,
    axis_if.master M_CORE_HP1_WEIGHT,
    axis_if.master M_CORE_HP2_WEIGHT,
    axis_if.master M_CORE_HP3_WEIGHT
);
