module memory_controller
  import gpu_pkg::*;
(
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    re,
  input  logic                    we,
  input  logic [ADDR_WIDTH-1:0]   addr,
  input  logic [DATA_WIDTH-1:0]   wdata,
  output logic [DATA_WIDTH-1:0]   rdata,
  output logic                    ready
);

  logic [DATA_WIDTH-1:0] gmem [GMEM_SIZE];

  initial begin
    for (int i = 0; i < GMEM_SIZE; i++)
      gmem[i] = '0;
  end

  always_ff @(posedge clk) begin
    if (we) begin
      gmem[addr[$clog2(GMEM_SIZE)-1:0]] <= wdata;
    end
  end

  assign rdata = re ? gmem[addr[$clog2(GMEM_SIZE)-1:0]] : '0;
  assign ready = 1'b1;

endmodule
