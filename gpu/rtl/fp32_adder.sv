module fp32_adder (
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic [31:0] result
);

  logic        sign_a, sign_b, sign_r;
  logic [7:0]  exp_a, exp_b, exp_large;
  logic [23:0] mant_a, mant_b, mant_large, mant_small, mant_shifted;
  logic [24:0] mant_r, mant_norm;
  logic [7:0]  exp_diff, exp_norm;
  logic        swap, sign_small;

  always_comb begin
    sign_a = a[31];
    sign_b = b[31];
    exp_a  = a[30:23];
    exp_b  = b[30:23];
    mant_a = (exp_a == 8'b0) ? {1'b0, a[22:0]} : {1'b1, a[22:0]};
    mant_b = (exp_b == 8'b0) ? {1'b0, b[22:0]} : {1'b1, b[22:0]};

    swap = (exp_b > exp_a) || (exp_b == exp_a && mant_b > mant_a);

    mant_large = swap ? mant_b : mant_a;
    mant_small = swap ? mant_a : mant_b;
    sign_r     = swap ? sign_b : sign_a;
    sign_small = swap ? sign_a : sign_b;
    exp_large  = swap ? exp_b  : exp_a;

    exp_diff     = exp_large - (swap ? exp_a : exp_b);
    mant_shifted = (exp_diff < 8'd24) ? (mant_small >> exp_diff) : 24'b0;

    if (sign_r == sign_small)
      mant_r = {1'b0, mant_large} + {1'b0, mant_shifted};
    else
      mant_r = {1'b0, mant_large} - {1'b0, mant_shifted};

    mant_norm = mant_r;
    exp_norm  = exp_large;

    if (mant_r[24]) begin
      mant_norm = mant_r >> 1;
      exp_norm  = exp_large + 8'd1;
    end else begin
      for (int i = 0; i < 24; i++) begin
        if (mant_norm != '0 && !mant_norm[23] && exp_norm > 8'd0) begin
          mant_norm = mant_norm << 1;
          exp_norm  = exp_norm - 8'd1;
        end
      end
    end

    result = (mant_norm == '0) ? 32'b0 : {sign_r, exp_norm, mant_norm[22:0]};
  end

endmodule
