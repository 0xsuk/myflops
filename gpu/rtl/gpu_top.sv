module gpu_top
  import gpu_pkg::*;
(
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    start,
  output logic                    done,

  input  logic                    imem_we,
  input  logic [PC_WIDTH-1:0]     imem_waddr,
  input  logic [INSTR_WIDTH-1:0]  imem_wdata,

  input  logic                    gmem_ext_re,
  input  logic                    gmem_ext_we,
  input  logic [ADDR_WIDTH-1:0]   gmem_ext_addr,
  input  logic [DATA_WIDTH-1:0]   gmem_ext_wdata,
  output logic [DATA_WIDTH-1:0]   gmem_ext_rdata
);

  logic [INSTR_WIDTH-1:0] imem [IMEM_SIZE];

  logic [PC_WIDTH-1:0]    core_imem_addr  [NUM_CORES];
  logic [INSTR_WIDTH-1:0] core_imem_rdata [NUM_CORES];

  logic                   core_gmem_re    [NUM_CORES];
  logic                   core_gmem_we    [NUM_CORES];
  logic [ADDR_WIDTH-1:0]  core_gmem_addr  [NUM_CORES];
  logic [DATA_WIDTH-1:0]  core_gmem_wdata [NUM_CORES];
  logic [DATA_WIDTH-1:0]  core_gmem_rdata [NUM_CORES];
  logic                   core_gmem_stall [NUM_CORES];

  logic                   core_smem_re    [NUM_CORES];
  logic                   core_smem_we    [NUM_CORES];
  logic [ADDR_WIDTH-1:0]  core_smem_addr  [NUM_CORES];
  logic [DATA_WIDTH-1:0]  core_smem_wdata [NUM_CORES];
  logic [DATA_WIDTH-1:0]  core_smem_rdata [NUM_CORES];

  logic                   core_done       [NUM_CORES];
  warp_state_t            core_warp_state [NUM_CORES];

  logic                   core_barrier_req [NUM_CORES];
  logic                   barrier_release;

  logic                   all_at_barrier;
  always_comb begin
    all_at_barrier = 1'b1;
    for (int j = 0; j < NUM_CORES; j++)
      all_at_barrier = all_at_barrier & core_barrier_req[j];
  end
  assign barrier_release = all_at_barrier;

  always_ff @(posedge clk) begin
    if (imem_we)
      imem[imem_waddr] <= imem_wdata;
  end

  for (genvar i = 0; i < NUM_CORES; i++) begin : gen_cores
    assign core_imem_rdata[i] = imem[core_imem_addr[i]];

    streaming_processor #(.CORE_ID(i)) u_sp (
      .clk             (clk),
      .rst_n           (rst_n),
      .start           (start),
      .done            (core_done[i]),
      .warp_state      (core_warp_state[i]),
      .imem_rdata      (core_imem_rdata[i]),
      .imem_addr       (core_imem_addr[i]),
      .gmem_re         (core_gmem_re[i]),
      .gmem_we         (core_gmem_we[i]),
      .gmem_addr       (core_gmem_addr[i]),
      .gmem_wdata      (core_gmem_wdata[i]),
      .gmem_rdata      (core_gmem_rdata[i]),
      .gmem_stall      (core_gmem_stall[i]),
      .smem_re         (core_smem_re[i]),
      .smem_we         (core_smem_we[i]),
      .smem_addr       (core_smem_addr[i]),
      .smem_wdata      (core_smem_wdata[i]),
      .smem_rdata      (core_smem_rdata[i]),
      .barrier_req     (core_barrier_req[i]),
      .barrier_release (barrier_release)
    );

    shared_memory u_smem (
      .clk   (clk),
      .rst_n (rst_n),
      .re    (core_smem_re[i]),
      .we    (core_smem_we[i]),
      .addr  (core_smem_addr[i]),
      .wdata (core_smem_wdata[i]),
      .rdata (core_smem_rdata[i])
    );
  end

  logic                   gmem_re_mux;
  logic                   gmem_we_mux;
  logic [ADDR_WIDTH-1:0]  gmem_addr_mux;
  logic [DATA_WIDTH-1:0]  gmem_wdata_mux;
  logic [DATA_WIDTH-1:0]  gmem_rdata_out;

  logic [1:0] rr_priority;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rr_priority <= 2'd0;
    else
      rr_priority <= rr_priority + 2'd1;
  end

  logic                   core_gmem_req [NUM_CORES];
  logic [1:0]             grant_id;
  logic                   any_core_req;

  always_comb begin
    for (int j = 0; j < NUM_CORES; j++)
      core_gmem_req[j] = core_gmem_re[j] || core_gmem_we[j];
  end

  always_comb begin
    grant_id = 2'd0;
    any_core_req = 1'b0;

    for (int j = 0; j < NUM_CORES; j++) begin
      int idx;
      idx = (int'(rr_priority) + j) % NUM_CORES;
      if (!any_core_req && core_gmem_req[idx]) begin
        grant_id = 2'(idx);
        any_core_req = 1'b1;
      end
    end
  end

  always_comb begin
    for (int j = 0; j < NUM_CORES; j++) begin
      if (core_gmem_req[j] && (2'(j) != grant_id))
        core_gmem_stall[j] = 1'b1;
      else
        core_gmem_stall[j] = 1'b0;
    end
  end

  always_comb begin
    gmem_re_mux    = gmem_ext_re;
    gmem_we_mux    = gmem_ext_we;
    gmem_addr_mux  = gmem_ext_addr;
    gmem_wdata_mux = gmem_ext_wdata;

    if (!gmem_ext_we && !gmem_ext_re && any_core_req) begin
      gmem_re_mux    = core_gmem_re[grant_id];
      gmem_we_mux    = core_gmem_we[grant_id];
      gmem_addr_mux  = core_gmem_addr[grant_id];
      gmem_wdata_mux = core_gmem_wdata[grant_id];
    end
  end

  memory_controller u_gmem (
    .clk   (clk),
    .rst_n (rst_n),
    .re    (gmem_re_mux),
    .we    (gmem_we_mux),
    .addr  (gmem_addr_mux),
    .wdata (gmem_wdata_mux),
    .rdata (gmem_rdata_out),
    .ready ()
  );

  assign gmem_ext_rdata = gmem_rdata_out;

  for (genvar i = 0; i < NUM_CORES; i++) begin : gen_gmem_rdata
    assign core_gmem_rdata[i] = gmem_rdata_out;
  end

  always_comb begin
    done = 1'b1;
    for (int j = 0; j < NUM_CORES; j++)
      done = done & core_done[j];
  end

endmodule
