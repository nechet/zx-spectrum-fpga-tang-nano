// -----------------------------------------------------------------------------
// The loader key: F12 on the keyboard, or button S2, pulls the Z80's /NMI low
// once -- the Multiface's red button.
//
// The Z80 takes NMI on a falling edge, so one press must give exactly one
// clean pulse: the button is synchronised and debounced (it must read the
// same for 10 ms), F12 is already clean (a held-key level from the keymap),
// and after a pulse both are ignored until released, then for another 0.25 s.
// The pulse is 20 us long, far more than the Z80 needs (it samples /NMI at
// the end of every instruction).
//
// The timers count microseconds, not clocks: a prescaler makes one tick a
// microsecond, as a crystal divider feeds a TTL timer chain, so no counter is
// wider than 18 bits.  A 26-bit clock counter was too deep a carry for the
// Tang Nano 9K at 81 MHz.
// -----------------------------------------------------------------------------
`default_nettype none

module nmi_gen #(
    parameter integer CLK_HZ = 135_000_000
) (
    input  wire clk,
    input  wire f12,            // F12 held (clk domain)
    input  wire btn,            // button, active high, from the pin
    output wire nmi_n
);
  localparam integer PRE   = CLK_HZ / 1_000_000;  // clocks a microsecond
  localparam integer DEB   = 10_000;              // 10 ms, in microseconds
  localparam integer PULSE = 20;                  // 20 us
  localparam integer GUARD = 250_000;             // 0.25 s

  // --- the microsecond tick ------------------------------------------------
  reg [7:0] pre = 8'd0;
  reg       us  = 1'b0;
  always @(posedge clk) begin
    us  <= (pre == PRE - 1);
    pre <= (pre == PRE - 1) ? 8'd0 : pre + 8'd1;
  end

  // --- button: synchronise, then debounce ---------------------------------
  reg [1:0]  bs = 2'b00;
  reg        bstable = 1'b0;
  reg [13:0] bcnt = 14'd0;
  always @(posedge clk) begin
    bs <= {bs[0], btn};
    if (bs[1] == bstable) bcnt <= 14'd0;
    else if (us) begin
      if (bcnt == DEB - 1) begin bstable <= bs[1]; bcnt <= 14'd0; end
      else bcnt <= bcnt + 14'd1;
    end
  end

  // --- one pulse per press --------------------------------------------------
  wire       pressed = bstable | f12;
  reg  [17:0] t = 18'd0;           // pulse, then guard time, in microseconds
  reg        armed = 1'b1;
  reg        pulse = 1'b0;
  // Everything here moves only on the microsecond tick, so its counter has
  // a whole microsecond (PRE clocks) to settle.
  always @(posedge clk) if (us) begin
    if (t != 18'd0) t <= t - 18'd1;
    if (!pressed && t == 18'd0) armed <= 1'b1;
    else if (pressed && armed && t == 18'd0) begin armed <= 1'b0; t <= GUARD + PULSE; end
    pulse <= (t > GUARD);
  end
  assign nmi_n = !pulse;
endmodule
`default_nettype wire
