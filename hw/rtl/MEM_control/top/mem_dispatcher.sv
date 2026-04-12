`timescale 1ns / 1ps
`include "GEMM_Array.svh"
`include "GLOBAL_CONST.svh"

import isa_pkg::*;

module mem_dispatcher #(
) (
    input logic clk_core,    // 400MHz
    input logic rst_n_core,
    input logic clk_axi,     // 250MHz
    input logic rst_axi_n,

    // ===| External AXI-Stream (From PS & DDR4) |=================
    axis_if.slave  S_AXIS_ACP_FMAP,
    axis_if.master M_AXIS_ACP_RESULT, // TO ps.


    input memory_control_uop_t IN_LOAD_uop,
    input memory_set_uop_t     IN_mem_set_uop,

    output logic OUT_fifo_full
);

  logic acp_cmd_fifo_full;
  logic npu_cmd_fifo_full;

  always_comb begin
    OUT_fifo_full = acp_cmd_fifo_full | npu_cmd_fifo_full;
  end

  logic        fmap_write_enable;
  logic [ 5:0] fmap_shape_read_address;
  logic [16:0] fmap_arr_shape_X;
  logic [16:0] fmap_arr_shape_Y;
  logic [16:0] fmap_arr_shape_Z;

  logic [16:0] fmap_read_arr_shape_X;
  logic [16:0] fmap_read_arr_shape_Y;
  logic [16:0] fmap_read_arr_shape_Z;

  logic        weight_write_enable;
  logic [ 5:0] weight_shape_read_address;
  logic [16:0] weight_arr_shape_X;
  logic [16:0] weight_arr_shape_Y;
  logic [16:0] weight_arr_shape_Z;

  logic [16:0] weight_read_arr_shape_X;
  logic [16:0] weight_read_arr_shape_Y;
  logic [16:0] weight_read_arr_shape_Z;

  always_ff @(posedge clk_core) begin
    if (!rst_n_core) begin
    end else begin
      case (IN_mem_set_uop.dest_cache)
        data_to_fmap_shape: begin
          // ===| [PORT] AXI LITE |==============================

          fmap_shape_read_address <= IN_mem_set_uop.dest_addr;
          fmap_arr_shape_X <= IN_mem_set_uop.a_value;
          fmap_arr_shape_Y <= IN_mem_set_uop.b_value;
          fmap_arr_shape_Z <= IN_mem_set_uop.c_value;
          fmap_write_enable <= 1;

          // ===| [PORT] AXI LITE |==============================
        end
        data_to_weight_shape: begin
          // ===| [PORT] AXI LITE |==============================

          weight_shape_read_address <= mem_set_uop.dest_addr;
          weight_arr_shape_X <= IN_mem_set_uop.a_value;
          weight_arr_shape_Y <= IN_mem_set_uop.b_value;
          weight_arr_shape_Z <= IN_mem_set_uop.c_value;
          weight_write_enable <= 1;

          // ===| [PORT] AXI LITE |==============================
        end
        default: begin
        end
      endcase
    end
  end


  fmap_array_shape u_fmap_shape (
      .clk  (clk_core),
      .rst_n(rst_n_core),

      // ===| write |=========================================
      .wr_en  (fmap_write_enable),        // true / false
      .wr_addr(fmap_shape_read_address),  // address
      .wr_val0(fmap_arr_shape_X),         // shape: x
      .wr_val1(fmap_arr_shape_Y),         // shape: y
      .wr_val2(fmap_arr_shape_Z),         // shape: z

      // ===| read  |=========================================
      .rd_addr(fmap_shape_read_address),  // address
      .rd_val0(fmap_read_arr_shape_X),    // shape: x
      .rd_val1(fmap_read_arr_shape_Y),    // shape: y
      .rd_val2(fmap_read_arr_shape_Z)     // shape: z
  );






  //implicit casting: result of X*Y*Z is smaller then 2^17
  logic [16:0] weight_shape;

  assign weight_shape = weight_read_arr_shape_X * weight_read_arr_shape_Y * weight_read_arr_shape_Z;
  // stride
  // block size
  weight_array_shape u_weight_shape (
      .clk  (clk_core),
      .rst_n(rst_n_core),

      // ===| write |=========================================
      .wr_en  (weight_write_enable),           // true / false
      .wr_addr(IN_weight_shape_read_address),  // address
      .wr_val0(weight_arr_shape_X),            // shape: x
      .wr_val1(weight_arr_shape_Y),            // shape: y
      .wr_val2(weight_arr_shape_Z),            // shape: z

      // ===| read  |=========================================
      .rd_addr(IN_weight_shape_read_address),  // address
      .rd_val0(weight_read_arr_shape_X),       // shape: x
      .rd_val1(weight_read_arr_shape_Y),       // shape: y
      .rd_val2(weight_read_arr_shape_Z)        // shape: z
  );


  ptr_addr_t        fmap_shape_read_address_wire;

  logic             IN_acp_rdy;
  acp_uop_t         acp_uop;
  acp_uop_t         OUT_acp_cmd;
  // Trigger to accept ACP data
  logic             acp_rx_start;
  logic      [16:0] acp_base_addr;
  logic             acp_write_en;
  logic      [16:0] acp_end_addr;


  logic             IN_npu_rdy;
  npu_uop_t         npu_uop;
  npu_uop_t         OUT_npu_cmd;
  logic             npu_rx_start;
  logic      [16:0] npu_base_addr;
  logic             npu_write_en;
  logic      [16:0] npu_end_addr;


  always_ff @(posedge clk_core) begin
    if (!rst_n_core) begin
    end else begin
      acp_rx_start <= 0;
      case (IN_LOAD_uop.data_dest)
        from_host_to_L2: begin
          // ===| [PORT] ACP IN |==============================

          acp_uop <= '{
              acp_write_en_wire   : `PORT_MOD_E_WRITE,
              acp_base_addr_wire  : IN_LOAD_uop.dest_addr,
              acp_end_addr        : {16'b0}
          };
          acp_rx_start <= 1;
          IN_fmap_shape_read_address <= IN_LOAD_uop.shape_ptr_addr;

          // ===| [PORT] ACP IN |==============================
        end
        from_L2_to_host: begin
          // ===| [PORT] ACP OUT |==============================

          acp_uop <= '{
              acp_write_en_wire   : `PORT_MOD_E_READ,
              acp_base_addr_wire  : IN_LOAD_uop.dest_addr,
              acp_end_addr        : {16'b0}
          };

          acp_rx_start <= 1;
          IN_fmap_shape_read_address <= IN_LOAD_uop.shape_ptr_addr;

          // ===| [PORT] ACP OUT |==============================
        end
        from_L2_to_L1_GEMM: begin
          // ===| [PORT] NPU INTERNAL WIRE (L2)OUT |==============================

          npu_uop <= '{
              npu_write_en_wire   : `PORT_MOD_E_READ,
              npu_base_addr_wire  : IN_LOAD_uop.dest_addr,
              npu_end_addr        : {16'b0}
          };

          // ===| [PORT] NPU INTERNAL WIRE (L2)OUT |==============================
        end
        from_L2_to_L1_GEMV: begin
          // ===| [PORT] NPU INTERNAL WIRE (L2)OUT |==============================

          npu_uop <= '{
              npu_write_en_wire   : `PORT_MOD_E_READ,
              npu_base_addr_wire  : IN_LOAD_uop.dest_addr,
              npu_end_addr        : {16'b0}
          };

          // ===| [PORT] NPU INTERNAL WIRE (L2)OUT |==============================
        end
        from_GEMV_res_to_L2: begin
          // ===| [PORT] NPU INTERNAL WIRE (L2)IN |==============================



          // ===| [PORT] NPU INTERNAL WIRE (L2)IN |==============================
        end
        from_gemm_res_to_L2: begin
          // ===| [PORT] NPU INTERNAL WIRE (L2)IN |==============================



          // ===| [PORT] NPU INTERNAL WIRE (L2)IN |==============================
        end
        default: begin
        end
      endcase
    end
  end


  //implicit casting: result of X*Y*Z is smaller then 2^17
  logic [16:0] shape_total;

  assign shape_total = fmap_read_arr_shape_X * fmap_read_arr_shape_Y * fmap_read_arr_shape_Z;

  always_ff @(posedge clk_core) begin
    if (!rst_n_core) begin
    end else begin
      if (acp_rx_start) begin

        acp_uop.acp_end_addr <= acp_uop.acp_base_addr_wire + (shape_total);

        IN_acp_rdy <= 1;
        IN_npu_rdy <= 0;

      end else if (npu_rx_start) begin

        npu_uop.npu_end_addr <= npu_uop.npu_base_addr_wire + (shape_total);

        IN_npu_rdy <= 1;
        IN_acp_rdy <= 0;

      end else begin

        IN_npu_rdy <= 0;
        IN_acp_rdy <= 0;

      end
    end
  end



  //memory_control_uop_t         LOAD_uop;
  logic         fifo_over_thresh_full;
  logic         fifo_empty;
  logic [127:0] fifo_dout;
  logic         read_enable_signal;

  // ===| L2 cache Pipeline Control (To/From Dispatcher)(KV,FMAP) |==
  logic         acp_write_en_wire;
  logic [ 16:0] acp_base_addr_wire;
  logic         acp_rx_start_wire;
  logic         acp_is_busy_wire;

  logic         OUT_acp_cmd_valid;

  // ===| NPU (Internal) Compute Access (Port B) |=====================
  logic         npu_write_en_wire;
  logic [ 16:0] npu_base_addr_wire;
  logic         npu_rx_start_wire;
  logic         npu_is_busy_wire;

  logic         OUT_npu_cmd_valid;

  mem_u_operation_queue #() u_operation_queue (
      .clk_core  (clk_core),
      .rst_n_core(rst_n_core),

      // [Port] ACP
      .IN_acp_rdy(IN_acp_rdy),
      .IN_acp_cmd(acp_uop),
      .OUT_acp_cmd(OUT_acp_cmd),
      .OUT_acp_cmd_valid(OUT_acp_cmd_valid),
      .OUT_acp_cmd_fifo_full(acp_cmd_fifo_full),
      .IN_acp_is_busy(acp_is_busy_wire),

      // [Port] Internal NPU
      .IN_npu_rdy(IN_npu_rdy),
      .IN_npu_cmd(npu_uop),
      .OUT_npu_cmd(OUT_npu_cmd),
      .OUT_npu_cmd_valid(OUT_npu_cmd_valid),
      .OUT_npu_cmd_fifo_full(npu_cmd_fifo_full),
      .IN_npu_is_busy(npu_is_busy_wire)
  );

  mem_GLOBAL_cache #() u_mem_dispatcher (
      .clk_core  (clk_core),
      .rst_n_core(rst_n_core),

      .clk_axi  (clk_axi),
      .rst_axi_n(rst_axi_n),

      // ACP      = featureMAP in, out (Full-Duplex), read & write at same time
      .S_AXIS_ACP_FMAP  (S_AXIS_ACP_FMAP),   // Feature Map Input 0 (128-bit, HPC0)
      .M_AXIS_ACP_RESULT(M_AXIS_ACP_RESULT), // Final Result Output (128-bit)

      // ===| L2 cache Pipeline Control (To/From Dispatcher)(KV,FMAP) |==
      .IN_acp_write_en (OUT_acp_cmd.acp_write_en_wire),   // A port mod to write or read
      .IN_acp_base_addr(OUT_acp_cmd.acp_base_addr_wire),
      .IN_acp_end_addr (OUT_acp_cmd.acp_end_addr),
      .IN_acp_rx_start (OUT_acp_cmd_valid),
      .OUT_acp_is_busy (acp_is_busy_wire),


      // NPU (Internal) Compute Access (Port B)
      .IN_npu_write_en (OUT_npu_cmd.npu_write_en_wire),
      .IN_npu_base_addr(OUT_npu_cmd.npu_base_addr_wire),
      .IN_npu_end_addr (OUT_npu_cmd.npu_end_addr),
      .IN_npu_rx_start (OUT_npu_cmd_valid),

      .OUT_npu_is_busy(npu_is_busy_wire),

      .IN_npu_wdata (IN_npu_wdata),
      .OUT_npu_rdata(OUT_npu_rdata)
  );


endmodule
