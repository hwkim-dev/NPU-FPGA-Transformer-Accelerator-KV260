/* ──────────────────────────────────────────────────────────────────────── *
 * pccx — types.sail
 * ──────────────────────────────────────────────────────────────────────── *
 * Every Sail `type` / `enum` / `struct` below 1:1 mirrors a SystemVerilog
 * `typedef` in
 *   ../../hw/rtl/NPU_Controller/NPU_Control_Unit/ISA_PACKAGE/isa_pkg.sv
 *
 * Widths are fixed because the RTL encoder shares the exact same
 * bitfield layout on the wire.  The Sail model is the **formal
 * specification** the RTL must refine against.
 * ──────────────────────────────────────────────────────────────────────── */

/* ── Primitive address / pointer widths (isa_pkg.sv §Basic Types) ── */

type dest_addr_t     = bitvector(17)
type src_addr_t      = bitvector(17)
type addr_t          = bitvector(17)
type ptr_addr_t      = bitvector(6)      /* shape/size pointer (6-bit index) */
type parallel_lane_t = bitvector(5)

type a_value_t = bitvector(16)
type b_value_t = bitvector(16)
type c_value_t = bitvector(16)
type length_t  = bitvector(16)

/* ── Device-direction / sync flags ── */

enum from_device_e = { FROM_NPU, FROM_HOST }
enum to_device_e   = { TO_NPU,   TO_HOST   }
enum async_e       = { SYNC_OP,  ASYNC_OP  }

/* ── GEMV / GEMM flags (6-bit, ISA §4) ── */

struct flags_t = {
  findemax   : bit,   /* [5] find e_max for output normalisation */
  accm       : bit,   /* [4] accumulate into dst (do not overwrite) */
  w_scale    : bit,   /* [3] apply weight scale factor during MAC */
  reserved3  : bitvector(3),
}

/* ── Opcode table (4-bit, ISA §2) ── */

enum opcode_e = {
  OP_GEMV,    /* 0x0 */
  OP_GEMM,    /* 0x1 */
  OP_MEMCPY,  /* 0x2 */
  OP_MEMSET,  /* 0x3 */
  OP_CVO,     /* 0x4 */
}

/* Forward / reverse mapping between the 4-bit wire encoding and the
 * typed opcode.  `mapping` gives us both directions in a single decl. */
mapping encdec_opcode : opcode_e <-> bitvector(4) = {
  OP_GEMV   <-> 0x0,
  OP_GEMM   <-> 0x1,
  OP_MEMCPY <-> 0x2,
  OP_MEMSET <-> 0x3,
  OP_CVO    <-> 0x4,
}

/* ── GEMV / GEMM body (60-bit, ISA §3.1) ── */

struct gemv_body_t = {
  dest_reg        : dest_addr_t,      /* [59:43] */
  src_addr        : src_addr_t,       /* [42:26] */
  flags           : flags_t,          /* [25:20] */
  size_ptr_addr   : ptr_addr_t,       /* [19:14] */
  shape_ptr_addr  : ptr_addr_t,       /* [13: 8] */
  parallel_lane   : parallel_lane_t,  /* [ 7: 3] */
  reserved3       : bitvector(3),     /* [ 2: 0] */
}

/* GEMM uses the identical body layout — SV uses `typedef A B;` we
 * just alias. */
type gemm_body_t = gemv_body_t

/* ── MEMCPY body (60-bit, ISA §3.2) ── */

struct memcpy_body_t = {
  from_device    : from_device_e,  /* [59]     */
  to_device      : to_device_e,    /* [58]     */
  dest_addr      : dest_addr_t,    /* [57:41]  */
  src_addr       : src_addr_t,     /* [40:24]  */
  aux_addr       : addr_t,         /* [23: 7]  */
  shape_ptr_addr : ptr_addr_t,     /* [ 6: 1]  */
  async          : async_e,        /* [ 0]     */
}

/* ── MEMSET body (60-bit, ISA §3.3) ── */

struct memset_body_t = {
  dest_cache : bitvector(2),   /* [59:58] */
  dest_addr  : ptr_addr_t,     /* [57:52] */
  a_value    : a_value_t,      /* [51:36] */
  b_value    : b_value_t,      /* [35:20] */
  c_value    : c_value_t,      /* [19: 4] */
  reserved4  : bitvector(4),   /* [ 3: 0] */
}

/* ── CVO body (60-bit, ISA §3.4) ── */

enum cvo_func_e = {
  CVO_EXP,         /* 0x0 */
  CVO_SQRT,        /* 0x1 */
  CVO_GELU,        /* 0x2 */
  CVO_SIN,         /* 0x3 */
  CVO_COS,         /* 0x4 */
  CVO_REDUCE_SUM,  /* 0x5 */
  CVO_SCALE,       /* 0x6 */
  CVO_RECIP,       /* 0x7 */
}

mapping encdec_cvo_func : cvo_func_e <-> bitvector(4) = {
  CVO_EXP        <-> 0x0,
  CVO_SQRT       <-> 0x1,
  CVO_GELU       <-> 0x2,
  CVO_SIN        <-> 0x3,
  CVO_COS        <-> 0x4,
  CVO_REDUCE_SUM <-> 0x5,
  CVO_SCALE      <-> 0x6,
  CVO_RECIP      <-> 0x7,
}

struct cvo_flags_t = {
  sub_emax    : bit,            /* [4] subtract e_max before op */
  recip_scale : bit,            /* [3] divide instead of multiply */
  accm        : bit,            /* [2] accumulate into dst */
  reserved2   : bitvector(2),
}

struct cvo_body_t = {
  cvo_func  : cvo_func_e,  /* [59:56] */
  src_addr  : src_addr_t,  /* [55:39] */
  dst_addr  : addr_t,      /* [38:22] */
  length    : length_t,    /* [21: 6] */
  flags     : cvo_flags_t, /* [ 5: 1] */
  async     : async_e,     /* [ 0]    */
}

/* ── Top-level typed instruction ── */

union instr = {
  Gemv   : gemv_body_t,
  Gemm   : gemm_body_t,
  Memcpy : memcpy_body_t,
  Memset : memset_body_t,
  Cvo    : cvo_body_t,
}
