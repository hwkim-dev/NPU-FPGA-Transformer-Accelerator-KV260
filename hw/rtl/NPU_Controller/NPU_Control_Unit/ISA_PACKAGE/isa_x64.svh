package isa_x64;
  //  Basic Types
  typedef logic [16:0] dest_addr_t;
  typedef logic [16:0] src_addr_t;
  typedef logic [16:0] addr_t;



  typedef logic [5:0] ptr_addr_t;  // For size and shape pointers
  typedef logic [4:0] parallel_lane_t;

  typedef logic [2:0] reserved_dot;

  typedef struct packed {
    logic [63:0] data;
    logic [7:0]  byte_en;
  } x64_payload_t;


  // npu -> host
  // host -> npu
  typedef enum logic {
    FROM_NPU  = 1'b0,
    FROM_HOST = 1'b1
  } from_device_e;

  typedef enum logic {
    TO_NPU  = 1'b0,
    TO_HOST = 1'b1
  } to_device_e;

  typedef enum logic {
    sync  = 1'b0,
    async = 1'b1
  } async_e;


  //  Flags (6-bit as per PDF spec)
  typedef struct packed {
    logic findemax;
    logic accm;     // Accumulate
    logic w_scale;
    logic [2:0] reserved;
  } flags_t;

  // Instruction format
  // instruction = x64(64bit) - head(opcode)
  typedef logic [59:0] VLIW_instruction_x64;

  //  Opcode table (4-bit)
  typedef enum logic [3:0] {
    OP_GEMV   = 4'h0,
    OP_GEMM   = 4'h1,
    OP_MEMCPY = 4'h2,
    OP_MEMSET = 4'h3
  } opcode_e;


  typedef struct packed {
    dest_addr_t     dest_reg;
    src_addr_t      src_addr;
    flags_t         flags;
    ptr_addr_t      size_ptr_addr;
    ptr_addr_t      shape_ptr_addr;
    parallel_lane_t parallel_lane;
    reserved_dot    reserved;
  } GEMV_op_x64_t;

  typedef struct packed {
    dest_addr_t     dest_reg;
    src_addr_t      src_addr;
    flags_t         flags;
    ptr_addr_t      size_ptr_addr;
    ptr_addr_t      shape_ptr_addr;
    parallel_lane_t parallel_lane;
    reserved_dot    reserved;
  } GEMM_op_x64_t;

  typedef struct packed {
    from_device_e from_device;
    to_device_e   to_device;
    dest_addr_t   dest_addr;
    src_addr_t    src_addr;
    addr_t        _addr;
    ptr_addr_t    shape_ptr_addr;
    async_e       async;
  } memcpy_op_x64_t;

  typedef struct packed {
    logic [1:0] dest_cache;
    ptr_addr_t  dest_addr;
    a_value_t   a_value;
    b_value_t   b_value;
    c_value_t   c_value;
    logic       reserved;
  } memset_op_x64_t;


  typedef struct packed {
    // head(opcode) removed
    logic [59:0] instruction;
  } instruction_op_x64_t;


  // --------------------------------------------------------
  // ===| Compute Micro-Op |=================================
  `define MEMORY_UOP_WIDTH 49

  typedef struct packed {
    flags_t    flags;
    ptr_addr_t size_ptr_addr;
    parallel_lane_t parallel_lane;
  } gemm_control_uop_t;


  typedef struct packed {
    flags_t    flags;
    ptr_addr_t size_ptr_addr;
    parallel_lane_t parallel_lane;
  } GEMV_control_uop_t;

  // ===| Compute Micro-Op |====================================
  // -----------------------------------------------------------

endpackage
