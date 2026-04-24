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
