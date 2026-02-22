module tb_gpu_top;
  import gpu_pkg::*;

  reg                     clk;
  reg                     rst_n;
  reg                     start;
  wire                    done;
  reg                     imem_we;
  reg  [PC_WIDTH-1:0]     imem_waddr;
  reg  [INSTR_WIDTH-1:0]  imem_wdata;
  reg                     gmem_ext_re;
  reg                     gmem_ext_we;
  reg  [ADDR_WIDTH-1:0]   gmem_ext_addr;
  reg  [DATA_WIDTH-1:0]   gmem_ext_wdata;
  wire [DATA_WIDTH-1:0]   gmem_ext_rdata;

  gpu_top u_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .start          (start),
    .done           (done),
    .imem_we        (imem_we),
    .imem_waddr     (imem_waddr),
    .imem_wdata     (imem_wdata),
    .gmem_ext_re    (gmem_ext_re),
    .gmem_ext_we    (gmem_ext_we),
    .gmem_ext_addr  (gmem_ext_addr),
    .gmem_ext_wdata (gmem_ext_wdata),
    .gmem_ext_rdata (gmem_ext_rdata)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task write_imem(input [PC_WIDTH-1:0] addr, input [INSTR_WIDTH-1:0] data);
    @(posedge clk);
    imem_we    <= 1'b1;
    imem_waddr <= addr;
    imem_wdata <= data;
    @(posedge clk);
    imem_we <= 1'b0;
  endtask

  task write_gmem(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
    @(posedge clk);
    gmem_ext_we    <= 1'b1;
    gmem_ext_addr  <= addr;
    gmem_ext_wdata <= data;
    @(posedge clk);
    gmem_ext_we <= 1'b0;
  endtask

  task read_gmem(input [ADDR_WIDTH-1:0] addr, output [DATA_WIDTH-1:0] data);
    @(posedge clk);
    gmem_ext_addr <= addr;
    gmem_ext_re   <= 1'b1;
    gmem_ext_we   <= 1'b0;
    @(posedge clk);
    @(posedge clk);
    data = gmem_ext_rdata;
    gmem_ext_re <= 1'b0;
  endtask

  function [INSTR_WIDTH-1:0] encode_r(
    input [3:0] op, input [3:0] rd, input [3:0] rs1, input [3:0] rs2
  );
    encode_r = {op, rd, rs1, rs2};
  endfunction

  function [INSTR_WIDTH-1:0] encode_li(
    input [3:0] rd, input [7:0] imm
  );
    encode_li = {OP_LI, rd, imm};
  endfunction

  function [INSTR_WIDTH-1:0] encode_spc(
    input [3:0] sub, input [3:0] arg1, input [3:0] arg2
  );
    encode_spc = {OP_SPC, sub, arg1, arg2};
  endfunction

  reg [DATA_WIDTH-1:0] read_val;
  integer test_pass;
  integer test_fail;

  initial begin
    $dumpfile("gpu_test.vcd");
    $dumpvars(0, tb_gpu_top);

    rst_n          = 0;
    start          = 0;
    imem_we        = 0;
    imem_waddr     = 0;
    imem_wdata     = 0;
    gmem_ext_re    = 0;
    gmem_ext_we    = 0;
    gmem_ext_addr  = 0;
    gmem_ext_wdata = 0;
    test_pass      = 0;
    test_fail      = 0;

    repeat (5) @(posedge clk);

    $display("=== Test 1: LI + ADD + STR ===");
    write_imem(0, encode_li(4'd1, 8'd10));
    write_imem(1, encode_li(4'd2, 8'd20));
    write_imem(2, encode_r(OP_ADD, 4'd3, 4'd1, 4'd2));
    write_imem(3, encode_li(4'd4, 8'd0));
    write_imem(4, {OP_STR, 4'd3, 4'd4, 4'd0});
    write_imem(5, encode_spc(SPC_HALT, 4'd0, 4'd0));

    rst_n = 1;
    repeat (2) @(posedge clk);

    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    repeat (50) @(posedge clk);

    read_gmem(16'd0, read_val);
    if (read_val == 32'd30) begin
      $display("  PASS: gmem[0] = %0d (expected 30)", read_val);
      test_pass = test_pass + 1;
    end else begin
      $display("  FAIL: gmem[0] = %0d (expected 30)", read_val);
      test_fail = test_fail + 1;
    end

    $display("=== Test 2: SUB ===");
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    write_imem(0, encode_li(4'd1, 8'd50));
    write_imem(1, encode_li(4'd2, 8'd15));
    write_imem(2, encode_r(OP_SUB, 4'd3, 4'd1, 4'd2));
    write_imem(3, encode_li(4'd4, 8'd1));
    write_imem(4, {OP_STR, 4'd3, 4'd4, 4'd0});
    write_imem(5, encode_spc(SPC_HALT, 4'd0, 4'd0));

    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    repeat (50) @(posedge clk);

    read_gmem(16'd1, read_val);
    if (read_val == 32'd35) begin
      $display("  PASS: gmem[1] = %0d (expected 35)", read_val);
      test_pass = test_pass + 1;
    end else begin
      $display("  FAIL: gmem[1] = %0d (expected 35)", read_val);
      test_fail = test_fail + 1;
    end

    $display("=== Test 3: TID ===");
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    write_imem(0, encode_spc(SPC_TID, 4'd1, 4'd0));
    write_imem(1, {OP_STR, 4'd1, 4'd0, 4'd0});
    write_imem(2, encode_spc(SPC_HALT, 4'd0, 4'd0));

    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    repeat (50) @(posedge clk);

    read_gmem(16'd0, read_val);
    $display("  Core 0 TID stored: %0d", read_val);
    if (read_val < NUM_CORES) begin
      $display("  PASS: valid thread ID");
      test_pass = test_pass + 1;
    end else begin
      $display("  FAIL: invalid thread ID %0d", read_val);
      test_fail = test_fail + 1;
    end

    $display("=== Test 4: MUL ===");
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    write_imem(0, encode_li(4'd1, 8'd7));
    write_imem(1, encode_li(4'd2, 8'd6));
    write_imem(2, encode_r(OP_MUL, 4'd3, 4'd1, 4'd2));
    write_imem(3, encode_li(4'd4, 8'd2));
    write_imem(4, {OP_STR, 4'd3, 4'd4, 4'd0});
    write_imem(5, encode_spc(SPC_HALT, 4'd0, 4'd0));

    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    repeat (50) @(posedge clk);

    read_gmem(16'd2, read_val);
    if (read_val == 32'd42) begin
      $display("  PASS: gmem[2] = %0d (expected 42)", read_val);
      test_pass = test_pass + 1;
    end else begin
      $display("  FAIL: gmem[2] = %0d (expected 42)", read_val);
      test_fail = test_fail + 1;
    end

    $display("");
    $display("=== Results: %0d passed, %0d failed ===", test_pass, test_fail);
    $finish;
  end

  initial begin
    #100000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
