module streaming_processor
  import gpu_pkg::*;
#(
  parameter int CORE_ID = 0
)(
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    start,
  output logic                    done,
  output warp_state_t             warp_state,

  input  logic [INSTR_WIDTH-1:0]  imem_rdata,
  output logic [PC_WIDTH-1:0]     imem_addr,

  output logic                    gmem_re,
  output logic                    gmem_we,
  output logic [ADDR_WIDTH-1:0]   gmem_addr,
  output logic [DATA_WIDTH-1:0]   gmem_wdata,
  input  logic [DATA_WIDTH-1:0]   gmem_rdata,
  input  logic                    gmem_stall,

  output logic                    smem_re,
  output logic                    smem_we,
  output logic [ADDR_WIDTH-1:0]   smem_addr,
  output logic [DATA_WIDTH-1:0]   smem_wdata,
  input  logic [DATA_WIDTH-1:0]   smem_rdata,

  output logic                    barrier_req,
  input  logic                    barrier_release
);

  logic                    fetch_flush, jump_en;
  logic [PC_WIDTH-1:0]     jump_target;
  logic [INSTR_WIDTH-1:0]  fetch_instr;
  logic [PC_WIDTH-1:0]     fetch_pc;
  logic                    fetch_valid;

  decoded_instr_t          dec;
  logic [PC_WIDTH-1:0]     dec_pc;
  logic                    dec_valid;

  logic [DATA_WIDTH-1:0]   rs1_data, rs2_data;
  logic [DATA_WIDTH-1:0]   alu_result;
  logic                    alu_zero;
  logic                    reg_we;
  logic [REG_ADDR_WIDTH-1:0] wb_rd;
  logic [DATA_WIDTH-1:0]   wb_data;

  logic                    halted;
  logic [2:0]              thread_id;

  logic                    barrier_stall;
  logic                    barrier_pending;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      barrier_pending <= 1'b0;
    else if (start)
      barrier_pending <= 1'b0;
    else if (dec_valid & dec.is_barrier & ~gmem_stall)
      barrier_pending <= 1'b1;
    else if (barrier_release)
      barrier_pending <= 1'b0;
  end

  assign barrier_req   = barrier_pending;
  assign barrier_stall = (dec_valid & dec.is_barrier & ~barrier_release) |
                         (barrier_pending & ~barrier_release);

  logic                    pipeline_stall;
  assign pipeline_stall = gmem_stall | barrier_stall;

  fetch_unit u_fetch (
    .clk         (clk),
    .rst_n       (rst_n & ~halted),
    .stall       (pipeline_stall),
    .flush       (fetch_flush),
    .jump_en     (jump_en),
    .jump_target (jump_target),
    .imem_addr   (imem_addr),
    .imem_rdata  (imem_rdata),
    .instr_out   (fetch_instr),
    .pc_out      (fetch_pc),
    .valid_out   (fetch_valid)
  );

  decode_unit u_decode (
    .clk         (clk),
    .rst_n       (rst_n),
    .instr_in    (fetch_instr),
    .pc_in       (fetch_pc),
    .valid_in    (fetch_valid & ~halted),
    .stall       (pipeline_stall),
    .flush       (fetch_flush & ~pipeline_stall),
    .decoded_out (dec),
    .pc_out      (dec_pc),
    .valid_out   (dec_valid)
  );

  register_file u_regfile (
    .clk       (clk),
    .rst_n     (rst_n),
    .rs1_addr  (dec.rs1),
    .rs2_addr  (dec.rs2),
    .rs1_data  (rs1_data),
    .rs2_data  (rs2_data),
    .we        (reg_we),
    .rd_addr   (wb_rd),
    .rd_data   (wb_data)
  );

  logic [DATA_WIDTH-1:0] alu_a, alu_b;

  always_comb begin
    alu_a = rs1_data;
    alu_b = rs2_data;
    if (dec.is_tid)
      alu_a = DATA_WIDTH'(thread_id);
    else if (dec.opcode == OP_LI)
      alu_a = {{(DATA_WIDTH-12){dec.imm[11]}}, dec.imm};
  end

  alu u_alu (
    .op     (dec.alu_op),
    .a      (alu_a),
    .b      (alu_b),
    .result (alu_result),
    .zero   (alu_zero)
  );

  logic branch_taken;
  always_comb begin
    branch_taken = 1'b0;
    if (dec_valid && dec.is_branch && !pipeline_stall) begin
      case (dec.opcode)
        OP_BEQ: branch_taken = alu_zero;
        OP_BNE: branch_taken = ~alu_zero;
        default: ;
      endcase
    end
  end

  assign jump_en     = dec_valid & ~pipeline_stall & (dec.is_jump | branch_taken);
  assign jump_target = dec.is_jump ?
                       dec.imm[PC_WIDTH-1:0] :
                       dec_pc + PC_WIDTH'(signed'(dec.imm[3:0]));
  assign fetch_flush = jump_en;

  assign gmem_re    = dec_valid & dec.mem_re;
  assign gmem_we    = dec_valid & dec.mem_we;
  assign gmem_addr  = rs1_data[ADDR_WIDTH-1:0] + ADDR_WIDTH'(dec.imm[3:0]);
  assign gmem_wdata = rs2_data;

  assign smem_re    = dec_valid & dec.smem_re;
  assign smem_we    = dec_valid & dec.smem_we;
  assign smem_addr  = rs1_data[ADDR_WIDTH-1:0];
  assign smem_wdata = rs2_data;

  always_comb begin
    reg_we  = dec_valid & dec.reg_we & ~halted & ~pipeline_stall;
    wb_rd   = dec.rd;
    wb_data = alu_result;
    if (dec.mem_re)
      wb_data = gmem_rdata;
    else if (dec.smem_re)
      wb_data = smem_rdata;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      halted    <= 1'b0;
      thread_id <= 3'(CORE_ID);
    end else if (start) begin
      halted    <= 1'b0;
      thread_id <= 3'(CORE_ID);
    end else if (dec_valid & dec.is_halt & ~pipeline_stall) begin
      halted <= 1'b1;
    end
  end

  assign done       = halted;
  assign warp_state = halted ? WARP_DONE : WARP_RUNNING;

endmodule
