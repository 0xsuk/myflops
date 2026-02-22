module fetch_unit
  import gpu_pkg::*;
(
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    stall,
  input  logic                    flush,
  input  logic                    jump_en,
  input  logic [PC_WIDTH-1:0]     jump_target,
  output logic [PC_WIDTH-1:0]     imem_addr,
  input  logic [INSTR_WIDTH-1:0]  imem_rdata,
  output logic [INSTR_WIDTH-1:0]  instr_out,
  output logic [PC_WIDTH-1:0]     pc_out,
  output logic                    valid_out
);

  logic [PC_WIDTH-1:0] pc_r, pc_next;

  always_comb begin
    if (jump_en)
      pc_next = jump_target;
    else if (stall)
      pc_next = pc_r;
    else
      pc_next = pc_r + PC_WIDTH'(1);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pc_r <= '0;
    else
      pc_r <= pc_next;
  end

  assign imem_addr = pc_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_out <= '0;
      pc_out    <= '0;
      valid_out <= 1'b0;
    end else if (flush) begin
      instr_out <= '0;
      pc_out    <= '0;
      valid_out <= 1'b0;
    end else if (!stall) begin
      instr_out <= imem_rdata;
      pc_out    <= pc_r;
      valid_out <= 1'b1;
    end
  end

endmodule
