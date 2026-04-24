/* ──────────────────────────────────────────────────────────────────────── *
 * pccx — regs.sail
 * ──────────────────────────────────────────────────────────────────────── *
 * Execution state visible to the Sail ISA model.  Kept minimal for the
 * initial scaffold: the cycle counter + the ring-buffer of committed
 * instructions that the `.pccx` trace format records.
 *
 * Ground truth for the register-file layout lives in the dispatcher and
 * Global_Scheduler modules; those are still being re-homed, so the Sail
 * model only tracks the architecturally-observable state at this stage.
 * ──────────────────────────────────────────────────────────────────────── */

/* Execution cycle — drives the `.pccx` trace timestamp column. */
register cycle : bitvector(64)

/* Program counter — in pccx this is an index into the host-managed
 * instruction ring rather than a byte address, matching the
 * dispatcher's AXI-Lite command FIFO semantics. */
register pc : bitvector(16)

/* Non-zero after the model has committed at least one instruction.
 * Surfaces in tests as a simple liveness oracle. */
register committed_any : bit

/* ────────────────────────────────────────────────────────────────────── *
 * Per-unit commit counters (pccx_execute 2nd increment)
 * ────────────────────────────────────────────────────────────────────── *
 * These are **Sail-model observables**, not RTL-mirrored state.  They
 * exist so proofs / tests can assert liveness and ordering properties
 * on the three compute units the v002 architecture distinguishes:
 *   - MAC  : GEMV + GEMM paths through MAT_CORE / VEC_CORE
 *   - DMA  : MEMCPY + MEMSET paths through MEM_control
 *   - SFU  : CVO scalar pipeline (CVO_CORE)
 *
 * 32 bits gives headroom for any reasonable LLM-decode trace window
 * (Gemma-3N E4B at 20 tok/s over a full day ≪ 2^32 ops).  When we wire
 * the real `.pccx` writer in M4.9, these counters anchor the per-unit
 * utilisation series the pccx-lab Roofline view consumes.
 * ────────────────────────────────────────────────────────────────────── */

register mac_ops_committed : bitvector(32)
register dma_ops_committed : bitvector(32)
register sfu_ops_committed : bitvector(32)

/* Set while an async MEMCPY or CVO is outstanding.  The Sail model is
 * still single-instruction-step, so this is a liveness flag rather than
 * a concurrency tracker; the refinement proof against the dispatcher's
 * real AXI-Lite command FIFO comes later. */
register async_inflight : bit

/* ────────────────────────────────────────────────────────────────────── *
 * Last-committed operand observables (pccx_execute 3rd increment)
 * ────────────────────────────────────────────────────────────────────── *
 * The 2nd increment's `execute_*` helpers accepted each opcode body but
 * committed uniform effects — the operand fields were round-tripped
 * through `reencode_body` and otherwise discarded.  This increment
 * threads the decoded operands into **per-unit "last committed" slots**
 * so refinement proofs can assert a concrete RTL step wrote the same
 * dest/src addresses the Sail model decoded.
 *
 * The widths track `pccx_types.sail` exactly (isa_pkg.sv §3), so a RTL
 * field-width drift fails the Sail typecheck before it reaches xsim:
 *   - MAC (GEMV, GEMM)   : 17-bit dest_reg + 17-bit src_addr
 *   - DMA MEMCPY         : 17-bit dest_addr + 17-bit src_addr (MEMSET's
 *                          6-bit shape-cache pointer is deliberately
 *                          excluded — it indexes a shape table the
 *                          model does not yet abstract)
 *   - SFU CVO            : 17-bit dst_addr + 17-bit src_addr +
 *                          16-bit length (the only opcode with an
 *                          architecturally-observable element count)
 *
 * Reset values are all-zero at cold start, matching how xsim's `pccx`
 * trace dumper records a fresh pipeline before the first dispatch.
 * ────────────────────────────────────────────────────────────────────── */

register last_mac_dst    : dest_addr_t
register last_mac_src    : src_addr_t
register last_dma_dst    : dest_addr_t
register last_dma_src    : src_addr_t
register last_sfu_dst    : addr_t
register last_sfu_src    : src_addr_t
register last_sfu_length : length_t
