/* ──────────────────────────────────────────────────────────────────────── *
 * pccx — execute.sail
 * ──────────────────────────────────────────────────────────────────────── *
 * Executable semantics — first increment.
 *
 * At this stage the model is **non-interpreting**: every opcode advances
 * the architectural cycle counter and sets `committed_any`.  Concrete
 * compute effects (MAC accumulation, DMA, SFU math) land in the next
 * iteration.
 *
 * The `.pccx` trace contract is:
 *   record_event(cycle, opcode_tag, body_bits)
 * where `opcode_tag` is the 4-bit wire encoding and `body_bits` is the
 * untouched 60-bit body.  A follow-up commit wires this function to the
 * pccx-lab flat-buffer layout described in
 *   https://hwkim-dev.github.io/pccx/en/docs/Lab/architecture.html
 * ──────────────────────────────────────────────────────────────────────── */

/* Low-level "effect hook" — a no-op today, will be attached to the
 * `.pccx` writer once the C back-end lands.  Keeping it as a Sail
 * function (not an external) means Isabelle / Coq extractions see a
 * pure total stub. */
function record_event(c : bitvector(64), op : bitvector(4), body : body_bits) -> unit = {
  let _ = c;
  let _ = op;
  let _ = body;
}

/* Advance the cycle counter by `n`.  Using 64-bit arithmetic so
 * multi-year traces do not overflow. */
function advance_cycle(n : bitvector(64)) -> unit = {
  cycle = cycle + n
}

/* Opcode-specific latency estimates (cycles).  These are deliberately
 * coarse so the execute pass is *latency-typed* rather than
 * latency-accurate; the refined model plugs in proper per-opcode
 * latency tables in the next iteration. */
function estimated_latency(i : instr) -> bitvector(64) = {
  match i {
    Gemv(_)   => 0x0000_0000_0000_0080,  /* ≈ 128 cy — GEMV tile      */
    Gemm(_)   => 0x0000_0000_0000_0100,  /*   256 cy — GEMM tile      */
    Memcpy(_) => 0x0000_0000_0000_0040,  /*    64 cy — DMA burst      */
    Memset(_) => 0x0000_0000_0000_0020,  /*    32 cy — cache preset   */
    Cvo(_)    => 0x0000_0000_0000_0060,  /*    96 cy — CVO scalar     */
  }
}

/* Extract the opcode wire tag from a typed `instr`.  Round-tripping
 * through `encdec_opcode` keeps this in lock-step with the decoder. */
function opcode_tag(i : instr) -> bitvector(4) = {
  match i {
    Gemv(_)   => encdec_opcode(OP_GEMV),
    Gemm(_)   => encdec_opcode(OP_GEMM),
    Memcpy(_) => encdec_opcode(OP_MEMCPY),
    Memset(_) => encdec_opcode(OP_MEMSET),
    Cvo(_)    => encdec_opcode(OP_CVO),
  }
}

/* Re-encode the body of a typed instruction into its 60-bit wire
 * form.  Used both by the trace writer (above) and by future proof
 * obligations that state `encode ∘ decode = id`. */
function reencode_body(i : instr) -> body_bits = {
  match i {
    /* For the scaffold we only reproduce the opcode and the high-order
     * address fields — the remaining low-order bits are zeroed until
     * the execute pass refines them.  A future iteration will wire
     * struct fields back into their exact bit slots.  The typechecker
     * still gets a 60-bit value; widths add up explicitly:
     *
     *   GEMV/GEMM : 17 (dest) + 17 (src) + 26 (tail)                  = 60
     *   MEMCPY    :  1 + 1 + 17 (dest) + 17 (src) + 24 (tail)         = 60
     *   MEMSET    :  2 + 6 + 16 + 16 + 16 + 4 (tail)                  = 60
     *   CVO       :  4 (func) + 17 (src) + 17 (dst) + 16 (len) + 6    = 60
     */
    Gemv(b)   => b.dest_reg  @ b.src_addr  @ sail_zeros(26),
    Gemm(b)   => b.dest_reg  @ b.src_addr  @ sail_zeros(26),
    Memcpy(b) => sail_zeros(1)   /* from_device (placeholder) */
               @ sail_zeros(1)   /* to_device   (placeholder) */
               @ b.dest_addr
               @ b.src_addr
               @ sail_zeros(24),
    Memset(b) => b.dest_cache @ b.dest_addr @ b.a_value @ b.b_value @ b.c_value @ sail_zeros(4),
    Cvo(b)    => encdec_cvo_func(b.cvo_func) @ b.src_addr @ b.dst_addr @ b.length @ sail_zeros(6),
  }
}

/* Top-level one-step execute: decode → record → advance cycle → mark
 * committed.  Intended to be the outermost driver the future
 * instruction-fetch loop calls once per instruction word. */
val step : instruction_bits -> unit
function step(word) = {
  let i = decode(word);
  let tag = opcode_tag(i);
  let body = reencode_body(i);
  record_event(cycle, tag, body);
  advance_cycle(estimated_latency(i));
  committed_any = bitone;
}
