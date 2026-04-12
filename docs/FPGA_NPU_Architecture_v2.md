# uXC NPU Architecture — V2 (W4A8, 400MHz Target)

Target board: **Xilinx Kria KV260** | Bare-metal (no OS) | 400MHz core clock

Block diagram: `/.images/NPU_block_diagram.png`

---

## 1. System Overview

The uXC NPU is a custom neural processing unit designed to run the **Gemma 3N E4B** model
at full throughput on the KV260. The core compute paradigm is **W4A8**:
INT4 weights × INT8 activations, accumulating into INT48 via DSP48E2 P-registers.
Precision is promoted to BF16/FP32 only inside the CVO Core for non-linear functions.

### 1.1 Top-Level Data Flow

```
                         ┌─────────────────────────────────────────┐
                         │              NPU Frontend                │
AXI-Lite (HPM) ─────────►  AXIL_CMD_IN → Decoder → Global Scheduler│
                         └─────────┬───────────────────────────────┘
                                   │ uop dispatch
              ┌────────────────────┼──────────────────────┐
              ▼                    ▼                       ▼
         Vector Core          CVO Core              Matrix Core
       (4 × μV-Cores)    (2 × μCVO-Cores)        (Systolic Array)
              │                    │                       │
              └────────────────────┴───────────────────────┘
                                   │
                          L2 Cache [True Dual-Port URAM]
                                   │
                          Global Cache [URAM]
                          Constant Cache [BRAM]
```

---

## 2. Memory Hierarchy

| Level | Technology | Capacity | Access | Purpose |
|-------|-----------|----------|--------|---------|
| L1 Cache (per μV-Core) | BRAM | per-core | single-port | GEMV weight + activation |
| L1 FMAP Cache (Matrix Core) | BRAM | dedicated | single-port | Systolic Array fmap buffer |
| L2 Cache | URAM (True Dual-Port) | shared | dual-port (no arbiter) | Vector Core ↔ Matrix Core |
| Global Cache | URAM | large | shared | KV cache, long-context activations |
| Constant Cache | BRAM | small | read-only | RMSNorm scales, bias constants |

True Dual-Port L2 allows simultaneous read from Vector Core and write from Matrix Core
(or vice versa) without arbitration stalls.

---

## 3. AXI Port Assignment

| Port | Direction | Width | Usage |
|------|-----------|-------|-------|
| HP-0 | IN | 128-bit/clk | μV-Core weight stream (GEMV) |
| HP-1 | IN | 128-bit/clk | μV-Core weight stream (GEMV) |
| HP-2 | IN | 128-bit/clk | μV-Core weight stream (GEMV) |
| HP-3 | IN (single IN, double OUT) | 128-bit/clk | Matrix Core weight stream (GEMM) |
| ACP | Bi-directional | 128-bit | FMap in / Result out (coherent) |
| HPM | AXI-Lite | 64-bit | Control plane — ISA instruction issue |

---

## 4. Vector Core (4 × μV-Cores)

Handles all **GEMV** (vector × matrix) operations — the dominant operation in
the decode phase of autoregressive generation.

### Structure of each μV-Core

```
HP-x (128-bit) ──► FIFO WEIGHT ──► Dispatcher
                                         │
                                    L1 Cache (BRAM)
                                         │
                          ┌──────────────▼──────────────┐
                          │  DSP48E2 Array               │
                          │  (INT4 weight × INT8 fmap)   │
                          └──────────────┬───────────────┘
                                         │
                                    Accumulator
                                         │
                                    ──► DATA BUS Vec
```

- **Weight precision:** INT4 (streamed from HP-0/1/2, 32 weights/clk)
- **Activation precision:** INT8 (read from L1 or L2 cache)
- **Accumulation:** INT48 (DSP48E2 P-register)
- **Output:** promoted to BF16 before entering DATA BUS

---

## 5. Complex Vector Operation (CVO) Core (2 × μCVO-Cores)

Handles non-linear activation functions that require floating-point precision.
Receives promoted BF16/FP32 data from the Vector Core or Matrix Core via the DATA BUS.

### Units per μCVO-Core

| Unit | Functions | Latency |
|------|-----------|---------|
| SFU (Special Function Unit) | GeLU, RMSNorm, Softmax, tanh, exp, sqrt | 1–3 cycles |
| CORDIC | sin, cos (for RoPE) | pipeline |

### Precision Promotion Flow

