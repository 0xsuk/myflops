module register_file
  import gpu_pkg::*;
(
  input  logic                        clk,
  input  logic                        rst_n,
  input  logic [REG_ADDR_WIDTH-1:0]   rs1_addr,
  input  logic [REG_ADDR_WIDTH-1:0]   rs2_addr,
  output logic [DATA_WIDTH-1:0]       rs1_data,
  output logic [DATA_WIDTH-1:0]       rs2_data,
  input  logic                        we,
  input  logic [REG_ADDR_WIDTH-1:0]   rd_addr,
  input  logic [DATA_WIDTH-1:0]       rd_data
);

  logic [DATA_WIDTH-1:0] regs [NUM_REGS];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_REGS; i++)
        regs[i] <= '0;
    end else if (we && rd_addr != '0) begin
      regs[rd_addr] <= rd_data;
    end
  end

  assign rs1_data = (rs1_addr == '0) ? '0 : regs[rs1_addr];
  assign rs2_data = (rs2_addr == '0) ? '0 : regs[rs2_addr];

endmodule
