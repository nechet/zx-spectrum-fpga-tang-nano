// -----------------------------------------------------------------------------
// PSRAM read-timing measurement, for a diagnostic build only (PSRAM_DIAG).
//
// psram_ctrl reports every read: where in a 12-sample window (half a clk_sys
// tick apart, 6.2 ns at 81 MHz) the die's RWDS was first seen high, whether
// the byte taken was wrong-phase (RWDS low at the chosen sample), and whether
// the read had double latency.  This module counts them and prints the counts
// once a second on the board's USB serial port, 115200 8N1, one line:
//
//   reads  errors  2x  h0 h1 ... h11  none     (16 hex words, 6 digits)
//
// h<k>: reads whose RWDS first rose before sample k (sample 4 = s0, 5 = s1,
// 6 = s2 in psram_ctrl's terms); none: never high inside the window.  TTL
// picture: a row of event counters on the bus, read out by a teleprinter.
// Counting pauses while a line is being sent, so each line is consistent.
// -----------------------------------------------------------------------------
`default_nettype none

module psram_diag_uart #(parameter integer CLK_HZ = 81_000_000) (
    input  wire       clk,
    input  wire       ev,          // one tick per read
    input  wire [3:0] first,       // 0..11, 12 = never high
    input  wire       bad,
    input  wire       x2,
    output wire       tx);

  reg [23:0] cnt [0:15];          // 24 bits: 16.7 million, ample for a second
  integer i;
  initial for (i = 0; i < 16; i = i + 1) cnt[i] = 24'd0;

  reg        printing = 1'b0;
  reg [4:0]  item = 5'd0;
  reg [3:0]  k = 4'd0;
  reg [23:0] word = 24'd0;
  reg [7:0]  ch = 8'h00;
  reg        send = 1'b0;
  reg [$clog2(CLK_HZ)-1:0] tmr = 0;
  wire       idle;

  // One enable per counter, registered, so each counter is a plain +1:
  // no multiplexer in front of the adders.
  reg [15:0] inc = 16'd0;
  always @(posedge clk) begin
    inc <= 16'd0;
    if (ev && !printing) begin
      inc[0] <= 1'b1;
      inc[1] <= bad;
      inc[2] <= x2;
      inc[5'd3 + first] <= 1'b1;
    end
  end
  genvar g;
  generate for (g = 0; g < 16; g = g + 1) begin : c
    always @(posedge clk) if (inc[g]) cnt[g] <= cnt[g] + 1'b1;
  end endgenerate

  function [7:0] hex(input [3:0] v);
    hex = (v < 4'd10) ? 8'h30 + v : 8'h41 + v - 4'd10;
  endfunction

  always @(posedge clk) begin
    send <= 1'b0;
    if (!printing) begin
      if (tmr == CLK_HZ - 1) begin tmr <= 0; printing <= 1'b1; item <= 5'd0; k <= 4'd0; end
      else tmr <= tmr + 1'b1;
    end else if (idle && !send) begin
      send <= 1'b1;
      if (item == 5'd16) begin
        if (k == 4'd0) begin ch <= 8'h0D; k <= 4'd1; end
        else begin ch <= 8'h0A; printing <= 1'b0; end
      end else if (k == 4'd0) begin
        ch <= 8'h20; word <= cnt[item[3:0]]; k <= 4'd1;
      end else begin
        ch <= hex(word[23:20]); word <= {word[19:0], 4'h0};
        if (k == 4'd6) begin k <= 4'd0; item <= item + 1'b1; end else k <= k + 1'b1;
      end
    end
  end

  uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(115_200)) u (.clk(clk), .data(ch), .send(send), .idle(idle), .tx(tx));
endmodule
`default_nettype wire
