// -----------------------------------------------------------------------------
// PSRAM hardware tester for the Tang Nano 9K: psram_ctrl alone on the real
// die, no Spectrum.  Build: gowin_psram_test/ (PSRAM_TRACE defined).
//
// First the die's ID0 and CR0 registers are read, then endless passes: write
// all 32K bytes with a pattern that changes every pass, read them all back,
// count mismatches.  Once a second the serial port (pin 17, 115200 8N1; on a
// PC the board's second USB serial port) gets one line:
//
//   P<pass> R<reads> E<errors> X<2x reads> i<ID0 high byte> c<CR0 high byte>
//   N| 32 x ttttt  X| 32 x ttttt  I| 32 x ttttt  C| 32 x ttttt
//
// the counts since power-up (ID0 reads 00 5F, CR0 8F E7 on the GW1NR-9's die),
// then four raw traces, tick by tick from CS# low: the latest 1x read (N), the
// latest 2x read (X), the ID0 read (I) and the CR0 read (C).  Each tick is 5
// hex digits: {rwds_r, rwds_f, dq_r, dq_f} as the controller sees them, IN_DLY
// ticks after the pins (PSRAM_TRACE keeps CK running past the data, so the
// trace shows where the die really put it).  LEDs: 0 any error, 1 any 2x
// read, 5 heartbeat.  TTL picture: a memory board on a test jig with a logic
// analyser, before it goes into the machine.
// -----------------------------------------------------------------------------
`default_nettype none

module psram_hwtest #(parameter integer PRINT_TICKS = 81_000_000) (
    input  wire        clk,                // 27 MHz
    output wire        uart_tx,
    output wire [5:0]  led,
    output wire [1:0]  O_psram_ck,
    output wire [1:0]  O_psram_ck_n,
    output wire [1:0]  O_psram_cs_n,
    output wire [1:0]  O_psram_reset_n,
    inout  wire [1:0]  IO_psram_rwds,
    inout  wire [15:0] IO_psram_dq);

  localparam integer CLK_HZ = 81_000_000;

  // --- 81 MHz = 27 x 3 (VCO 648 MHz) ----------------------------------------
  wire clk81, lock;
  wire gnd = 1'b0;
`ifdef SIM
  assign clk81 = clk; assign lock = 1'b1;   // the testbench drives 81 MHz itself
`else
  rPLL pll (
      .CLKOUT(clk81), .LOCK(lock), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
      .RESET(gnd), .RESET_P(gnd), .CLKIN(clk), .CLKFB(gnd),
      .FBDSEL({6{gnd}}), .IDSEL({6{gnd}}), .ODSEL({6{gnd}}),
      .PSDA({4{gnd}}), .DUTYDA({4{gnd}}), .FDLY({4{gnd}}));
  defparam pll.FCLKIN = "27";
  defparam pll.DYN_IDIV_SEL = "false";  defparam pll.IDIV_SEL = 0;
  defparam pll.DYN_FBDIV_SEL = "false"; defparam pll.FBDIV_SEL = 2;
  defparam pll.DYN_ODIV_SEL = "false";  defparam pll.ODIV_SEL = 8;
  defparam pll.PSDA_SEL = "0000";       defparam pll.DYN_DA_EN = "true";
  defparam pll.DUTYDA_SEL = "1000";
  defparam pll.CLKOUT_FT_DIR = 1'b1;    defparam pll.CLKOUTP_FT_DIR = 1'b1;
  defparam pll.CLKOUT_DLY_STEP = 0;     defparam pll.CLKOUTP_DLY_STEP = 0;
  defparam pll.CLKFB_SEL = "internal";
  defparam pll.CLKOUT_BYPASS = "false"; defparam pll.CLKOUTP_BYPASS = "false";
  defparam pll.CLKOUTD_BYPASS = "false";
  defparam pll.DYN_SDIV_SEL = 2;
  defparam pll.CLKOUTD_SRC = "CLKOUT";  defparam pll.CLKOUTD3_SRC = "CLKOUT";
  defparam pll.DEVICE = "GW1NR-9C";
`endif

  reg [1:0] rst_s = 2'b00;
  always @(posedge clk81) rst_s <= {rst_s[0], lock};

  // --- the controller ----------------------------------------------------------