```
[INT48 accumulator]
       │
  Normalizer (barrel shift + LOD → BF16)
       │
  SFU / CORDIC  ← operates in BF16 / FP32
       │
  Requantize → INT8
       │
  Back to L2 cache or next layer
```

---

## 6. Matrix Core (32×32 Systolic Array)

Handles **GEMM** (matrix × matrix) operations — used during the prefill phase
and for projection layers.

### Structure

```
HP-3 (128-bit, 32 INT4 weights/clk) ──► FIFO WEIGHT
                                               │
                                          Dispatcher ◄── Inst FIFO
                                               │
                       ┌───────────────────────┴──────────────────────────┐
                       │             Systolic Array                        │
                       │  ┌─────────────────┐  ┌─────────────────┐       │
                       │  │  32 × 16 Array  │  │  32 × 16 Array  │       │
                       │  │  (DSP48E2)      │  │  (DSP48E2)      │       │
                       │  └────────┬────────┘  └────────┬────────┘       │
                       │           └───────────┬─────────┘                │
                       │               Accumulator 32 × 1                 │
                       └───────────────────────┬──────────────────────────┘
                                               │
                                   L1 FMAP Cache ◄── ACP (fmap in)
```

- **Weight:** INT4, 128-bit/clk from HP-3 (32 weights per clock, feeds both sub-arrays)
- **FMap:** INT8, from L1 FMAP cache (pre-loaded via ACP)
- **Array size:** 32×32 implemented as two 32×16 sub-arrays
- **Accumulator:** INT48, 32 outputs (one per row)

### DSP48E2 Utilization

Each DSP48E2 handles `INT4 weight × INT8 fmap` via bit-packing.
Two INT4 weights are packed into a single B-port input (18-bit), allowing
two MACs per DSP per clock when using the cascade chain.

---

## 7. FMap Preprocessing Pipeline

Before entering the systolic array, BF16 feature maps from the ACP port are:

1. Cached in the L1 FMAP SRAM (`fmap_cache.sv`)
2. Converted from BF16 → 27-bit fixed-point mantissa (`preprocess_bf16_fixed_pipeline.sv`)
3. Exponent-max (`e_max`) extracted per column (`BF16_Emax_Align.sv`)
4. Broadcast to all 32 columns with staggered delay (0–31 cycles)

---

## 8. Output Pipeline

After computation, each PE row produces a 48-bit raw accumulator value.

```
[48-bit raw result × 32 rows]
          │
  stlc_result_normalizer.sv   ← sign-magnitude, LOD, barrel shift, e_max restore
          │
  [BF16 × 32 rows]
          │
  FROM_stlc_result_packer.sv  ← pack 8 × BF16 → 128-bit
          │
  [128-bit AXI stream → ACP → Host]
```

---

## 9. Control Plane

The NPU is controlled via a 64-bit custom ISA issued over AXI-Lite (HPM port).
See [ISA.md](ISA.md) for the full instruction encoding reference.

```
Host (AXI-Lite) ──► AXIL_CMD_IN ──► ctrl_npu_decoder
                                            │
                         ┌──────────┬───────┴──────┬──────────┐
                         ▼          ▼               ▼          ▼
                    GEMV FIFO  GEMM FIFO        MEM FIFO   MEMSET FIFO
                         │          │               │          │
                     μV-Cores   Systolic       mem_dispatcher  mem_set
                                 Array
```

The Global Scheduler (`Global_Scheduler.sv`) arbitrates between engine FIFOs
and dispatches uops. Engines run independently — a stall in one does not
block the others.

---

## 10. Implementation Status

| Block | RTL File(s) | Status |
|-------|-------------|--------|
| NPU Controller (frontend + decoder + scheduler) | `NPU_Controller/` | In Progress |
| GEMM Systolic Array (32×16 × 2) | `GEMM_PIPELINE/` | In Progress |
| GEMV Pipeline (μV-Cores) | `GEMV_PIPELINE/` | In Progress |
| FMap Preprocessing | `PREPROCESS/` | In Progress |
| Memory Hierarchy (L1/L2/Global/Constant) | `MEM_control/` | In Progress |
| CVO Core (SFU + CORDIC) | — | Not Started |
| Result Normalizer + Packer | `stlc_result_normalizer.sv`, `FROM_stlc_result_packer.sv` | In Progress |
| uXC Driver (HAL + API) | `sw/driver/` | Skeleton Only |
| Gemma 3N E4B Application | `sw/gemma3NE4B/` | Submodule |
