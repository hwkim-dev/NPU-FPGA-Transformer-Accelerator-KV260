/* ──────────────────────────────────────────────────────────────────────── *
 * pccx — smoke_decode.sail
 * ──────────────────────────────────────────────────────────────────────── *
 * Lightweight typecheck-only test.  We construct a handful of canonical
 * 64-bit words and assert that `decode` returns the expected variant of
 * `instr`.  The goal here is **not** behavioural coverage — that comes
 * with the execute pass — it is to lock the opcode/body wire format so
 * a breaking RTL change makes the Sail model fail first.
 * ──────────────────────────────────────────────────────────────────────── */

/* Build a 64-bit word from a 4-bit opcode + 60-bit body. */
val make_word : (bitvector(4), body_bits) -> instruction_bits
function make_word(op, body) = op @ body

function decode_matches_gemv_opcode() -> bool = {
  let word : instruction_bits = make_word(0x0, 0x000000000000000);
  match decode(word) {
    Gemv(_) => true,
    _       => false,
  }
}

function decode_matches_gemm_opcode() -> bool = {
  let word : instruction_bits = make_word(0x1, 0x000000000000000);
  match decode(word) {
    Gemm(_) => true,
    _       => false,
  }
}

function decode_matches_memcpy_opcode() -> bool = {
  let word : instruction_bits = make_word(0x2, 0x000000000000000);
  match decode(word) {
    Memcpy(_) => true,
    _         => false,
  }
}

function decode_matches_memset_opcode() -> bool = {
  let word : instruction_bits = make_word(0x3, 0x000000000000000);
  match decode(word) {
    Memset(_) => true,
    _         => false,
  }
}

function decode_matches_cvo_opcode() -> bool = {
  let word : instruction_bits = make_word(0x4, 0x000000000000000);
  match decode(word) {
    Cvo(_) => true,
    _      => false,
  }
}

/* ── Execute-path smoke (typecheck-only, 2nd increment) ────────────────
 *
 * These functions are not runtime asserts — they exist so the Sail
 * type-checker confirms the per-opcode execute helpers compose with
 * `decode` on every legal opcode.  A future interpreter-driven test
 * (once `record_event` has a real back end) can reuse the same words.
 * ────────────────────────────────────────────────────────────────── */

function step_accepts_gemv() -> unit =
  step(make_word(0x0, 0x000000000000000))

function step_accepts_gemm() -> unit =
  step(make_word(0x1, 0x000000000000000))

function step_accepts_memcpy() -> unit =
  step(make_word(0x2, 0x000000000000000))

function step_accepts_memset() -> unit =
  step(make_word(0x3, 0x000000000000000))

function step_accepts_cvo() -> unit =
  step(make_word(0x4, 0x000000000000000))

/* ── Last-operand observables smoke (typecheck-only, 3rd increment) ──
 *
 * The 3rd increment wires decoded operands into per-unit "last
 * committed" registers.  These helpers lock each observable's width
 * into the type checker: if someone widens `dest_addr_t` in
 * `pccx_types.sail` without updating `pccx_regs.sail`, these read-
 * backs stop composing with their declared return types.
 *
 * Values are not asserted — behavioural coverage of the exact decoded
 * operand arrives with the `.pccx` writer (M4.9).
 * ────────────────────────────────────────────────────────────────── */

function read_last_mac_dst() -> dest_addr_t = last_mac_dst
function read_last_mac_src() -> src_addr_t  = last_mac_src
function read_last_dma_dst() -> dest_addr_t = last_dma_dst
function read_last_dma_src() -> src_addr_t  = last_dma_src
function read_last_sfu_dst() -> addr_t      = last_sfu_dst
function read_last_sfu_src() -> src_addr_t  = last_sfu_src
function read_last_sfu_len() -> length_t    = last_sfu_length
