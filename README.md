# TinyNPU-Gemma: Bare-Metal Gemma 3N LLM Accelerator on FPGA

![WIP](https://img.shields.io/badge/Status-Work_in_Progress-red)
![Vulkan](https://img.shields.io/badge/Vulkan-Raw_API-red?logo=vulkan)
![C++](https://img.shields.io/badge/C++-17-blue?logo=c%2B%2B)
![Python](https://img.shields.io/badge/Python-3.x-yellow?logo=python)
![Hardware](https://img.shields.io/badge/Target-FPGA_KV260-orange)
![Quantization](https://img.shields.io/badge/Quantization-W4A8-green)

> **Notice: Active Development in Progress**
>
> This repository is currently under active development. The codebase, architecture, and core features are subject to change. The RTL synthesis targeting the Xilinx KV260 FPGA (including aggressive DSP48E2 resource mapping) is actively being refined and is not yet ready for production use.

## Project Overview

TinyNPU-Gemma is a custom SystemVerilog-based Neural Processing Unit (NPU) engineered from the ground up to accelerate the quantized Gemma 3N (E2B/E4B) Large Language Model on a bare-metal Xilinx Kria KV260 FPGA.

**Software Baseline (x64):**
This project is the hardware-accelerated adaptation of my baseline x64 software implementation, [llm-lite 🔗](https://github.com/hwkim-dev/llm-lite). While `llm-lite` executes the Gemma 3N E4B model on standard CPU environments, TinyNPU-Gemma re-architects the core inference pipeline to overcome inherent edge-device memory bottlenecks. The architecture is meticulously designed to push the absolute physical constraints of the KV260 platform, exploiting its 1,248 DSP48E2 slices and 144 Block RAMs (BRAMs) to the limit.

This project encompasses a full-stack hardware-software co-design approach. It seamlessly integrates a SystemVerilog hardware accelerator, a Python-based Golden Model for Trace-Driven Verification, CPU SIMD optimizations, and a high-performance AXI Direct Memory Access (AXI DMA) pipeline.


TinyNPU-Gemma is a custom SystemVerilog-based Neural Processing Unit (NPU) engineered from the ground up to accelerate the quantized Gemma 3N (E2B/E4B) Large Language Model on a bare-metal Xilinx Kria KV260 FPGA. The architecture is meticulously designed to push the absolute physical constraints of the KV260 platform, exploiting its 1,248 DSP48E2 slices and 144 Block RAMs (BRAMs) to the limit.

This project encompasses a full-stack hardware-software co-design approach. It seamlessly integrates a SystemVerilog hardware accelerator, a Python-based Golden Model for Trace-Driven Verification, CPU SIMD optimizations, and a high-performance AXI Direct Memory Access (AXI DMA) pipeline to overcome inherent edge-device memory bottlenecks.

---

## NPU Architecture Overview

![NPU Architecture](.images/NPU_block_diagram.png)

The NPU is organized into three primary compute tiers connected via a shared **L2 True Dual-Port cache** and internal data buses:

- **Vector Core:** Four μV-Cores for parallel GEMV operations, each with a dedicated L1 cache and BF16 Emax-align unit. Fed by AXI HP-Ports 0, 1, 2.
- **Complex Vector Operation (CVO) Core:** Two μCVO-Cores handling non-linear activation functions (tanh, sqrt, sin/cos via CORDIC and SFU). Connected to the Vector Core and Matrix Core via dedicated unidirectional data buses.
- **Matrix Core:** A 32×32 Systolic Array (implemented as two 32×16 sub-arrays) for GEMM operations. Weight is supplied via AXI HP-Port 3 at 128-bit/clk. FMap is cached in a dedicated L1 FMAP cache.

---

## Quantization Strategy: W4A8 with Dynamic Precision Promotion

The core compute path operates at **W4A8 precision**:

| Data                     | Type        | Width     | Notes                                   |
| ------------------------ | ----------- | --------- | --------------------------------------- |
| Weight                   | INT4        | 4-bit     | Stored and streamed as-is from HP ports |
| Feature Map (Activation) | INT8        | 8-bit     | Stored in L1/L2 cache                   |
| MAC Accumulation         | INT32/INT48 | 32–48-bit | DSP48E2 P-register output               |
| SFU Input/Output         | BF16 / FP32 | 16–32-bit | After type promotion                    |

### Precision Promotion Flow

```
[Weight: INT4] × [FMap: INT8]
        ↓  DSP48E2 MAC
  [Accumulator: INT48]
        ↓  Normalization (Barrel Shift + LOD)
     [BF16 / FP32]
        ↓  SFU / CORDIC  (tanh, RMSNorm, Softmax, GeLU, sin/cos)
     [BF16 / FP32]
        ↓  Requantize
     [INT8] → next layer
```

Precision promotion to **BF16 or FP32** occurs only when entering the Complex Vector Operation (CVO) Core for non-linear functions. After the SFU computation, results are requantized back to INT8 before re-entering the Vector Core or L2 cache. This minimizes the footprint of high-precision arithmetic while preserving numerical accuracy where it matters.

---

## System Architecture and Key Components

### 1. Custom ISA and Decoupled Dataflow Pipeline

[![ISA Instruction Set Architecture](.images/ISA_screen_shot_0409.png)](https://docs.google.com/spreadsheets/d/e/2PACX-1vQOZ4tMXcdIpcdOCvneAx0r8wmRfmprogqkhbCTK2ythlzxp2GBromIiCi9J9yEz9G_ZO4o7BreDOoq/pubhtml?gid=584280668&single=true)

> **[Click Here to Explore the Full Custom ISA Specification (Google Sheets)]**(https://docs.google.com/spreadsheets/d/e/2PACX-1vQOZ4tMXcdIpcdOCvneAx0r8wmRfmprogqkhbCTK2ythlzxp2GBromIiCi9J9yEz9G_ZO4o7BreDOoq/pubhtml?gid=584280668&single=true)

The accelerator operates on a **Custom 64-bit ISA** specifically tailored for LLM acceleration. To maximize parallel execution and eliminate pipeline stalls, the architecture employs a strictly **Decoupled Dataflow** system, divided into two asynchronous stages:

- **Stage 1 — Global Front-End:** The central `ctrl_npu_decoder` fetches and decodes 64-bit custom instructions and dispatches them into dedicated Instruction FIFOs at the front of each execution pipeline. The front-end advances immediately without waiting for execution to complete.
- **Stage 2 — Local Dispatcher:** Each compute engine pops from its instruction FIFO and checks local execution conditions (weight availability, FMap readiness). Once dependencies are satisfied, it fires the engine independently — a stall in one engine never halts another.

### 2. Memory Hierarchy

| Level                       | Technology            | Purpose                                       |
| --------------------------- | --------------------- | --------------------------------------------- |
| L1 Cache (per μV-Core)      | BRAM                  | Ultra-low latency weight/activation access    |
| L1 Cache FMAP (Matrix Core) | BRAM                  | Dedicated FMap buffer for Systolic Array      |
| L2 Cache                    | URAM (True Dual-Port) | Shared between Vector Core ↔ Matrix Core      |
| Global Cache                | URAM                  | Long-context KV cache, full model activations |
| Constant Cache              | BRAM                  | RMSNorm scales, bias constants                |

True Dual-Port L2 enables simultaneous read/write from Vector Core and Matrix Core without arbitration stalls.

### 3. DSP48E2 Architecture Utilization

The Systolic Array maps **INT4 weight × INT8 FMap** MAC operations directly onto DSP48E2 blocks using bit-packing to maximize compute density within the KV260's 1,248 DSP budget.

![DSP48E2 Architecture](.images/DSP48E2_IMG.jpeg)

Weight is delivered to the Systolic Array at **128-bit/clk via AXI HP-Port 3**, equivalent to 32 INT4 weights per clock (INT4 × 16 × 2), feeding both 32×16 sub-arrays simultaneously.

### 4. Complex Vector Operation (CVO) Core

The CVO Core performs **floating-point non-linear operations** after precision promotion from INT8/INT48 accumulator output:

| Unit   | Function  | Latency  |
| ------ | --------- | -------- |
| SFU    | GeLU      | 1 cycle  |
| SFU    | RMSNorm   | 1 cycle  |
| SFU    | Softmax   | 3 cycles |
| SFU    | tanh      | 1 cycle  |
| CORDIC | sin / cos | pipeline |

Two μCVO-Cores operate in parallel, each with a register file and shared Dispatcher/Inst FIFO.

### 5. AXI DMA and Memory Interface

| Port             | Direction                  | Bandwidth        | Usage                     |
| ---------------- | -------------------------- | ---------------- | ------------------------- |
| HP-0, HP-1, HP-2 | IN (uni-directional)       | 128-bit/clk each | Vector Core weight stream |
| HP-3             | IN (single IN, double OUT) | 128-bit/clk      | Matrix Core weight stream |
| ACP Port         | Bi-directional             | 128-bit          | FMap in / Result out      |

### 6. CPU SIMD Optimizations & Trace-Driven Verification

Hardware verification requires a **bit-true match (0% error rate)** between the Python/PyTorch golden model and the SystemVerilog RTL simulation across all precision levels (INT4, INT8, BF16, FP32).

### 7. Gemma 3N Architecture Specifics

| Feature                 | Implementation                                                        |
| ----------------------- | --------------------------------------------------------------------- |
| AltUp Router            | Tanh scaling: `Tanh(Norm(x)/2048) × W`, main stream `xs[0]` untouched |
| RMSNorm                 | `scale_plus_one=False`, strictly per Gemma spec                       |
| Top-K Extraction        | `numpy.argpartition` — O(N) vs O(N log N)                             |
| Gaussian Top-K Sparsity | FFN layers 0–9: 0.95 sparsity via hardware ReLU                       |
| KV Cache Reuse          | Layers 20–34 reuse Layer 18 (Local) and Layer 19 (Global) caches      |

---

## Current Status

| Component                            | Status        |
| ------------------------------------ | ------------- |
| Custom ISA definition                | ✅ Complete    |
| Python golden model                  | ✅ Verified    |
| Vulkan memory profiling              | ✅ Verified    |
| Systolic Array RTL                   | 🔧 In Progress |
| CVO Core RTL                         | 🔧 In Progress |
| Full system integration              | 🔧 In Progress |
| DSP48E2 timing closure @ target freq | 🔧 In Progress |

---

## Repository Structure (planned)

```
├── rtl/          # SystemVerilog source
├── tb/           # Testbenches
├── golden/       # Python golden model
├── isa/          # ISA specification
└── docs/         # Architecture diagrams
```