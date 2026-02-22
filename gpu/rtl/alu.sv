module alu
  import gpu_pkg::*;
(
  input  alu_op_t               op,
  input  logic [DATA_WIDTH-1:0] a,
  input  logic [DATA_WIDTH-1:0] b,
  output logic [DATA_WIDTH-1:0] result,
  output logic                  zero
);

  logic [DATA_WIDTH-1:0] fadd_result;

  fp32_adder u_fp32_adder (
    .a      (a),
    .b      (b),
    .result (fadd_result)
  );

  always_comb begin
    case (op)
      ALU_ADD:  result = a + b;
      ALU_SUB:  result = a - b;
      ALU_MUL:  result = a * b;
      ALU_AND:  result = a & b;
      ALU_OR:   result = a | b;
      ALU_XOR:  result = a ^ b;
      ALU_SHL:  result = a << b[4:0];
      ALU_SHR:  result = a >> b[4:0];
      ALU_FADD: result = fadd_result;
      ALU_PASS: result = a;
      default:  result = '0;
    endcase
  end

  assign zero = (result == '0);

endmodule
