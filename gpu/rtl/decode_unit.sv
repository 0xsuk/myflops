module decode_unit
  import gpu_pkg::*;
(
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic [INSTR_WIDTH-1:0]  instr_in,
  input  logic [PC_WIDTH-1:0]     pc_in,
  input  logic                    valid_in,
  input  logic                    stall,
  input  logic                    flush,
  output decoded_instr_t          decoded_out,
  output logic [PC_WIDTH-1:0]     pc_out,
  output logic                    valid_out
);

  decoded_instr_t decoded;
  opcode_t opc;
  special_t spc;

  always_comb begin
    decoded = '0;
    opc = opcode_t'(instr_in[15:12]);
    decoded.opcode = opc;

    case (opc)
      OP_ADD, OP_SUB, OP_MUL,
      OP_AND, OP_OR, OP_XOR,
      OP_SHL, OP_SHR, OP_FADD: begin
        decoded.rd     = instr_in[11:8];
        decoded.rs1    = instr_in[7:4];
        decoded.rs2    = instr_in[3:0];
        decoded.reg_we = 1'b1;
        case (opc)
          OP_ADD:  decoded.alu_op = ALU_ADD;
          OP_SUB:  decoded.alu_op = ALU_SUB;
          OP_MUL:  decoded.alu_op = ALU_MUL;
          OP_AND:  decoded.alu_op = ALU_AND;
          OP_OR:   decoded.alu_op = ALU_OR;
          OP_XOR:  decoded.alu_op = ALU_XOR;
          OP_SHL:  decoded.alu_op = ALU_SHL;
          OP_SHR:  decoded.alu_op = ALU_SHR;
          OP_FADD: decoded.alu_op = ALU_FADD;
          default: decoded.alu_op = ALU_ADD;
        endcase
      end

      OP_LDR: begin
        decoded.rd     = instr_in[11:8];
        decoded.rs1    = instr_in[7:4];
        decoded.imm    = {8'b0, instr_in[3:0]};
        decoded.alu_op = ALU_ADD;
        decoded.reg_we = 1'b1;
        decoded.mem_re = 1'b1;
      end

      OP_STR: begin
        decoded.rd     = instr_in[11:8];
        decoded.rs1    = instr_in[7:4];
        decoded.rs2    = instr_in[11:8];
        decoded.imm    = {8'b0, instr_in[3:0]};
        decoded.alu_op = ALU_ADD;
        decoded.mem_we = 1'b1;
      end

      OP_LI: begin
        decoded.rd     = instr_in[11:8];
        decoded.imm    = {{4{instr_in[7]}}, instr_in[7:0]};
        decoded.alu_op = ALU_PASS;
        decoded.reg_we = 1'b1;
      end

      OP_BEQ: begin
        decoded.rs1       = instr_in[11:8];
        decoded.rs2       = instr_in[7:4];
        decoded.imm       = {{8{instr_in[3]}}, instr_in[3:0]};
        decoded.is_branch = 1'b1;
        decoded.alu_op    = ALU_SUB;
      end

      OP_BNE: begin
        decoded.rs1       = instr_in[11:8];
        decoded.rs2       = instr_in[7:4];
        decoded.imm       = {{8{instr_in[3]}}, instr_in[3:0]};
        decoded.is_branch = 1'b1;
        decoded.alu_op    = ALU_SUB;
      end

      OP_JMP: begin
        decoded.imm     = instr_in[11:0];
        decoded.is_jump = 1'b1;
      end

      OP_SPC: begin
        spc = special_t'(instr_in[11:8]);
        case (spc)
          SPC_NOP: ;
          SPC_HALT: decoded.is_halt = 1'b1;
          SPC_TID: begin
            decoded.rd     = instr_in[7:4];
            decoded.is_tid = 1'b1;
            decoded.reg_we = 1'b1;
            decoded.alu_op = ALU_PASS;
          end
          SPC_LDS: begin
            decoded.rd      = instr_in[7:4];
            decoded.rs1     = instr_in[3:0];
            decoded.reg_we  = 1'b1;
            decoded.smem_re = 1'b1;
            decoded.alu_op  = ALU_PASS;
          end
          SPC_STS: begin
            decoded.rd      = instr_in[7:4];
            decoded.rs1     = instr_in[3:0];
            decoded.rs2     = instr_in[7:4];
            decoded.smem_we = 1'b1;
          end
          SPC_BAR: decoded.is_barrier = 1'b1;
          default: ;
        endcase
      end

      default: ;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      decoded_out <= '0;
      pc_out      <= '0;
      valid_out   <= 1'b0;
    end else if (flush) begin
      decoded_out <= '0;
      pc_out      <= '0;
      valid_out   <= 1'b0;
    end else if (!stall) begin
      decoded_out <= decoded;
      pc_out      <= pc_in;
      valid_out   <= valid_in;
    end
  end

endmodule
