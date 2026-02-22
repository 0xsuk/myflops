module shared_memory
  import gpu_pkg::*;
(
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    re,
  input  logic                    we,
  input  logic [ADDR_WIDTH-1:0]   addr,
  input  logic [DATA_WIDTH-1:0]   wdata,
  output logic [DATA_WIDTH-1:0]   rdata
);

  logic [DATA_WIDTH-1:0] mem [SMEM_SIZE];

  initial begin
    for (int i = 0; i < SMEM_SIZE; i++)
      mem[i] = '0;
  end

  always_ff @(posedge clk) begin
    if (we) begin
      mem[addr[$clog2(SMEM_SIZE)-1:0]] <= wdata;
    end
  end

  assign rdata = re ? mem[addr[$clog2(SMEM_SIZE)-1:0]] : '0;

endmodule
