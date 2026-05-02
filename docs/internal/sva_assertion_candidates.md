# SVA Assertion Candidate Map — pccx v002 RTL

_Stage C deliverable, autonomous RTL cleanup pass._

This document enumerates the SystemVerilog Assertion targets surveyed
during the Stage C pass. **No assertions are inserted by this pass**;
this map exists so the next batch can reach for a pre-vetted, ranked
list rather than re-discover them.

## 1. Why no assertions land in this pass

Three constraints, all softly converging on the same call:

1. The Stage C scope memo restricts this pass to package / counter /
   inventory work only.
2. The current `hw/sim/run_verification.sh` exercises 6 testbenches —
   `tb_GEMM_dsp_packer_sign_recovery`, `tb_mat_result_normalizer`,
   `tb_GEMM_weight_dispatcher`, `tb_FROM_mat_result_packer`,
   `tb_barrel_shifter_BF16`, `tb_ctrl_npu_decoder`. None of them
   compile the modules where the highest-value SVAs would land
   (`AXIL_STAT_OUT`, `mem_u_operation_queue`, `mem_dispatcher`,
   `Global_Scheduler`, `mem_CVO_stream_bridge`, `GEMM_systolic_top`).
   So an SVA added today only buys lint-time syntax coverage; it
   wakes up later when a TB starts driving the affected pin.
3. The codebase currently has zero SVA. There is no track record of
   the simulator's `disable iff` / `\`ifndef SYNTHESIS` tolerance for
   the project's xsim flow — adding the first assertion warrants its
   own focused commit with a TB that intentionally exercises the
   property, not a drive-by add.

Capture a behaviour-freeze sim baseline (already done — see
`/tmp/sim_baseline.log` snapshot in the Stage C summary doc) **and**
land at least one TB that drives one of the candidates below before
the SVA goes in. The first SVA + its driver TB should ship together.

## 2. Recommended assertion targets

Targets are ranked by (a) ease of reasoning, (b) recovery value when
the property fails, and (c) availability of an existing TB that could
be extended to drive the fault path. "Stage" = which downstream batch
is the right home.

### 2.1 Tier 1 — silent-drop / silent-discard surfaces

These modules silently swallow handshakes when their FIFO is full.
The contract documentation flags the surface; an SVA makes it
observable in simulation.

#### `AXIL_STAT_OUT` — push dropped on `fifo_full`

- **Where**: `hw/rtl/NPU_Controller/NPU_frontend/AXIL_STAT_OUT.sv`,
  inside the FIFO push block (`if (IN_valid && !fifo_full) ...`).
- **Property**: At every cycle outside reset/clear,
  `!(IN_valid && fifo_full)`.
- **Severity**: `$warning` — the upstream is permitted to over-issue
  in pathological scenarios, but most workloads should not.
- **Sketch**:
  ```systemverilog
  `ifndef SYNTHESIS
    property p_axil_stat_out_no_silent_drop;
      @(posedge clk) disable iff (!rst_n || IN_clear)
        !(IN_valid && fifo_full);
    endproperty
    a_axil_stat_out_no_silent_drop : assert property
        (p_axil_stat_out_no_silent_drop)
        else $warning("AXIL_STAT_OUT: status push dropped (fifo_full at IN_valid)");
  `endif
  ```
- **TB readiness**: No TB compiles this module yet. Add
  `tb_AXIL_STAT_OUT` first, then land the SVA in the same commit.

#### `mem_u_operation_queue` — push dropped on `fifo_full` (ACP / NPU)

- **Where**: `hw/rtl/MEM_control/IO/mem_u_operation_queue.sv`, both
  channels (push gated by `IN_*_rdy & ~*_fifo_full`).
- **Property**: `!(IN_acp_rdy && acp_fifo_full)` and the same for NPU.
- **Severity**: `$warning`.
- **TB readiness**: No TB. Same recipe — write a queue TB first.

### 2.2 Tier 2 — issue-rate one-hot guarantees

The decoder and scheduler are documented as issuing at most one op
class per cycle. SVA pins this contract so a future decoder rewrite
can not silently regress.

#### `ctrl_npu_decoder` — at most one `OUT_*_op_x64_valid` per cycle

- **Where**: `hw/rtl/NPU_Controller/NPU_Control_Unit/ctrl_npu_decoder.sv`.
- **Property**: `$onehot0({OUT_gemv_op_x64_valid, OUT_gemm_op_x64_valid,
  OUT_memcpy_op_x64_valid, OUT_memset_op_x64_valid, OUT_cvo_op_x64_valid})`.
