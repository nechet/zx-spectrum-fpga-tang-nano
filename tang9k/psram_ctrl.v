// -----------------------------------------------------------------------------
// Byte-wide controller for the Tang Nano 9K's embedded PSRAM (HyperRAM, one
// die, x8), on the board's own clock -- no second PLL, no clock crossing.
//
// The memory clock CK is clk / 2 (40.5 MHz from 81).  Every pin goes through
// one of the I/O cell's DDR registers (ODDR out, IDDR in), clocked by clk,
// which can change a pin on both edges of clk -- half a clk tick apart.  That
// is what makes the half-speed CK work without a phase-shifted clock:
//
//      clk     _|‾‾‾|___|‾‾‾|___|‾‾‾|___|‾‾‾|___
//      CK      _____|‾‾‾‾‾‾‾|_______|‾‾‾‾‾‾‾|___     edges in the MIDDLE of a clk tick
//      DQ out  X  b0   X  b1   X  b2   X  b3   X    changes at clk's rising edge
//
// CK's edges sit half a clk tick (6.2 ns) away from every change on DQ, CS#
// and RWDS: the chip sees a quarter CK period of setup and of hold, which is
// what the 90-degree clock of a full-speed design buys, here for free.  (TTL
// picture: clock the address latches on one edge of a clock and the RAM's
// strobe on the other, so the strobe always lands in the middle of a steady
// address.)
//
// Reads come back edge-aligned: the chip changes DQ and RWDS together, a
// delay `a` after each CK edge -- its own tDQSCK (2-5.5 ns) plus the path
// out to the die and back, which no simulation knows.  The upper byte is
// valid from a to a + 12.3 ns after CK rises.  The IDDRs sample every 6.2 ns
// (both edges of clk), so three samples fall near that window:
//
//      CK rise      +6.2        +12.3 (CK fall)    +18.5
//         |          s0            s1                s2
//
// s1 is good for a < ~6 ns, s2 for a > ~6 ns.  RWDS says which: it rises
// with the upper byte, so RWDS already high at s0 means the data came early
// (take s1); still low, late (take s2).  Either way the sample taken is at
// least a quarter CK period inside the byte, for any a from 0 to ~17 ns --
// and the choice is made afresh on every read, so it follows temperature.
// (TTL: a scope check of which clock phase lands mid-data, done by the
// hardware on each cycle.)
//
// One byte per transaction: the byte lives in the upper half of word `addr`
// (the lower half is masked on writes and ignored on reads).  Wasteful of the
// 4 MB, which this machine does not need, and it makes every access the same
// one-word transaction.
//
// Latency (W955D8MBYA): L = 3 clocks, programmed into CR0 after power-up;
// variable, so the chip asks for 2L when an internal refresh collides, by
// driving RWDS high during the command.  Data starts on CK cycle 3 + L or
// 3 + 2L, counting the first command cycle as 1 (DOFS = 3).  Measured on the
// board (psram_hwtest.v, 2026-11-04): RWDS rose on cycle 6 for 1x and 9 for
// 2x, and CR0 read back as written.  The first version assumed 2 + L, as did
// its simulation model, so every simulation passed and every board access
// was a cycle early: reads took a stale byte, writes ended before the die
// took the data.
// -----------------------------------------------------------------------------
`default_nettype none

module psram_ctrl #(
    parameter integer CLK_HZ = 81_000_000,
    parameter integer L      = 3,            // initial latency, CK cycles
    parameter integer AW     = 15,           // byte address width used
    parameter integer DOFS   = 3             // data on CK cycle DOFS + L (1x) / DOFS + 2L (2x)
) (
    input  wire          clk,
    input  wire          rst_n,              // power-up reset: starts the 150 us wait
    output reg           ready = 1'b0,       // initialised; accesses accepted from now
    input  wire          rd,                 // one-tick request pulses, taken when !busy
    input  wire          wr,
    input  wire          rs,                 // register space (CA46): the tester's CR0/ID reads; 0 otherwise
    input  wire [AW-1:0] addr,
    input  wire [7:0]    wdata,
    output reg  [7:0]    rdata = 8'hFF,      // the last byte read
    output reg           rd_done = 1'b0,     // one tick: rdata just updated
    output wire          busy,
    output reg           err = 1'b0,         // sticky: a request while busy, or RWDS not
                                             // high at the read sample
    output reg  [4:0]    diag = 5'd0,        // sticky, for LEDs: {2x seen, s2 used,
                                             // s1 used, RWDS wrong, request while busy}
    // per-read timing report for psram_diag_uart (PSRAM_DIAG builds only)
    output reg           dg_ev = 1'b0,
    output reg  [3:0]    dg_first = 4'd0,
    output reg           dg_bad = 1'b0,
    output reg           dg_x2 = 1'b0,
    // raw pin samples, for the hardware tester (psram_hwtest.v); unconnected
    // elsewhere, and then removed by synthesis
    output wire [17:0]   tr_smp,             // {rwds_r, rwds_f, dq_r, dq_f}
    output wire [4:0]    tr_n,               // tick in the transaction
    output wire          tr_rd,              // a read is running
    output wire          tr_x2,              // this read took the 2x latency
    // the die's pins (Gowin's magic port names live in the top level)
    output wire          psram_ck,
    output wire          psram_ck_n,
    output wire          psram_cs_n,
    output wire          psram_reset_n,
    inout  wire          psram_rwds,
    inout  wire [7:0]    psram_dq
);
  // --- what each pin should do this tick (the DDR cells add a fixed delay) --
  reg       cs_n = 1'b1;
  reg [1:0] ck2  = 2'b00;          // CK during the {first, second} half of the tick
  reg [7:0] dq_o = 8'h00;
  reg       dq_oe = 1'b0;
  reg       rwds_o = 1'b0, rwds_oe = 1'b0;

  // --- inputs, as sampled at the CK-edge instants (clk falling) -------------
  wire       rwds_r, rwds_f;
  wire [7:0] dq_r, dq_f;

  // --- sequencer ------------------------------------------------------------
  // One transaction = ticks n = 0, 1, 2, ...  Tick 0: CS# low, CK still low.
  // CK cycle c (1-based) spans ticks 2c-1 (CK rises in its middle) and 2c
  // (CK falls in its middle).  Command bytes: ticks 1..6.
  localparam S_POWERUP = 3'd0, S_CFG = 3'd1, S_IDLE = 3'd2, S_RD = 3'd3, S_WR = 3'd4;
  reg [2:0]  st = S_POWERUP;
  reg [4:0]  n = 5'd0;
  reg [47:0] ca = 48'd0;
  reg [7:0]  wbyte = 8'h00;
  reg        two_x = 1'b0;
  localparam integer INIT_TICKS = CLK_HZ / 1000 * 160 / 1000;   // 160 us > tVCS
  reg [$clog2(INIT_TICKS+1)-1:0] init_cnt = 0;

  // Data cycle and its two ticks.
  wire [4:0] dcyc = two_x ? DOFS + 5'd2 * L : DOFS + L;
  wire [4:0] t_hi = 5'd2 * dcyc - 5'd1;      // tick whose middle has the CK rise
  wire [4:0] t_lo = 5'd2 * dcyc;             // ... and the CK fall
  // Pipeline: a pin value set at tick n is on the pin during tick n + OUT_DLY;
  // the clk-falling sample in the middle of pin tick p is seen here at p + IN_DLY.
  localparam integer OUT_DLY = 3, IN_DLY = 2;
  // The RWDS latency request: sampled in the middle of command tick 2.
  localparam [4:0] T_LAT = 5'd2 + OUT_DLY + IN_DLY;
  // The read samples s0, s1 (start and middle of pin tick t_lo) are seen at
  // t_cap; s2 (start of pin tick t_lo + 1) one tick later.
  wire [4:0] t_cap = t_lo + OUT_DLY + IN_DLY;
  reg        early = 1'b0;               // RWDS already high at s0
  reg  [7:0] dq_s1 = 8'h00;
  reg        rwds_s1 = 1'b0;
`ifdef PSRAM_DIAG
  // Measurement: RWDS sampled at every half tick from 2 ticks before t_cap to
  // 3 after -- 12 samples, s0 is number 4 -- and CS# held two ticks longer so
  // the die keeps driving through the whole window (the linear burst goes on).
  // The byte taken and its moment are unchanged.
