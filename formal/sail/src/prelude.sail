/* ──────────────────────────────────────────────────────────────────────── *
 * pccx — prelude.sail
 * ──────────────────────────────────────────────────────────────────────── *
 * Minimal bitvector + arithmetic helpers.  Kept intentionally small; we
 * only pull what the ISA decode / execute paths need.
 *
 * Source of truth: the RTL at
 *   ../../hw/rtl/NPU_Controller/NPU_Control_Unit/ISA_PACKAGE/isa_pkg.sv
 * every type below mirrors a `typedef` in that package.  When a RTL
 * field width changes, update here in the same commit.
 * ──────────────────────────────────────────────────────────────────────── */

default Order dec

$include <prelude.sail>
$include <mapping.sail>
$include <vector.sail>
$include <arith.sail>
$include <hex_bits.sail>

/* A convenience alias for the canonical 64-bit pccx instruction word.
 * The word is laid out as { opcode[63:60], body[59:0] } — see
 * `pccx_types.sail` for the body decoding. */
type instruction_bits = bitvector(64)

/* 60-bit body (opcode stripped).  Mirrors SV `VLIW_instruction_x64`. */
type body_bits = bitvector(60)
