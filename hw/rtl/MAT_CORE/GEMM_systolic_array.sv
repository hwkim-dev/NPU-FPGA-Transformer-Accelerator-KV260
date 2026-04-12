`timescale 1ns / 1ps

`include "GLOBAL_CONST.svh"
`include "GEMM_Array.svh"

module GEMM_systolic_array #(
    parameter array_horizontal = `ARRAY_SIZE_H,
    parameter array_vertical = `ARRAY_SIZE_V,
    parameter h_in_size = `GEMM_MAC_UNIT_IN_H,
    parameter v_in_size = `GEMM_MAC_UNIT_IN_V
) (
    input logic clk,
    input logic rst_n,
    input logic i_clear,

    // =| Global Controls |=
    input logic i_weight_valid,  // Enables horizontal weight shifting

    // =| Delay line input (from FMap Cache and Weight Dispatcher) |=
    input logic [h_in_size-1:0] H_in[0:array_horizontal-1],
    input logic [v_in_size-1:0] V_in[0:array_vertical-1],
    input logic in_valid[0:array_vertical-1],  // Staggered valid from FMap delay line

    // =| VLIW Instruction Input (Staggered along with V_in) |=
    input logic [2:0] inst_in      [0:array_horizontal-1],
    input logic       inst_valid_in[  0:array_vertical-1],

    // =| Outputs |=
    output logic [`DSP48E2_POUT_SIZE-1:0] V_out      [   0:array_horizontal-1],
    output logic [`DSP48E2_POUT_SIZE-1:0] V_ACC_out  [   0:array_horizontal-1],
    output logic                          V_ACC_valid[0:array_horizontalE_V-1]
);

  // ===| Systolic Array Internal Wires |==================================

  // Horizontal logic wires (Weights)
  // Size is [Row][Col], data flows Left to Right.
  // H_in feeds into Col 0.
  logic [`GEMM_MAC_UNIT_IN_H - 1 : 0] gemm_H_wire[0 : array_horizontal-1][0 : array_vertical];
  logic [`GEMM_MAC_UNIT_IN_H - 1 : 0] gemm_H_REG[0 : array_horizontal-1][0 : array_vertical];

  // Vertical logic wires (Feature Map / ACIN)
  // Size is [Row][Col], data flows Top to Bottom.
  logic [29:0] gemm_ACIN_wire[0 : array_horizontal][0 : array_vertical-1];

  // Instruction logic wires (Top to Bottom)
  logic [2:0] gemm_inst_wire[0 : array_horizontal][0 : array_vertical-1];
  logic gemm_inst_valid_wire[0 : array_horizontal][0 : array_vertical-1];

  // Valid signal logic wires (Top to Bottom)
  logic gemm_V_valid_wire[0 : array_horizontal][0 : array_vertical-1];

  // Result shift wires (Top to Bottom)
  logic [`DSP48E2_POUT_SIZE - 1 : 0] gemm_V_result_wire[0 : array_horizontal][0 : array_vertical-1];

  // Fabric break wires for row 15 -> 16
  logic [47:0] gemm_P_fabric_wire[0 : array_horizontal-1][0 : array_vertical-1];

  // V_in fabric delay line to replace A_fabric_wire
  logic [29:0] gemm_in_V_fabric[0 : array_horizontal][0 : array_vertical-1];

  // ======================================================================

  // ===| Input Assignments |==============================================
  // >>>| TOP INPUT LANE |<<<
  genvar i;
  generate
    for (i = 0; i < array_vertical; i++) begin : assign_v_inputs
      // Top row ACIN is not used (A is used directly) 30'd0;
      assign gemm_ACIN_wire[0][i] = '0;
      assign gemm_inst_wire[0][i] = inst_in[i];
      assign gemm_inst_valid_wire[0][i] = inst_valid_in[i];
      assign gemm_V_valid_wire[0][i] = in_valid[i];
      assign gemm_V_result_wire[0][i] = '0;
      //48'd0;  // Top row PCIN is 0

      // Initialize the fabric delay line with V_in padded to 30 bits
      assign gemm_in_V_fabric[0][i] = {3'd0, V_in[i]};
    end

    for (i = 0; i < array_horizontal; i++) begin : assign_h_inputs
      assign gemm_H_wire[i][0] = H_in[i];
    end
  endgenerate

  // >>>| Normal Lane |<<<
  // Fabric delay line for V_in to reach row 16 correctly
  genvar d_row, d_col;
  generate
    for (d_row = 0; d_row < array_horizontal; d_row++) begin : v_delay_row
      for (d_col = 0; d_col < array_vertical; d_col++) begin : v_delay_col
        always_ff @(posedge clk) begin
          if (gemm_V_valid_wire[d_row][d_col]) begin
            gemm_in_V_fabric[d_row+1][d_col] <= gemm_in_V_fabric[d_row][d_col];
          end
        end
      end
    end
  endgenerate

  // ===| 2D Array Instantiation |=========================================
  genvar row, col;
  generate
    for (row = 0; row < array_horizontal; row++) begin : gemm_row_loop
      for (col = 0; col < array_vertical; col++) begin : gemm_col_loop

        if (row == array_horizontal - 1) begin : last_row
          GEMM_dsp_unit_last_ROW #(
              .IS_TOP_ROW(0)
          ) dsp_unit_last_ROW (
              .clk(clk),
              .rst_n(rst_n),
              .i_clear(i_clear),

              .i_valid(gemm_V_valid_wire[row][col]),
              .inst_valid_in_V(gemm_inst_valid_wire[row][col]),
              .i_weight_valid(i_weight_valid),
              .o_valid(gemm_V_valid_wire[row+1][col]),

              .in_H (gemm_H_wire[row][col]),
              .out_H(gemm_H_wire[row][col+1]),

              .ACIN_in  (gemm_ACIN_wire[row][col]),
              .ACOUT_out(gemm_ACIN_wire[row+1][col]),

              .instruction_in_V (gemm_inst_wire[row][col]),
              .instruction_out_V(gemm_inst_wire[row+1][col]),
              .inst_valid_out_V (gemm_inst_valid_wire[row+1][col]),

              .V_result_in (gemm_V_result_wire[row][col]),
              .V_result_out(gemm_V_result_wire[row+1][col]),

              .gemm_unit_results(V_out[col])
          );
        end else if (row == 16) begin : break_row
          GEMM_dsp_unit #(
              .IS_TOP_ROW(0),
              .BREAK_CASCADE(1)
          ) dsp_unit_break (
              .clk(clk),
              .rst_n(rst_n),
              .i_clear(i_clear),

              .i_valid(gemm_V_valid_wire[row][col]),
              .inst_valid_in_V(gemm_inst_valid_wire[row][col]),
              .i_weight_valid(i_weight_valid),
              .o_valid(gemm_V_valid_wire[row+1][col]),

              .in_H (gemm_H_wire[row][col]),
              .out_H(gemm_H_wire[row][col+1]),

              // Take delayed input from fabric shift register instead of CASCADE
              .in_V(gemm_in_V_fabric[row][col]),
              .ACIN_in(30'd0),
              .ACOUT_out(gemm_ACIN_wire[row+1][col]),

              .instruction_in_V (gemm_inst_wire[row][col]),
              .instruction_out_V(gemm_inst_wire[row+1][col]),
              .inst_valid_out_V (gemm_inst_valid_wire[row+1][col]),

              // Take result from previous row's P fabric out
              .V_result_in (gemm_P_fabric_wire[row-1][col]),
              .V_result_out(gemm_V_result_wire[row+1][col]),
              .P_fabric_out(gemm_P_fabric_wire[row][col])
          );
        end else begin : normal_row
          GEMM_dsp_unit #(
              .IS_TOP_ROW(row == 0 ? 1 : 0),
              .BREAK_CASCADE(0)
          ) dsp_unit (
              .clk(clk),
              .rst_n(rst_n),
              .i_clear(i_clear),

              .i_valid(gemm_V_valid_wire[row][col]),
              .inst_valid_in_V(gemm_inst_valid_wire[row][col]),
              .i_weight_valid(i_weight_valid),
              .o_valid(gemm_V_valid_wire[row+1][col]),

              .in_H (gemm_H_wire[row][col]),
              .out_H(gemm_H_wire[row][col+1]),

              .in_V(row == 0 ? {3'd0, V_in[col]} : 30'd0),
              .ACIN_in(gemm_ACIN_wire[row][col]),
              .ACOUT_out(gemm_ACIN_wire[row+1][col]),

              .instruction_in_V (gemm_inst_wire[row][col]),
              .instruction_out_V(gemm_inst_wire[row+1][col]),
              .inst_valid_out_V (gemm_inst_valid_wire[row+1][col]),

              .V_result_in (gemm_V_result_wire[row][col]),
              .V_result_out(gemm_V_result_wire[row+1][col]),
              .P_fabric_out(gemm_P_fabric_wire[row][col])
          );
        end
      end
    end

    // Accumulators for the final row
    for (col = 0; col < array_vertical; col++) begin : gemm_ACC_col_loop
      assign V_ACC_valid[col] = gemm_inst_valid_wire[array_horizontal][col];
      GEMM_accumulator #() gemm_ACC (
          .clk(clk),
          .rst_n(rst_n),
          .i_clear(i_clear),
          // Accumulator should trigger when the last row outputs a valid result
          .i_valid(V_ACC_valid[col]),
          // PCIN connects to the V_result_out of the LAST_ROW (which is stored in [array_horizontal])
          .PCIN(gemm_V_result_wire[array_horizontal][col]),
          .gemm_ACC_result(V_ACC_out[col])
      );
    end
  endgenerate

endmodule
