// ===| uXC API (High-Level Driver Interface) |====================================
// This is the "CUDA equivalent" for the uXC NPU.
// Application code (sw/gemma3NE4B/) should only call functions from this layer.
// It builds 64-bit VLIW instructions and calls the HAL to issue them.
//
// Instruction encoding reference: docs/ISA.md
// ================================================================================

#ifndef UXC_V1_API_H
#define UXC_V1_API_H

#include <stdint.h>

// ===| Opcode Definitions |======================================================
// Must match isa_x64.svh opcode_e
#define UXC_OP_GEMV    0x0
#define UXC_OP_GEMM    0x1
#define UXC_OP_MEMCPY  0x2
#define UXC_OP_MEMSET  0x3

// ===| Flags Bits (used in GEMV/GEMM) |==========================================
// Must match flags_t in isa_x64.svh
#define UXC_FLAG_FINDEMAX  (1U << 5)  // Extract e_max for output normalization
#define UXC_FLAG_ACCM      (1U << 4)  // Accumulate into dest (do not overwrite)
#define UXC_FLAG_W_SCALE   (1U << 3)  // Apply weight scale during MAC

// ===| Memory Route Codes |======================================================
// Must match data_route_e in isa_memctrl.svh
#define UXC_ROUTE_HOST_TO_L2         0x01
#define UXC_ROUTE_L2_TO_HOST         0x10
#define UXC_ROUTE_L2_TO_L1_GEMM     0x12
#define UXC_ROUTE_L2_TO_L1_GEMV     0x13
#define UXC_ROUTE_GEMV_RES_TO_L2    0x31
#define UXC_ROUTE_GEMM_RES_TO_L2    0x21

// ===| API Init |================================================================
int  uxc_init(void);   // Calls uxc_hal_init() and verifies NPU
void uxc_deinit(void);

// ===| Compute Operations |======================================================

// Issue a GEMV instruction (vector × matrix).
// dest_reg:     destination register/address (17-bit)
// src_addr:     source address (17-bit)
// flags:        OR of UXC_FLAG_* constants
// size_ptr:     pointer to size descriptor (6-bit)
// shape_ptr:    pointer to shape descriptor (6-bit)
// lanes:        number of active parallel lanes (5-bit, 1–16)
void uxc_gemv(uint32_t dest_reg, uint32_t src_addr,
              uint8_t  flags,    uint8_t  size_ptr,
              uint8_t  shape_ptr, uint8_t lanes);

// Issue a GEMM instruction (matrix × matrix).
// Same field layout as GEMV.
void uxc_gemm(uint32_t dest_reg, uint32_t src_addr,
              uint8_t  flags,    uint8_t  size_ptr,
              uint8_t  shape_ptr, uint8_t lanes);

// ===| Memory Operations |=======================================================

// Issue a MEMCPY instruction.
// route:        one of UXC_ROUTE_* constants (encodes from_device + to_device)
// dest_addr:    destination address (17-bit)
// src_addr:     source address (17-bit)
// shape_ptr:    pointer to shape descriptor (6-bit)
// async:        0=blocking, 1=fire-and-forget
void uxc_memcpy(uint8_t  route,     uint32_t dest_addr,
                uint32_t src_addr,  uint8_t  shape_ptr,
                uint8_t  async);

// Issue a MEMSET instruction.
// dest_cache:   0=fmap_shape, 1=weight_shape
// dest_addr:    destination pointer (6-bit)
// a, b, c:      values to set (16-bit each)
void uxc_memset(uint8_t  dest_cache, uint8_t  dest_addr,
                uint16_t a,          uint16_t b, uint16_t c);

// ===| Synchronization |=========================================================
// Block until the NPU completes all issued instructions.
int uxc_sync(uint32_t timeout_us);

#endif // UXC_V1_API_H