- **Severity**: `$error` — a violation here means the dispatcher
  receives malformed traffic.
- **TB readiness**: `tb_ctrl_npu_decoder` already exists. The SVA can
  ride on top of the existing baseline; verify all 6 cycles still PASS.

#### `Global_Scheduler` — `OUT_sram_rd_start` is a one-cycle pulse

- **Where**: `hw/rtl/NPU_Controller/Global_Scheduler.sv`.
- **Property**:
  `OUT_sram_rd_start |=> !OUT_sram_rd_start` (concurrent assertion
  guarded against reset).
- **Severity**: `$error` — multi-cycle pulse breaks the one-shot
  contract assumed by downstream consumers.
- **TB readiness**: No TB. Defer until scheduler TB lands.

### 2.3 Tier 3 — handshake / FIFO invariants on streaming paths

These are the largest-value class once a TB drives them, but they
require interface-level cooperation (often a property bound onto
`axis_if`, not the consumer module).

#### `axis_if` payload-stable-while-stalled

- **Where**: `hw/rtl/NPU_Controller/npu_interfaces.svh` (or wherever
  `axis_if` is declared).
- **Property**: `valid && !ready |=> $stable(payload) && valid`.
- **Severity**: `$error` — every protocol-conformant master must
  obey this; a violation indicates a master bug.
- **TB readiness**: Should be added inside the interface so every
  consumer in every TB inherits it. Highest leverage of this list.

#### `mem_CVO_stream_bridge` — write counter never exceeds total

- **Where**: `hw/rtl/MEM_control/top/mem_CVO_stream_bridge.sv`.
- **Property**: `wr_word_cnt <= total_words` and result FIFO never
  overflows when `OUT_cvo_result_ready` is gated.
- **Severity**: `$error`.
- **TB readiness**: No TB.

#### `GEMM_systolic_top` — dual-lane weight valids rise together

- **Where**: `hw/rtl/MAT_CORE/GEMM_systolic_top.sv`.
- **Property**:
  `IN_weight_upper_valid <-> IN_weight_lower_valid` per cycle
  (W4A8 dual-MAC precondition — `GEMM_dsp_packer` requires the pair).
- **Severity**: `$error` — a desync produces wrong arithmetic.
- **TB readiness**: No TB at the top level (component-level
  TBs exist for `GEMM_dsp_packer` and `GEMM_weight_dispatcher`).

### 2.4 Tier 4 — reset-state assertions

Cheap to add, low information density per assertion, but a fast way
to detect partial-reset bugs after RTL surgery. Best added in batches
once the project is comfortable with the SVA workflow.

- Per boundary module: assert `OUT_*_valid == 0` and reset-time
  registers all zero one cycle after `rst_n` deasserts (or after
  `IN_clear` asserts).
- Recommended landing order: `npu_controller_top`, `mem_dispatcher`,
  `Global_Scheduler`, `GEMV_top`, `GEMM_systolic_top`, `CVO_top`.

## 3. Implementation pattern (when the time comes)

Use a uniform block at the **bottom** of each module so contributors
can find them at a glance:

```systemverilog
// ===| Assertions (sim-only) |================================================
`ifndef SYNTHESIS
  // Each assertion gets its own named property + named assertion. Keep
  // properties short; one invariant per assertion. Use $error for
  // contract violations, $warning for soft preconditions the workload
  // might transiently violate.
  property p_<name>;
    @(posedge clk) disable iff (!rst_n || IN_clear)
      <expression>;
  endproperty
  a_<name> : assert property (p_<name>)
      else $<sev>("<module>: <human description>");
`endif
```

The `\`ifndef SYNTHESIS` guard keeps Vivado synthesis output identical;
xsim picks the assertions up automatically.

## 4. Workflow for landing the first SVA

The next batch that lands SVA should follow this sequence so the
toolchain story is established cleanly:

1. Pick **one** Tier 1 candidate (recommendation: `AXIL_STAT_OUT`).
2. Write `tb_AXIL_STAT_OUT` driving the over-push case so the SVA
   provably fires in negative tests and stays silent in positive.
3. Add the SVA block to the module.
4. Re-run `bash hw/sim/run_verification.sh`; verify
   - existing 6 TBs still PASS
   - new tb_AXIL_STAT_OUT PASS for the legitimate path
   - new tb_AXIL_STAT_OUT WARNs (not FAILs) for the over-push path
5. Confirm `xvlog -f filelist.f` reports 0 ERROR / 0 WARNING.
6. Land both files (TB + SVA) in one commit so the trail is
   self-contained.

Repeat for subsequent tiers; do not bulk-land assertions across many
modules in a single commit.
