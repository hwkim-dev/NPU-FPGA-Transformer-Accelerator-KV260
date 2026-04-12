package isa_memctrl;

  `define PORT_MOD_E_WRITE 1
  `define PORT_MOD_E_READ 0

  typedef enum logic [3:0] {
    data_to_host             = 4'h0,
    data_to_GLOBAL_cache         = 4'h1,
    data_to_L1_cache_gemm_in = 4'h2,
    data_to_L1_cache_GEMV_in = 4'h3,
  } data_dest_e;

  typedef enum logic [3:0] {
    data_from_host              = 4'h0,
    data_from_GLOBAL_cache          = 4'h1,
    data_from_L1_cache_gemm_res = 4'h2,
    data_from_L1_cache_GEMV_res = 4'h3
  } data_source_e;

  typedef enum logic [7:0] {
    from_host_to_L2 = {data_from_host, data_to_GLOBAL_cache},

    from_L2_to_host = {data_from_GLOBAL_cache, data_to_host},

    from_L2_to_L1_GEMM = {data_from_GLOBAL_cache, data_to_L1_cache_GEMM_in},
    from_L2_to_L1_GEMV = {data_from_GLOBAL_cache, data_to_L1_cache_GEMV_in},

    from_GEMV_res_to_L2 = {data_from_L1_cache_GEMV_res, data_to_GLOBAL_cache},
    from_GEMM_res_to_L2 = {data_from_L1_cache_GEMM_res, data_to_GLOBAL_cache}
  } data_route_e;


  typedef struct packed {
    data_route_e data_dest;

    dest_addr_t dest_addr;
    src_addr_t  src_addr;

    ptr_addr_t shape_ptr_addr;

    async_e async;
  } memory_control_uop_t;

  typedef enum logic [1:0] {
    data_to_fmap_shape   = 2'h0,
    data_to_weight_shape = 2'h1
  } dest_cache_e;

  typedef struct packed {
    dest_cache_e dest_cache;
    ptr_addr_t   dest_addr;
    a_value_t    a_value;
    b_value_t    b_value;
    c_value_t    c_value;
  } memory_set_uop_t;

  // mem dispatcher.sv
  typedef enum logic {
    NPU_U_OP_WIDTH = 33,
    ACP_U_OP_WIDTH = 33
  } npu_acp_u_op_width_e;

  typedef struct packed {
    logic        acp_write_en_wire;
    logic [16:0] acp_base_addr_wire;
    logic [16:0] acp_end_addr;
  } acp_uop_t;  //33 bit == [32:0]

  typedef struct packed {
    logic        npu_write_en_wire;
    logic [16:0] npu_base_addr_wire;
    logic [16:0] npu_end_addr;
  } npu_uop_t;  //33 bit == [32:0]

endpackage