`ifdef PSRAM_DIAG_SHORT
  // ...or, the read's own timing unchanged: the window ends at t_cap + 1
  // (8 samples; the last four counted as low).
  localparam [4:0] RD_CS_END = 5'd2, RD_END = 5'd1, DG_END = 5'd1;
`else
  localparam [4:0] RD_CS_END = 5'd4, RD_END = 5'd3, DG_END = 5'd3;
`endif
  reg [11:0] dg_pat = 12'd0;
  reg        dg_pend = 1'b0;
  function [3:0] first_one(input [11:0] p);
    integer j;
    begin
      first_one = 4'd12;
      for (j = 0; j < 12; j = j + 1) if (p[11 - j] && first_one == 4'd12) first_one = j;
    end
  endfunction
`else
  localparam [4:0] RD_CS_END = 5'd2, RD_END = 5'd1;
`endif

  assign busy = (st != S_IDLE);

  // How long a read keeps CK running and CS# low, and when it ends.
`ifdef PSRAM_TRACE
  // Tester: CK runs to the end of a 2x read's data and four ticks more, CS#
  // stays low after it, whatever latency was detected -- so a trace shows
  // where the die really puts RWDS and data.  The byte is taken as usual.
  wire [4:0] rd_ck_end = 5'd2 * (DOFS + 5'd2 * L) + 5'd4, rd_cs_hi = rd_ck_end + 5'd2,
             rd_last = rd_ck_end + 5'd5;
