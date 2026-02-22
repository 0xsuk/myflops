package gpu_pkg;

  parameter int DATA_WIDTH     = 32;
  parameter int ADDR_WIDTH     = 16;
  parameter int INSTR_WIDTH    = 16;
  parameter int NUM_REGS       = 16;
  parameter int REG_ADDR_WIDTH = 4;
  parameter int WARP_SIZE      = 8;
  parameter int NUM_CORES      = 4;
  parameter int SMEM_SIZE      = 1024;
  parameter int GMEM_SIZE      = 16384;
  parameter int IMEM_SIZE      = 1024;
  parameter int PC_WIDTH       = 10;

  typedef enum logic [3:0] {
    OP_ADD  = 4'h0,
    OP_SUB  = 4'h1,
    OP_MUL  = 4'h2,
    OP_AND  = 4'h3,
    OP_OR   = 4'h4,
    OP_XOR  = 4'h5,
    OP_SHL  = 4'h6,
    OP_SHR  = 4'h7,
    OP_LDR  = 4'h8,
    OP_STR  = 4'h9,
    OP_LI   = 4'hA,
    OP_BEQ  = 4'hB,
    OP_BNE  = 4'hC,
    OP_JMP  = 4'hD,
    OP_SPC  = 4'hE,
    OP_FADD = 4'hF
  } opcode_t;

  typedef enum logic [3:0] {
    SPC_NOP  = 4'h0,
    SPC_HALT = 4'h1,
    SPC_TID  = 4'h2,
    SPC_LDS  = 4'h3,
    SPC_STS  = 4'h4,
    SPC_BAR  = 4'h5
  } special_t;

  typedef enum logic [3:0] {
    ALU_ADD  = 4'h0,
    ALU_SUB  = 4'h1,
    ALU_MUL  = 4'h2,
    ALU_AND  = 4'h3,
    ALU_OR   = 4'h4,
    ALU_XOR  = 4'h5,
    ALU_SHL  = 4'h6,
    ALU_SHR  = 4'h7,
    ALU_FADD = 4'h8,
    ALU_PASS = 4'hF
  } alu_op_t;

  typedef struct packed {
    opcode_t                      opcode;
    logic [REG_ADDR_WIDTH-1:0]    rd;
    logic [REG_ADDR_WIDTH-1:0]    rs1;
    logic [REG_ADDR_WIDTH-1:0]    rs2;
    logic [11:0]                  imm;
    alu_op_t                      alu_op;
    logic                         reg_we;
    logic                         mem_re;
    logic                         mem_we;
    logic                         smem_re;
    logic                         smem_we;
    logic                         is_branch;
    logic                         is_jump;
    logic                         is_halt;
    logic                         is_tid;
    logic                         is_barrier;
  } decoded_instr_t;

  typedef enum logic [1:0] {
    WARP_IDLE    = 2'b00,
    WARP_RUNNING = 2'b01,
    WARP_STALLED = 2'b10,
    WARP_DONE    = 2'b11
  } warp_state_t;

endpackage
