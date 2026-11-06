// Simulation stand-ins for Gowin's ODDR and IDDR, with the same timing as
// the vendor models in gowin_1.9.11/IDE/simlib/gw1n/prim_sim.v (which also
// need Gowin's global-reset module, GSR) -- written out here so the
// testbenches compile on their own.
//
// ODDR: D0/D1 taken on a rising edge appear on Q0 two cycles later, D0 for
//       the high half of the clock, D1 for the low half.  TX (1 = output
//       off) appears on Q1 with the same delay, for a whole cycle.
// IDDR: D sampled on the rising edge (Q0) and on the following falling edge
//       (Q1); both presented together on the next rising edge.
`timescale 1ns / 1ps
module ODDR #(parameter TXCLK_POL = 1'b0, parameter INIT = 1'b0)
             (output wire Q0, output wire Q1, input wire D0, D1, TX, CLK);
  reg d0_0 = INIT, d0_1 = INIT, d0_2 = INIT, d1_0 = INIT, d1_1 = INIT, d1_2 = INIT;
  reg t0 = INIT, t1 = INIT, dt0 = INIT, dt1 = INIT;   // as GSR leaves them
  always @(posedge CLK) begin
    d0_0 <= D0; d1_0 <= D1; d0_1 <= d0_0; d1_1 <= d1_0;
    t0 <= TX; t1 <= t0; d1_2 <= d1_1; dt0 <= dt1;
  end
  always @(negedge CLK) begin d0_2 <= d0_1; dt1 <= t1; end
  assign Q0 = CLK ? d0_2 : d1_2;
  assign Q1 = (TXCLK_POL == 1'b0) ? dt0 : dt1;
endmodule

module IDDR #(parameter Q0_INIT = 1'b0, parameter Q1_INIT = 1'b0)
             (output reg Q0 = 0, output reg Q1 = 0, input wire D, CLK);
  reg q0_o = 0, q1_o = 0;
  always @(posedge CLK) begin q0_o <= D; Q0 <= q0_o; Q1 <= q1_o; end
  always @(negedge CLK) q1_o <= D;
endmodule
