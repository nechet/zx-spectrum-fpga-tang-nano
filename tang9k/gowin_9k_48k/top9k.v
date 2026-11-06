// Tang Nano 9K top level for the Gowin toolchain, 48K build: as
// ../gowin_9k_sd720/top9k.v, plus the on-package PSRAM for the upper 32 KB.
//   emulated LVDS for HDMI (ELVDS_OBUF: the 9K's HDMI pins have no true
//   LVDS drivers), and both buttons active low (pulled up, pressed = 0).
//
// The PSRAM ports must have exactly these names: Gowin connects ports
// called O_psram_* / IO_psram_* to the two dies inside the package, and they
// need no pin constraints.  [0] is die 0, [1] die 1; DQ[7:0] and DQ[15:8].
// Only die 0 is used; die 1 is parked (CS# high, clock low).
`default_nettype none
module top9k (
    input  wire        clk,          // 27 MHz, pin 52
    input  wire        rst_s1,       // button S1, pin 3: reset, active low
    input  wire        menu_s2,      // button S2, pin 4: loader menu, active low
    output wire [5:0]  led,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_d_p,
    output wire [2:0]  tmds_d_n,
    input  wire        ps2_clk,      // PS/2 keyboard CLK, pin 31
    input  wire        ps2_data,     // PS/2 keyboard DATA, pin 32
    output wire        sd_clk,       // microSD, SPI mode: pins 36, 37, 38, 39
    output wire        sd_cmd,
    output wire        sd_dat3,
    input  wire        sd_dat0,
    output wire        uart_tx,           // pin 17: the USB serial port (PSRAM_DIAG builds)
    output wire [1:0]  O_psram_ck,
    output wire [1:0]  O_psram_ck_n,
    output wire [1:0]  O_psram_cs_n,
    output wire [1:0]  O_psram_reset_n,
    inout  wire [1:0]  IO_psram_rwds,
    inout  wire [15:0] IO_psram_dq);

  top #(.WITH_HDMI(1), .TRUE_LVDS(0), .RST_ACTIVE_LOW(1)) core (
      .clk(clk), .rst_i(rst_s1), .led(led),
      .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
      .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n),
      .ps2_clk(ps2_clk), .ps2_data(ps2_data),
      .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat3(sd_dat3), .sd_dat0(sd_dat0),
      .psram_dbg_tx(uart_tx), .psram_ck(O_psram_ck[0]), .psram_ck_n(O_psram_ck_n[0]),
      .psram_cs_n(O_psram_cs_n[0]), .psram_reset_n(O_psram_reset_n[0]),
      .psram_rwds(IO_psram_rwds[0]), .psram_dq(IO_psram_dq[7:0]),
      .nmi_btn(~menu_s2));          // top.v wants the menu button active high

  assign O_psram_ck[1]      = 1'b0;   // die 1 unused
  assign O_psram_ck_n[1]    = 1'b1;
  assign O_psram_cs_n[1]    = 1'b1;
  assign O_psram_reset_n[1] = 1'b1;
  assign IO_psram_rwds[1]   = 1'bz;
  assign IO_psram_dq[15:8]  = 8'bz;
endmodule
`default_nettype wire
