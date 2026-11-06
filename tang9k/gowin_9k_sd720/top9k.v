// Tang Nano 9K top level for the Gowin toolchain: fixes the board-specific
// parameters of ../../core/top.v, as top20k.v does for the 20K.
//   emulated LVDS for HDMI (ELVDS_OBUF: the 9K's HDMI pins have no true
//   LVDS drivers), and both buttons active low (pulled up, pressed = 0).
`default_nettype none
module top9k (
    input  wire       clk,          // 27 MHz, pin 52
    input  wire       rst_s1,       // button S1, pin 3: reset, active low
    input  wire       menu_s2,      // button S2, pin 4: loader menu, active low
    output wire [5:0] led,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n,
    input  wire       ps2_clk,      // PS/2 keyboard CLK, pin 31
    input  wire       ps2_data,     // PS/2 keyboard DATA, pin 32
    output wire       sd_clk,       // microSD, SPI mode: pins 36, 37, 38, 39
    output wire       sd_cmd,
    output wire       sd_dat3,
    input  wire       sd_dat0);

  top #(.WITH_HDMI(1), .TRUE_LVDS(0), .RST_ACTIVE_LOW(1)) core (
      .clk(clk), .rst_i(rst_s1), .led(led),
      .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
      .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n),
      .ps2_clk(ps2_clk), .ps2_data(ps2_data),
      .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat3(sd_dat3), .sd_dat0(sd_dat0),
      .nmi_btn(~menu_s2));          // top.v wants the menu button active high
endmodule
`default_nettype wire
