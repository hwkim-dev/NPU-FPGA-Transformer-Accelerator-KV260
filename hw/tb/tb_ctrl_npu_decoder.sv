`timescale 1ns / 1ps

// ===============================================================================
// Testbench: tb_ctrl_npu_decoder
// Phase : pccx v002 — front-end instruction dispatch
//
// Purpose
// -------
//   Drives the opcode decoder with one instruction per opcode (plus one
//   intentionally unknown opcode to confirm silent drop) and checks the
//   one-hot valid pulse is asserted for exactly one cycle on the matching
//   output.
// ===============================================================================

`include "GLOBAL_CONST.svh"

import isa_pkg::*;

module tb_ctrl_npu_decoder;

  localparam int N_OPS = 6;  // GEMV GEMM MEMCPY MEMSET CVO unknown

  // ===| Clock + reset |=========================================================
  logic clk;
  logic rst_n;
  initial clk = 1'b0;
  always #2 clk = ~clk;

  // ===| DUT IO |================================================================
  logic [`ISA_WIDTH-1:0] IN_raw_instruction;
  logic                  raw_instruction_pop_valid;
  logic                  OUT_fetch_PC_ready;
  logic                  OUT_GEMV_op_x64_valid;
  logic                  OUT_GEMM_op_x64_valid;
  logic                  OUT_memcpy_op_x64_valid;
  logic                  OUT_memset_op_x64_valid;
  logic                  OUT_cvo_op_x64_valid;
  instruction_op_x64_t   OUT_op_x64;

  ctrl_npu_decoder u_dut (
    .clk                     (clk),
    .rst_n                   (rst_n),
    .IN_raw_instruction      (IN_raw_instruction),
    .raw_instruction_pop_valid(raw_instruction_pop_valid),
    .OUT_fetch_PC_ready      (OUT_fetch_PC_ready),
    .OUT_GEMV_op_x64_valid   (OUT_GEMV_op_x64_valid),
    .OUT_GEMM_op_x64_valid   (OUT_GEMM_op_x64_valid),
    .OUT_memcpy_op_x64_valid (OUT_memcpy_op_x64_valid),
    .OUT_memset_op_x64_valid (OUT_memset_op_x64_valid),
    .OUT_cvo_op_x64_valid    (OUT_cvo_op_x64_valid),
    .OUT_op_x64              (OUT_op_x64)
  );

  // ===| Scoreboard |============================================================
  int errors = 0;

  task automatic expect_valids(
      input string tag,
      input logic gemv,
      input logic gemm,
      input logic memcpy,
      input logic memset,
      input logic cvo
  );
    if (OUT_GEMV_op_x64_valid   !== gemv ||
        OUT_GEMM_op_x64_valid   !== gemm ||
        OUT_memcpy_op_x64_valid !== memcpy ||
        OUT_memset_op_x64_valid !== memset ||
        OUT_cvo_op_x64_valid    !== cvo) begin
      errors++;
      $display("[%0t] %s valids mismatch: got={g=%b G=%b mc=%b ms=%b cvo=%b} exp={g=%b G=%b mc=%b ms=%b cvo=%b}",
               $time, tag,
               OUT_GEMV_op_x64_valid, OUT_GEMM_op_x64_valid,
               OUT_memcpy_op_x64_valid, OUT_memset_op_x64_valid,
               OUT_cvo_op_x64_valid,
               gemv, gemm, memcpy, memset, cvo);
    end
  endtask

  initial begin
    rst_n                    = 1'b0;
    IN_raw_instruction       = '0;
    raw_instruction_pop_valid = 1'b0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    // ─── GEMV (opcode 0x0) ─────────────────────────────────────────
    IN_raw_instruction       = {OP_GEMV, 60'hBEEFCAFEDEAD123};
    raw_instruction_pop_valid = 1'b1;
    @(posedge clk); #1;
    // Decoder is one-cycle — valids are live right after the edge that
    // sampled pop_valid=1.
    expect_valids("GEMV", 1, 0, 0, 0, 0);
    if (OUT_op_x64.instruction !== 60'hBEEFCAFEDEAD123) begin
      errors++;
      $display("[%0t] GEMV body mismatch: got=%h", $time, OUT_op_x64.instruction);
    end

    raw_instruction_pop_valid = 1'b0;
    @(posedge clk); #1;
    // With pop=0, the decoder's else-branch default clears valid next cycle.
    expect_valids("GEMV_off", 0, 0, 0, 0, 0);

    // ─── GEMM (opcode 0x1) ─────────────────────────────────────────
    IN_raw_instruction       = {OP_GEMM, 60'd17};
    raw_instruction_pop_valid = 1'b1;
    @(posedge clk); #1;
    expect_valids("GEMM", 0, 1, 0, 0, 0);
    raw_instruction_pop_valid = 1'b0;
    @(posedge clk); #1;

    // ─── MEMCPY (opcode 0x2) ───────────────────────────────────────
    IN_raw_instruction       = {OP_MEMCPY, 60'd42};
    raw_instruction_pop_valid = 1'b1;
    @(posedge clk); #1;
    expect_valids("MEMCPY", 0, 0, 1, 0, 0);
    raw_instruction_pop_valid = 1'b0;
    @(posedge clk); #1;

    // ─── MEMSET (opcode 0x3) ───────────────────────────────────────
    IN_raw_instruction       = {OP_MEMSET, 60'd99};
    raw_instruction_pop_valid = 1'b1;
    @(posedge clk); #1;
    expect_valids("MEMSET", 0, 0, 0, 1, 0);
    raw_instruction_pop_valid = 1'b0;
    @(posedge clk); #1;

    // ─── CVO (opcode 0x4) ──────────────────────────────────────────
    IN_raw_instruction       = {OP_CVO, 60'h0};
    raw_instruction_pop_valid = 1'b1;
    @(posedge clk); #1;
    expect_valids("CVO", 0, 0, 0, 0, 1);
    raw_instruction_pop_valid = 1'b0;
    @(posedge clk); #1;

    // ─── Unknown opcode (0xF) — must drop silently, all valids stay 0.
    IN_raw_instruction       = {4'hF, 60'h0};
    raw_instruction_pop_valid = 1'b1;
    @(posedge clk); #1;
    expect_valids("UNKNOWN", 0, 0, 0, 0, 0);
    raw_instruction_pop_valid = 1'b0;
    @(posedge clk); #1;

    if (errors == 0) begin
      $display("PASS: %0d cycles, both channels match golden.", N_OPS);
    end else begin
      $display("FAIL: %0d mismatches over %0d cycles.", errors, N_OPS);
    end
    $finish;
  end

  initial begin
    #100000 $display("TIMEOUT"); $finish;
  end

endmodule
