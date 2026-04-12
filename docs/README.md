# uXC Documentation Index

This directory contains all design documents for the uXC (micro eXcelerator Core) NPU project.
Documents are organized into three categories: Hardware Architecture, ISA/Driver, and Model Analysis.

---

## 1. Hardware Architecture

| File | Description |
|------|-------------|
| [FPGA_NPU_Architecture_v2.md](FPGA_NPU_Architecture_v2.md) | Top-level NPU architecture — block diagram, memory hierarchy, compute core overview (W4A8) |
| [HW_Optimization_DSP48E2.md](HW_Optimization_DSP48E2.md) | DSP48E2-level optimization notes: constant folding, bit-shift tricks, RMSNorm scale cancellation |

---

## 2. ISA & Driver

| File | Description |
|------|-------------|
| [ISA.md](ISA.md) | 64-bit custom ISA specification: opcode table, instruction encoding, memory routing |

---

## 3. Gemma 3N E4B Model Analysis

These documents describe the mathematical behavior and hardware constraints of the Gemma 3N E4B model
that runs on the uXC NPU. Read these before implementing any compute pipeline.

| File | Description |
|------|-------------|
| [GEMMA_3N_E4B.md](GEMMA_3N_E4B.md) | Comprehensive Gemma 3N E4B model analysis: weights, layers, quantization, KV cache |
| [Gemma3N_Pipeline_EN.md](Gemma3N_Pipeline_EN.md) | Full pipeline mathematical specification (English) — token to logit, all 35 layers |
| [Gemma3N_Pipeline_KR.md](Gemma3N_Pipeline_KR.md) | Pipeline overview with hardware integration notes (Korean) |
| [Attention_RoPE.md](Attention_RoPE.md) | Gemma 3N attention constraints: no scaling, no softcap, alternating RoPE theta |
| [FFN_Sparsity.md](FFN_Sparsity.md) | Gaussian Top-K sparsity (0.95) in FFN layers 0–9 |
| [PLE_LAuReL.md](PLE_LAuReL.md) | LAuReL parallel calibration and PLE shadow-stream injection rules |

---

## Reading Order

**For hardware engineers starting on RTL:**
1. `FPGA_NPU_Architecture_v2.md` — understand the full system
2. `ISA.md` — understand the instruction set before touching the controller
3. `HW_Optimization_DSP48E2.md` — DSP48E2 tricks for the compute pipelines

**For understanding the target workload (Gemma 3N E4B):**
1. `Gemma3N_Pipeline_EN.md` — the ground truth mathematical spec
2. `Attention_RoPE.md`, `FFN_Sparsity.md`, `PLE_LAuReL.md` — critical constraint details
3. `GEMMA_3N_E4B.md` — deep-dive into model internals

---

## Project Structure Reference

```
hw/rtl/          SystemVerilog RTL (synthesizable only)
sw/driver/       uXC driver — AXI-Lite MMIO HAL + high-level API (CUDA equivalent)
sw/gemma3NE4B/   Gemma 3N E4B inference application (uses uXC driver API)
docs/            This directory
.images/         Block diagrams and architecture screenshots
```
