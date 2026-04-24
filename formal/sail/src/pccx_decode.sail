/* ──────────────────────────────────────────────────────────────────────── *
 * pccx — decode.sail
 * ──────────────────────────────────────────────────────────────────────── *
 * Pure decoder: 64-bit wire word -> typed `instr` union.
 *
 * Layout (from ../../hw/rtl/NPU_Controller/NPU_Control_Unit/ISA_PACKAGE/
 * isa_pkg.sv):
 *
 *   bits [63:60]  opcode (OP_GEMV=0x0 .. OP_CVO=0x4)
 *   bits [59: 0]  body   (opcode-specific layout, see pccx_types.sail)
 *
 * The decoder is the **single point** where the raw bitvector becomes
 * a typed instruction — any downstream pass (execute, trace writer,
 * coverage) works on the union, never the raw bits.
 * ──────────────────────────────────────────────────────────────────────── */

/* ── Helper: decode a `from_device_e` bit ── */

function decode_from_device(b : bit) -> from_device_e =
  if b == bitzero then FROM_NPU else FROM_HOST

function decode_to_device(b : bit) -> to_device_e =
  if b == bitzero then TO_NPU else TO_HOST

function decode_async(b : bit) -> async_e =
  if b == bitzero then SYNC_OP else ASYNC_OP

/* ── Helper: decode a `flags_t` from 6 bits (MSB-first, see ISA §4) ── */

function decode_flags(bits6 : bitvector(6)) -> flags_t = struct {
  findemax  = bits6[5],
  accm      = bits6[4],
  w_scale   = bits6[3],
  reserved3 = bits6[2 .. 0],
}

function decode_cvo_flags(bits5 : bitvector(5)) -> cvo_flags_t = struct {
  sub_emax    = bits5[4],
  recip_scale = bits5[3],
  accm        = bits5[2],
  reserved2   = bits5[1 .. 0],
}

/* ── Body decoders ── */

function decode_gemv(body : body_bits) -> gemv_body_t = struct {
  dest_reg       = body[59 .. 43],
  src_addr       = body[42 .. 26],
  flags          = decode_flags(body[25 .. 20]),
  size_ptr_addr  = body[19 .. 14],
  shape_ptr_addr = body[13 .. 8],
  parallel_lane  = body[7 .. 3],
  reserved3      = body[2 .. 0],
}

function decode_memcpy(body : body_bits) -> memcpy_body_t = struct {
  from_device    = decode_from_device(body[59]),
  to_device      = decode_to_device(body[58]),
  dest_addr      = body[57 .. 41],
  src_addr       = body[40 .. 24],
  aux_addr       = body[23 .. 7],
  shape_ptr_addr = body[6 .. 1],
  async          = decode_async(body[0]),
}

function decode_memset(body : body_bits) -> memset_body_t = struct {
  dest_cache = body[59 .. 58],
  dest_addr  = body[57 .. 52],
  a_value    = body[51 .. 36],
  b_value    = body[35 .. 20],
  c_value    = body[19 .. 4],
  reserved4  = body[3 .. 0],
}

function decode_cvo(body : body_bits) -> cvo_body_t = {
  let func : cvo_func_e = encdec_cvo_func(body[59 .. 56]);
  struct {
    cvo_func = func,
    src_addr = body[55 .. 39],
    dst_addr = body[38 .. 22],
    length   = body[21 .. 6],
    flags    = decode_cvo_flags(body[5 .. 1]),
    async    = decode_async(body[0]),
  }
}

/* ── Top-level: 64-bit word -> typed `instr` ── *
 *
 * The opcode mapping is total w.r.t. the 5 legal encodings; any other
 * value is an architectural error and raises a Sail exception so the
 * proof assistant can discharge "no unexpected behaviour" downstream.
 */
val decode : instruction_bits -> instr
function decode(word) = {
  let op : opcode_e = encdec_opcode(word[63 .. 60]);
  let body : body_bits = word[59 .. 0];
  match op {
    OP_GEMV   => Gemv  (decode_gemv(body)),
    OP_GEMM   => Gemm  (decode_gemv(body)),      /* identical layout */
    OP_MEMCPY => Memcpy(decode_memcpy(body)),
    OP_MEMSET => Memset(decode_memset(body)),
    OP_CVO    => Cvo   (decode_cvo(body)),
  }
}