`ifndef PSRAM_DOFS
`define PSRAM_DOFS 3
`endif
  reg         rd = 1'b0, wr = 1'b0, rs = 1'b0;
  reg  [14:0] addr = 15'd0;
  reg  [7:0]  wdata = 8'h00;
  wire [7:0]  rdata;
  wire        ready, busy, rd_done, err;
  wire [17:0] tr_smp; wire [4:0] tr_n; wire tr_rd, tr_x2;
  psram_ctrl #(.CLK_HZ(CLK_HZ), .AW(15), .DOFS(`PSRAM_DOFS)) ctrl (
      .clk(clk81), .rst_n(rst_s[1]), .ready(ready),
      .rd(rd), .wr(wr), .rs(rs), .addr(addr), .wdata(wdata),
      .rdata(rdata), .rd_done(rd_done), .busy(busy), .err(err), .diag(),
      .dg_ev(), .dg_first(), .dg_bad(), .dg_x2(),
      .tr_smp(tr_smp), .tr_n(tr_n), .tr_rd(tr_rd), .tr_x2(tr_x2),
      .psram_ck(O_psram_ck[0]), .psram_ck_n(O_psram_ck_n[0]), .psram_cs_n(O_psram_cs_n[0]),
      .psram_reset_n(O_psram_reset_n[0]), .psram_rwds(IO_psram_rwds[0]), .psram_dq(IO_psram_dq[7:0]));
  assign O_psram_ck[1] = 1'b0;  assign O_psram_ck_n[1] = 1'b1;
  assign O_psram_cs_n[1] = 1'b1; assign O_psram_reset_n[1] = 1'b1;
  assign IO_psram_rwds[1] = 1'bz; assign IO_psram_dq[15:8] = 8'bz;

  // --- the test ----------------------------------------------------------------
  // First two register reads (ID0, then CR0: word addresses 0 and 0x800 -- CA16
  // is our addr[3], so CR0's A11 is addr[11]), then endless write/read passes over the 32K bytes.
  reg  [15:0] pass = 16'd0;
  reg  [1:0]  step = 2'd0;               // 0 ID0, 1 CR0, 2 testing
  reg         phase_rd = 1'b0, waiting = 1'b0;
  function [7:0] pattern(input [14:0] a, input [15:0] p);
    pattern = (a[7:0] * 8'd37) ^ {a[14:8], 1'b1} ^ p[7:0] ^ {p[15:8], 1'b0};
  endfunction
  reg  [23:0] n_rd = 24'd0, n_err = 24'd0, n_x2 = 24'd0;
  reg  [7:0]  exp_b = 8'h00, id0_b = 8'h00, cr0_b = 8'h00;
  reg         printing = 1'b0, cur_x2 = 1'b0;

  always @(posedge clk81) begin
    rd <= 1'b0; wr <= 1'b0;
    if (tr_rd) cur_x2 <= tr_x2;
    if (ready) begin
      if (!waiting && !busy && !rd && !wr) begin
        if (step != 2'd2) begin
          rd <= 1'b1; rs <= 1'b1; addr <= (step == 2'd0) ? 15'h0000 : 15'h0800; waiting <= 1'b1;
        end else if (!phase_rd) begin
          rs <= 1'b0; wr <= 1'b1; wdata <= pattern(addr, pass); waiting <= 1'b1;
        end else begin
          rs <= 1'b0; rd <= 1'b1; exp_b <= pattern(addr, pass); waiting <= 1'b1;
        end
      end
      if (waiting && !busy && !rd && !wr) begin
        waiting <= 1'b0;
        if (step == 2'd0) begin id0_b <= rdata; step <= 2'd1; end
        else if (step == 2'd1) begin cr0_b <= rdata; step <= 2'd2; addr <= 15'd0; end
        else begin
          addr <= addr + 1'b1;
          if (!phase_rd) begin
            if (addr == 15'h7FFF) phase_rd <= 1'b1;
          end else begin
            n_rd <= n_rd + 1'b1;
            if (cur_x2) n_x2 <= n_x2 + 1'b1;
            if (rdata != exp_b) n_err <= n_err + 1'b1;
            if (addr == 15'h7FFF) begin phase_rd <= 1'b0; pass <= pass + 1'b1; end
          end
        end
      end
    end
  end

  // Traces, written as they come (frozen while a line is printed): one buffer
  // for the latest 1x read, one for the latest 2x read, one each for the ID0
  // and CR0 register reads.
  reg  [17:0] tb_n [0:31], tb_x [0:31], tb_i [0:31], tb_c [0:31];
  integer i;
  initial for (i = 0; i < 32; i = i + 1) begin tb_n[i] = 0; tb_x[i] = 0; tb_i[i] = 0; tb_c[i] = 0; end
  always @(posedge clk81) if (tr_rd && !printing) begin
    if (step == 2'd0) tb_i[tr_n] <= tr_smp;
    else if (step == 2'd1) tb_c[tr_n] <= tr_smp;
    else if (tr_x2) tb_x[tr_n] <= tr_smp;
    else tb_n[tr_n] <= tr_smp;
  end

  // --- the report ----------------------------------------------------------------
  // P R E X counts, i<ID0 hi> c<CR0 hi>, then four traces: N (1x), X (2x),
  // I (ID0), C (CR0), each '|' and 32 words of 5 digits.
  reg  [7:0]  item = 8'd0;
  reg  [2:0]  k = 3'd0, ndig = 3'd0;
  reg  [23:0] word = 24'd0;
  reg  [7:0]  ch = 8'h00;
  reg         send = 1'b0;
  reg  [26:0] tmr = 27'd0;
  wire        idle;
  localparam [7:0] NHEAD = 8'd6, NITEMS = NHEAD + 8'd4 * 8'd33;
  function [7:0] hex(input [3:0] v);
    hex = (v < 4'd10) ? 8'h30 + v : 8'h41 + v - 4'd10;
  endfunction
  reg [7:0] it_ch; reg [23:0] it_val; reg [2:0] it_nd;
  wire [7:0] ti = item - NHEAD;              // item inside the traces
  wire [1:0] tw = ti / 8'd33;                // which trace
  wire [5:0] te = ti % 8'd33;                // 0 = its '|', 1..32 = its words
  reg  [17:0] tv;
  always @* begin
    case (tw)
      2'd0: tv = tb_n[te[4:0] - 5'd1];
      2'd1: tv = tb_x[te[4:0] - 5'd1];
      2'd2: tv = tb_i[te[4:0] - 5'd1];
      default: tv = tb_c[te[4:0] - 5'd1];
    endcase
    it_ch = 8'h20; it_val = {2'b00, tv, 4'h0}; it_nd = 3'd5;
    case (item)
      8'd0: begin it_ch = "P"; it_val = {pass, 8'h00};  it_nd = 3'd4; end
      8'd1: begin it_ch = "R"; it_val = n_rd;           it_nd = 3'd6; end
      8'd2: begin it_ch = "E"; it_val = n_err;          it_nd = 3'd6; end
      8'd3: begin it_ch = "X"; it_val = n_x2;           it_nd = 3'd6; end
      8'd4: begin it_ch = "i"; it_val = {id0_b, 16'h0}; it_nd = 3'd2; end
      8'd5: begin it_ch = "c"; it_val = {cr0_b, 16'h0}; it_nd = 3'd2; end
      default: if (te == 6'd0) begin
        it_ch = (tw == 2'd0) ? "N" : (tw == 2'd1) ? "X" : (tw == 2'd2) ? "I" : "C";
        it_nd = 3'd0;
      end
    endcase
  end
  always @(posedge clk81) begin
    send <= 1'b0;
    if (!printing) begin
      if (tmr == PRINT_TICKS - 1) begin tmr <= 27'd0; printing <= 1'b1; item <= 8'd0; k <= 3'd0; end
      else tmr <= tmr + 1'b1;
    end else if (idle && !send) begin
      send <= 1'b1;
      if (item == NITEMS) begin
        if (k == 3'd0) begin ch <= 8'h0D; k <= 3'd1; end
        else begin ch <= 8'h0A; printing <= 1'b0; end
      end else if (k == 3'd0) begin
        ch <= it_ch; word <= it_val; ndig <= it_nd;
        if (it_nd == 3'd0) item <= item + 1'b1; else k <= 3'd1;
      end else begin
        ch <= hex(word[23:20]); word <= {word[19:0], 4'h0};
        if (k == ndig) begin k <= 3'd0; item <= item + 1'b1; end else k <= k + 1'b1;
      end
    end
  end
  uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(115_200)) u (.clk(clk81), .data(ch), .send(send), .idle(idle), .tx(uart_tx));

  reg [25:0] beat = 26'd0;
  always @(posedge clk81) beat <= beat + 1'b1;
  assign led = ~{beat[25], 3'b000, n_x2 != 24'd0, n_err != 24'd0};
endmodule
`default_nettype wire
