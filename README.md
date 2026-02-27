# TinyNPU-RTL: On-Device LLM Accelerator for Gemma 3N

## 1. Project Overview
This project focuses on the RTL-level design and implementation of a custom Neural Processing Unit (NPU) tailored for Edge Devices. The ultimate goal is to accelerate Google's latest on-device LLM, **Gemma 3N (E4B / E2B)**, on the Xilinx **Kria KV260** FPGA board. 

Unlike traditional CNNs, Auto-regressive LLMs suffer from severe **Memory Bound** issues during the token decoding phase. To overcome this extreme memory bandwidth bottleneck, the design aggressively adopts a **2D Systolic Array** architecture, **AXI DMA**, and optimized **KV Cache** management for efficient hardware-software co-design.

## 2. Developer Background
- **Core Strengths**: Mastering software parallel processing based on **C/C++, CUDA, OpenCL**, and **DirectX 11** pipelines.
- **Hardware Mapping Philosophy**: Rapidly bridging software parallel concepts into hardware (RTL). For instance, translating GPU **Shared Memory** usage into FPGA **BRAM** design, and transforming **Compute Shader** thread parallelism into hardware **Systolic Arrays** to maximize **Data Reuse**.

## 3. System Architecture
The system utilizes a Hardware/Software Co-design approach, partitioning tasks between the ARM CPU (PS) and the FPGA (PL).

### A. 2D Systolic Array (Compute Core)
* **GEMM & GEMV Acceleration**: The core execution unit designed to accelerate massive matrix multiplications (**GEMM** for Prefill phase, **GEMV** for Decode phase).
* **Wavefront Data Flow**: Maximizes internal data reuse by flowing data continuously through the Processing Elements (PEs) like a wavefront, drastically reducing external memory access.

### B. Memory Hierarchy & Bandwidth Optimization
* **Global Memory (DDR4)**: Stores the quantized Gemma 3N weights and the dynamically growing **KV Cache**.
* **AXI DMA**: A high-speed Direct Memory Access controller that streams weights and tokens from DDR4 to the NPU without CPU intervention.
* **Ping-Pong BRAM (Double Buffering)**: Ultra-fast on-chip SRAM functioning identical to **Shared Memory** in CUDA. A Ping-Pong buffer scheme is employed to overlap data transfer with computation, effectively hiding memory latency.

## 4. Project Milestones

### 🏃‍♂️ Phase 1. Hardware Core Implementation (Completed ✅)
- Designed the `NxN` MAC array in **SystemVerilog** based on C++ parallel concepts.
- Automated **Delay Lines** for wavefront data synchronization.
- Implemented **Ping-Pong BRAM** double buffering to hide memory bottlenecks.
- Packaged as a Vivado **AXI4-Lite** IP, perfectly passing timing constraints (**WNS** = 0).

### 🧠 Phase 2. Software Golden Model & Architecture Analysis (WIP 🚀)
- Building a pure Python/NumPy simulator to dissect the Gemma 3N transformer structure from the ground up.
- Simulating **KV Cache** structures and isolating the heavy **MatMul** operations that the NPU can accelerate.
- Testing Matrix slicing and mapping strategies via the `MockTinyNPU` virtual environment before board deployment.

### ⚡ Phase 3. Real Hardware Deployment (Upcoming)
- Setting up Ubuntu and **PYNQ** environments on the Kria KV260 board.
- Replacing the `np.dot` functions in the Python Golden Model with actual NPU **MMIO** control codes (`npu.write/read`).
- Finalizing the local Edge AI demo generating text via Gemma 3N.

## 5. Development Workflow & Tools
* **Hardware**: SystemVerilog, Xilinx Vivado 2025.2
* **Software**: Python, PyTorch, Hugging Face, C/C++, PYNQ
* **Simulation**: Verilator, VS Code
