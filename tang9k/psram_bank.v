// -----------------------------------------------------------------------------
// The upper 32 KB (sockets D23-D30) stored in the Tang Nano 9K's PSRAM.
//
// On the board this bank is eight КР565РУ5 chips, one per data bit, sharing
// /RAS5, /CAS5, /WR5 and the multiplexed address MA0-MA7.  The FPGA has no
// block RAM left for them (48 blocks against 26), so their cells move to the
// PSRAM and this module is their common "brains": it watches the same pins
// the chips do, decodes them exactly as fpga_memory.v's dram_x1 does --
// row on /RAS falling, column on /CAS falling, read or (late) write -- and
// turns each access into one PSRAM transaction.  The eight sockets stay in
// the netlist as output pins: in RAM_PSRAM mode each drives its own bit
// (LANE) of `q` while `oe` says a read is on the bus.  TTL picture: the
// DRAMs unplugged, and a ribbon cable from their sockets to a memory card.
//
// Address: 7 row bits (A0-A6; MA7 on the row strobe is the RAM-type jumper,
// constant) and 8 column bits (A7-A14), as dram_x1 stores them -- so the
// cell for a CPU address is the same one the 20K's block RAM uses.
//
// Timing.  The CPU takes the data 30 clk_sys ticks after /CAS5 falls (81
// MHz; measured, and fixed: every part of the board counts the same clock).
// The strobe filter takes 2 ticks, and the request goes to the controller
// straight from it, combinationally; a PSRAM read then takes at most 27
// ticks (refresh collision, data from the late s2 sample), so the byte is in
// `q` 29 ticks after /CAS5 -- 1 tick (12 ns) before it is needed.  The board tests print the worst
// case they meet (the simulation block at the end).
// Writes are posted: the PSRAM write runs after the CPU has moved on, and
// is over long before the next access to this bank (>= 70 ticks).
// -----------------------------------------------------------------------------
`default_nettype none

module psram_bank #(parameter integer CLK_HZ = 81_000_000) (
    input  wire       clk,
    input  wire       rst_n,             // power-up reset
    output wire       ready,             // PSRAM initialised: hold the CPU until then
    output wire       err,               // sticky protocol trouble (an LED)
    output wire [4:0] diag,              // its causes, separately (psram_ctrl)
    output wire       dbg_tx,            // PSRAM_DIAG: read-timing counts, serial (psram_diag_uart)
    // the bank's pins, as the eight chips see them
    input  wire       ras_n_pin, cas_n_pin, we_n_pin,
    input  wire [7:0] ma,                // MA7..MA0
    input  wire [7:0] d,                 // data bus D7..D0
    output wire [7:0] q,                 // read data, bit i for the socket on Di
    output wire       oe,                // a read is on the bus
    // PSRAM die 0
    output wire       psram_ck, psram_ck_n, psram_cs_n, psram_reset_n,
    inout  wire       psram_rwds,
    inout  wire [7:0] psram_dq);

  // The reset comes from the PLL's lock, which is not clocked by clk.
  reg [1:0] rst_s = 2'b00;
  always @(posedge clk) rst_s <= {rst_s[0], rst_n};

  // --- the strobes, filtered as dram_x1 does (see "Settling" there) ---------
  reg ras_1 = 1'b1, cas_1 = 1'b1, we_1 = 1'b1, ras_2 = 1'b1, cas_2 = 1'b1, we_2 = 1'b1;
  reg ras_f = 1'b1, cas_f = 1'b1, we_f = 1'b1;
  reg [7:0] a_1 = 8'd0, a_2 = 8'd0, d_1 = 8'd0, d_2 = 8'd0;
  reg [6:0] row = 7'd0;
  reg [7:0] col = 8'd0;
  reg wr_d = 1'b0, rd_valid = 1'b0;
  reg [1:0] hold = 2'd0;
  wire ras_n = (ras_1 == ras_2) ? ras_1 : ras_f;
  wire cas_n = (cas_1 == cas_2) ? cas_1 : cas_f;
  wire we_n  = (we_1  == we_2)  ? we_1  : we_f;
  wire cas_fall = cas_f && !cas_n;
  wire wr_now   = !ras_n && !cas_n && !we_n;
  wire [7:0] col_now = cas_fall ? a_2 : col;

  always @(posedge clk) begin
    {ras_1, cas_1, we_1, a_1, d_1} <= {ras_n_pin, cas_n_pin, we_n_pin, ma, d};
    {ras_2, cas_2, we_2, a_2, d_2} <= {ras_1, cas_1, we_1, a_1, d_1};
    ras_f <= ras_n; cas_f <= cas_n; we_f <= we_n;
    wr_d  <= wr_now;
    if (ras_f && !ras_n) row <= a_2[6:0];
    if (cas_fall) col <= a_2;
    // Output enable as a real chip's: from a read's /CAS fall until /CAS
    // rises, then a short hold (dram_x1 explains why the board needs it).
    if (cas_fall)   rd_valid <= !ras_n && we_n;
    else if (cas_n) rd_valid <= 1'b0;
    if (!cas_n && rd_valid) hold <= 2'd1;
    else if (hold != 2'd0)  hold <= hold - 2'd1;
  end
  assign oe = (!cas_f && rd_valid) || hold != 2'd0;

  // --- requests ---------------------------------------------------------------
  wire rd_req = cas_fall && !ras_n && we_n;
  wire wr_req = wr_now && !wr_d;
  wire [14:0] addr = {col_now, row};       // cell = {row, column}: any fixed map will do

  wire [7:0] rdata;
  wire busy, rd_done;
  wire dg_ev, dg_bad, dg_x2; wire [3:0] dg_first;
  psram_ctrl #(.CLK_HZ(CLK_HZ), .AW(15)) ctrl (
      .clk(clk), .rst_n(rst_s[1]), .ready(ready),
      .rd(rd_req), .wr(wr_req), .rs(1'b0), .addr(addr), .wdata(d_2),
      .rdata(rdata), .rd_done(rd_done), .busy(busy), .err(err), .diag(diag),
      .dg_ev(dg_ev), .dg_first(dg_first), .dg_bad(dg_bad), .dg_x2(dg_x2),
      .psram_ck(psram_ck), .psram_ck_n(psram_ck_n), .psram_cs_n(psram_cs_n),
      .psram_reset_n(psram_reset_n), .psram_rwds(psram_rwds), .psram_dq(psram_dq));
  assign q = rdata;
`ifndef SYNTHESIS
  // Simulation only: the read's deadline.  Ticks from /CAS5 falling at the
  // pin (the filter's 2 ticks plus the transaction) to the byte in `q`; the
  // CPU takes it 30 ticks after /CAS5.  Each new maximum is printed.
  integer t_cas = 0, t_now = 0, worst = 0;
  always @(posedge clk) begin
    t_now = t_now + 1;
    if (rd_req) t_cas = t_now - 2;
    if (rd_done && t_now - t_cas + 1 > worst) begin
      worst = t_now - t_cas + 1;
      $display("psram_bank: read ready %0d ticks after /CAS5 (CPU takes it at 30)", worst);
    end
  end
`endif
`ifdef PSRAM_DIAG
  psram_diag_uart #(.CLK_HZ(CLK_HZ)) diag_uart (.clk(clk), .ev(dg_ev), .first(dg_first),
      .bad(dg_bad), .x2(dg_x2), .tx(dbg_tx));
`else
  assign dbg_tx = 1'b1;
`endif
endmodule
`default_nettype wire
