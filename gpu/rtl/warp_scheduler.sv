module warp_scheduler
  import gpu_pkg::*;
(
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 start,
  input  warp_state_t          warp_states [NUM_CORES],
  output logic [1:0]           active_warp,
  output logic                 warp_valid
);

  logic [1:0] current_warp;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      current_warp <= '0;
    else if (start)
      current_warp <= '0;
    else
      current_warp <= current_warp + 2'd1;
  end

  always_comb begin
    warp_valid  = 1'b0;
    active_warp = current_warp;
    for (int i = 0; i < NUM_CORES; i++) begin
      logic [1:0] idx;
      idx = 2'(current_warp + i[1:0]);
      if (!warp_valid && warp_states[idx] == WARP_RUNNING) begin
        active_warp = idx;
        warp_valid  = 1'b1;
      end
    end
  end

endmodule
