// -----------------------------------------------------------------------------
// 27 MHz -> 135 MHz for the TMDS serialisers.
//
// OSER10 shifts 10 bits out per pixel clock using both edges of FCLK, so
// FCLK = 5 x pixel clock = 5 x 27 = 135 MHz.
//
//   CLKOUT = CLKIN * (FBDIV_SEL+1) / (IDIV_SEL+1) = 27 * 5 / 1 = 135 MHz
//   VCO    = CLKOUT * ODIV_SEL                    = 135 * 8     = 1080 MHz
//
// The GW1N-9 VCO must stay within 400..1200 MHz, so 1080 is in range.  I
// briefly lowered this to 540 suspecting GW2A-18 would not lock at 1080; that
// was wrong -- the 20K's dark LEDs were a reset-polarity problem, and the PLL
// locks at either value.  Kept at 8 to match the configuration proven on the 9K.
// Modelled on apicula's examples/DVI/pll480.v.
// -----------------------------------------------------------------------------
`default_nettype none

module pll_135 (
    input  wire clkin,      // 27 MHz
    output wire clkout,     // 135 MHz
    output wire lock);

  wire gnd = 1'b0;
  wire clkoutp_o, clkoutd_o, clkoutd3_o;

  rPLL rpll_inst (
      .CLKOUT   (clkout),
      .LOCK     (lock),
      .CLKOUTP  (clkoutp_o),
      .CLKOUTD  (clkoutd_o),
      .CLKOUTD3 (clkoutd3_o),
      .RESET    (gnd),
      .RESET_P  (gnd),
      .CLKIN    (clkin),
      .CLKFB    (gnd),
      .FBDSEL   ({gnd,gnd,gnd,gnd,gnd,gnd}),
      .IDSEL    ({gnd,gnd,gnd,gnd,gnd,gnd}),
      .ODSEL    ({gnd,gnd,gnd,gnd,gnd,gnd}),
      .PSDA     ({gnd,gnd,gnd,gnd}),
      .DUTYDA   ({gnd,gnd,gnd,gnd}),
      .FDLY     ({gnd,gnd,gnd,gnd}));

  defparam rpll_inst.FCLKIN = "27";
  defparam rpll_inst.DYN_IDIV_SEL = "false";
  defparam rpll_inst.IDIV_SEL = 0;          // divide by 1
  defparam rpll_inst.DYN_FBDIV_SEL = "false";
  defparam rpll_inst.FBDIV_SEL = 4;         // multiply by 5
  defparam rpll_inst.DYN_ODIV_SEL = "false";
  defparam rpll_inst.ODIV_SEL = 8;   // VCO 1080 MHz, as proven on the 9K
  defparam rpll_inst.PSDA_SEL = "0000";
  defparam rpll_inst.DYN_DA_EN = "true";
  defparam rpll_inst.DUTYDA_SEL = "1000";
  defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
  defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
  defparam rpll_inst.CLKOUT_DLY_STEP = 0;
  defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
  defparam rpll_inst.CLKFB_SEL = "internal";
  defparam rpll_inst.CLKOUT_BYPASS = "false";
  defparam rpll_inst.CLKOUTP_BYPASS = "false";
  defparam rpll_inst.CLKOUTD_BYPASS = "false";
  defparam rpll_inst.DYN_SDIV_SEL = 2;
  defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
  defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
`ifdef GW2A
  defparam rpll_inst.DEVICE = "GW2AR-18C";   // Tang Nano 20K, Gowin toolchain
`else
  defparam rpll_inst.DEVICE = "GW1NR-9C";
`endif
endmodule
`default_nettype wire