`else
  wire [4:0] rd_ck_end = t_lo, rd_cs_hi = t_lo + RD_CS_END, rd_last = t_cap + RD_END;
`endif
  assign tr_smp = {rwds_r, rwds_f, dq_r, dq_f};
  assign tr_n   = n;
  assign tr_rd  = (st == S_RD);
  assign tr_x2  = two_x;

  always @(posedge clk) begin
    rd_done <= 1'b0;
`ifdef PSRAM_DIAG
    dg_ev <= 1'b0;
    if (dg_pend) begin dg_pend <= 1'b0; dg_ev <= 1'b1; dg_first <= first_one(DG_END == 5'd1 ? {dg_pat[7:0], 4'b0000} : dg_pat); end
`endif
    case (st)
      S_POWERUP: begin
        cs_n <= 1'b1; ck2 <= 2'b00; dq_oe <= 1'b0; rwds_oe <= 1'b0;
        if (init_cnt == INIT_TICKS) begin
          // CR0 = 8FE7: normal operation, default drive, latency 3 (code 1110),
          // variable latency, legacy wrapped bursts, 32 bytes.
          ca <= {8'h60, 8'h00, 8'h01, 8'h00, 8'h00, 8'h00};
          n <= 5'd0;
          st <= S_CFG;
        end else init_cnt <= init_cnt + 1'b1;
      end

      S_CFG: begin                           // register write: no latency
        n <= n + 1'b1;
        cs_n  <= (n > 5'd8);
        ck2   <= (n >= 5'd1 && n <= 5'd8) ? (n[0] ? 2'b01 : 2'b10) : 2'b00;
        dq_oe <= (n >= 5'd1 && n <= 5'd8);
        dq_o  <= (n >= 5'd1 && n <= 5'd6) ? ca[47 - 8 * (n - 1) -: 8] :
                 (n == 5'd7) ? 8'h8F : 8'hE7;
        if (n == 5'd12) begin st <= S_IDLE; ready <= 1'b1; end
      end

      S_IDLE: begin
        cs_n <= 1'b1; ck2 <= 2'b00; dq_oe <= 1'b0; rwds_oe <= 1'b0;
        n <= 5'd0;
        if (rd || wr) begin
          // CA: R/W#, memory space, linear burst, word address = addr.
          ca <= {rd, rs, 1'b1, {(29 - (AW - 3)){1'b0}}, addr[AW-1:3], 13'd0, addr[2:0]};
          wbyte <= wdata;
          two_x <= 1'b0;
          st <= rd ? S_RD : S_WR;
        end
      end

      S_RD, S_WR: begin
        n <= n + 1'b1;
        if (n == 5'd0) cs_n <= 1'b0;
        ck2   <= (n >= 5'd1 && n <= (st == S_RD ? rd_ck_end : t_lo)) ? (n[0] ? 2'b01 : 2'b10) : 2'b00;
        // Command: bytes on ticks 1..6.  A write keeps DQ driven to the end;
        // a read lets go after the command.
        dq_oe <= (n >= 5'd1 && n <= 5'd6) || (st == S_WR && n >= 5'd1 && n <= t_lo);
        dq_o  <= (n >= 5'd1 && n <= 5'd6) ? ca[47 - 8 * (n - 1) -: 8] :
                 (n == t_hi) ? wbyte : 8'h00;
        // Write mask on RWDS: 0 (write) with the upper byte, 1 (keep) with the
        // lower.  Driven from the tick before the data, once the chip has let
        // go of RWDS at the end of the command.
        rwds_oe <= (st == S_WR) && n >= t_hi - 5'd1 && n <= t_lo;
        rwds_o  <= (n == t_lo);
        if (n == T_LAT) two_x <= rwds_f;
        // CS# rises half a tick after the last CK edge; on a read one tick
        // later still, so the chip keeps driving until s2 has been taken.
        if (n == (st == S_RD ? rd_cs_hi : t_lo + 5'd1)) cs_n <= 1'b1;
        if (st == S_RD && n == t_cap) begin
          early <= rwds_r; dq_s1 <= dq_f; rwds_s1 <= rwds_f;
        end
        if (st == S_RD && n == t_cap + 5'd1) begin
          rdata <= early ? dq_s1 : dq_r;
          rd_done <= 1'b1;
          if (!(early ? rwds_s1 : rwds_r)) begin err <= 1'b1; diag[1] <= 1'b1; end  // not the upper byte
          if (early) diag[2] <= 1'b1; else diag[3] <= 1'b1;
          if (two_x) diag[4] <= 1'b1;
        end
`ifdef PSRAM_DIAG
        if (st == S_RD && n >= t_cap - 5'd2 && n <= t_cap + DG_END)
          dg_pat <= {dg_pat[9:0], rwds_r, rwds_f};       // r is the earlier of the two
        if (st == S_RD && n == t_cap + 5'd1) begin dg_bad <= !(early ? rwds_s1 : rwds_r); dg_x2 <= two_x; end
        if (st == S_RD && n == t_cap + DG_END) dg_pend <= 1'b1;
`endif
        if (n == (st == S_RD ? rd_last : t_lo + 5'd2)) st <= S_IDLE;
      end
      default: st <= S_IDLE;
    endcase
    if ((rd || wr) && st != S_IDLE && ready) begin err <= 1'b1; diag[0] <= 1'b1; end
    if (!rst_n) begin
      st <= S_POWERUP; init_cnt <= 0; ready <= 1'b0;
      cs_n <= 1'b1; ck2 <= 2'b00; dq_oe <= 1'b0; rwds_oe <= 1'b0;
    end
  end

  // --- the pins: DDR output registers (D0 = first half of the tick) ---------
  wire cs_q, ck_q, ckn_q, rwds_q, rwds_t;
  wire [7:0] dq_q, dq_t;
  ODDR #(.INIT(1'b1)) o_cs (.CLK(clk), .D0(cs_n), .D1(cs_n), .TX(1'b0), .Q0(cs_q), .Q1());  // CS# high from configuration on
  ODDR o_ck  (.CLK(clk), .D0(ck2[1]), .D1(ck2[0]), .TX(1'b0), .Q0(ck_q),  .Q1());
  ODDR o_ckn (.CLK(clk), .D0(~ck2[1]),.D1(~ck2[0]),.TX(1'b0), .Q0(ckn_q), .Q1());
  ODDR o_rwds(.CLK(clk), .D0(rwds_o), .D1(rwds_o), .TX(~rwds_oe), .Q0(rwds_q), .Q1(rwds_t));
  assign psram_cs_n    = cs_q;
  assign psram_ck      = ck_q;
  assign psram_ck_n    = ckn_q;
  assign psram_reset_n = rst_n;
  assign psram_rwds    = rwds_t ? 1'bz : rwds_q;
  IDDR i_rwds(.CLK(clk), .D(psram_rwds), .Q0(rwds_r), .Q1(rwds_f));

  genvar b;
  generate
    for (b = 0; b < 8; b = b + 1) begin : dq
      ODDR o (.CLK(clk), .D0(dq_o[b]), .D1(dq_o[b]), .TX(~dq_oe), .Q0(dq_q[b]), .Q1(dq_t[b]));
      assign psram_dq[b] = dq_t[b] ? 1'bz : dq_q[b];
      IDDR i (.CLK(clk), .D(psram_dq[b]), .Q0(dq_r[b]), .Q1(dq_f[b]));
    end
  endgenerate
endmodule
