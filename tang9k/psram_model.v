// -----------------------------------------------------------------------------
// Simulation model of one die of the Tang Nano 9K's embedded PSRAM
// (GW1NR-9C: 2 x 32 Mbit, each a Winbond W955D8MBYA-like HyperRAM, x8 DQ).
// Behavioural, for the testbenches only -- strict rather than forgiving:
// every protocol rule the controller relies on is checked, and a breach is
// reported with $display("PSRAM ERROR ...") so a test can fail on it.
//
// What it models (HyperBus, as the datasheet describes it):
//
//   * A transaction is CS# low ... CS# high.  The first 3 CK cycles carry
//     the 48-bit command/address CA, one byte on each CK edge, MSB first:
//       CA[47]    1 = read, 0 = write
//       CA[46]    0 = memory, 1 = register space
//       CA[45]    burst type (not checked; reads/writes here are 1 word)
//       CA[44:16] upper word address,  CA[2:0] lower word address
//   * Latency.  Counting CK cycles from 1 at the first CA cycle, data starts
//     on cycle 3 + L ("1x") or 3 + 2L ("2x"), L = initial latency from CR0
//     -- as measured on the Tang Nano 9K's die (psram_hwtest.v), not 2 + L
//     (power-up default 6).  In variable-latency mode the chip asks for 2x
//     when an internal refresh collides, by driving RWDS high during CA;
//     here that happens at random (REFRESH_PCT).  Fixed mode (CR0[3]) is
//     always 2x.  Register writes have no latency: data follows CA directly.
//   * Data, one 16-bit word per CK cycle: [15:8] on the rising edge, [7:0]
//     on the falling.  Writes: RWDS from the host is the byte mask (1 = keep
//     the old byte).  Reads: the chip drives DQ and RWDS edge-aligned, RWDS
//     high with [15:8], low with [7:0], each tDQSCK after the CK edge --
//     randomised per transaction between TDQSCK_MIN and TDQSCK_MAX, which is
//     what makes a controller that samples at a fixed instant fail here.
//     Linear bursts continue to the next word while CS# stays low.
//   * Power-up: no access for 150 us after reset_n rises (tVCS).
//   * tCSM: CS# low at most 4 us (the chip cannot refresh meanwhile).
//   * Setup/hold of DQ, RWDS and CS# around the CK edges that capture them
//     (TSETUP / THOLD; a guard band, not the datasheet's exact figures).
//
// Memory starts filled with a pattern, not zeros, so a read that returns
// "nothing" is not mistaken for a correct read of a zeroed cell.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module psram_model #(
    parameter integer WORDS       = 1 << 16,   // modelled words (the die has 2M)
    parameter real    TDQSCK_MIN  = 2.0,       // ns, read data after CK edge
    parameter real    TDQSCK_MAX  = 5.5,
    parameter real    TSETUP      = 1.0,       // ns, input setup before CK edge
    parameter real    THOLD       = 1.0,       // ns, input hold after CK edge
    parameter integer REFRESH_PCT = 20,        // % of transactions asking for 2x
    parameter integer SEED        = 1
) (
    input  wire       ck,
    input  wire       cs_n,
    input  wire       reset_n,
    inout  wire       rwds,
    inout  wire [7:0] dq
);
  reg [15:0] mem [0:WORDS-1];
  reg [15:0] cr0 = 16'h8F1F;                   // datasheet default: latency 6, fixed 2x
  integer i, seed = SEED, errors = 0;
  initial for (i = 0; i < WORDS; i = i + 1) mem[i] = 16'hA5C3 ^ i[15:0];

  wire [3:0] lat_code = cr0[7:4];
  // A function, not a net: it must be right in the very step CR0 is written.
  function integer lat_of(input [3:0] c);
    lat_of = (c == 4'b1110) ? 3 : (c == 4'b1111) ? 4 : (c == 4'b0000) ? 5 :
             (c == 4'b0001) ? 6 : (c == 4'b0010) ? 7 : 6;
  endfunction
  `define LAT lat_of(cr0[7:4])
  wire fixed = cr0[3];

  // --- power-up -------------------------------------------------------------
  realtime t_reset = 0.0;
  always @(posedge reset_n) t_reset = $realtime;

  // --- drivers ----------------------------------------------------------------
  reg       rwds_oe = 1'b0, rwds_o = 1'b0;
  reg       dq_oe = 1'b0;
  reg [7:0] dq_o = 8'h00;
  assign rwds = rwds_oe ? rwds_o : 1'bz;
  assign dq   = dq_oe   ? dq_o   : 8'bz;

  task error(input [8*72:1] msg);
    begin
      errors = errors + 1;
      if (errors <= 20) $display("PSRAM ERROR at %0t ns: %0s", $realtime, msg);
    end
  endtask

  // --- input timing checks --------------------------------------------------
  // Only the CK edges that capture something are checked: the command edges
  // (DQ), and a write's data edges (DQ and the RWDS mask).  DQ / RWDS must
  // be steady TSETUP before such an edge and THOLD after it, unless the chip
  // itself is driving them.  CS# must fall TSETUP before the first CK rise
  // and rise THOLD after the last CK edge.
  realtime t_ck = -100.0, t_dq = -100.0, t_rwds = -100.0, t_cs = -100.0;
  realtime t_cap_dq = -100.0, t_cap_rwds = -100.0;
  always @(dq) if (!dq_oe) begin
    t_dq = $realtime;
    if ($realtime - t_cap_dq < THOLD) error("DQ changed inside hold after a capturing CK edge");
  end
  always @(rwds) if (!rwds_oe) begin
    t_rwds = $realtime;
    if ($realtime - t_cap_rwds < THOLD) error("RWDS changed inside hold after a capturing CK edge");
  end
  always @(cs_n) begin
    t_cs = $realtime;
    if (cs_n && $realtime - t_ck < THOLD) error("CS# rose inside hold after a CK edge");
  end
  task check_dq;   begin if ($realtime - t_dq < TSETUP) error("DQ not set up before a capturing CK edge");
                         t_cap_dq = $realtime; end endtask
  task check_rwds; begin if ($realtime - t_rwds < TSETUP) error("RWDS not set up before a write data edge");
                         t_cap_rwds = $realtime; end endtask

  // --- the transaction --------------------------------------------------------
  reg [47:0] ca;
  integer    edge_n;                           // CK edges seen in this transaction
  integer    data_cyc;                         // CK cycle (1-based) data starts on
  reg        is_read, is_reg, two_x;
  reg [31:0] waddr;
  realtime   t_cs_fall, tdqsck;
  integer    nreads = 0, nwrites = 0, n2x = 0;

  always @(negedge cs_n) begin
    t_cs_fall = $realtime;
    if (!reset_n) error("CS# low while reset_n is low");
    else if ($realtime - t_reset < 150_000.0) error("access within 150 us of power-up (tVCS)");
    edge_n = 0;
    ca = 48'd0;
    two_x = fixed ? 1'b1 : ($unsigned($random(seed)) % 100 < REFRESH_PCT);
    tdqsck = TDQSCK_MIN + (TDQSCK_MAX - TDQSCK_MIN) * ($unsigned($random(seed)) % 1000) / 999.0;
    // RWDS during CA: the latency request (driven from CS# low).
    rwds_oe <= 1'b1; rwds_o <= two_x;
  end

  always @(posedge cs_n) begin
    rwds_oe <= 1'b0; dq_oe <= 1'b0;
    if ($realtime - t_cs_fall > 4000.0) error("CS# low longer than tCSM (4 us)");
  end

  // CK edges: count them, collect CA, then data.  edge_n 0..5 = CA bytes.
  always @(ck) if (!cs_n) begin : on_edge
    integer cyc;                               // 1-based CK cycle of this edge
    reg rising;
    rising = ck;
    if (edge_n == 0 && !rising) error("first CK edge after CS# low is a falling edge");
    if (edge_n == 0 && $realtime - t_cs < TSETUP) error("CS# fell inside setup before the first CK rise");
    t_ck = $realtime;
    cyc = edge_n / 2 + 1;
    if (edge_n < 6) begin
      check_dq;
      ca = {ca[39:0], dq};
      if (edge_n == 5) begin
        is_read = ca[47];
        is_reg  = ca[46];
        waddr   = {ca[44:16], ca[2:0]};
        data_cyc = is_reg && !is_read ? 4 : (two_x ? 3 + 2 * `LAT : 3 + `LAT);
        if (is_reg && is_read) error("register reads are not modelled");
        if (!is_reg && waddr >= WORDS) error("address beyond the modelled words");
        // RWDS: released after CA on a write (the host takes it over for the
        // mask), driven low until the data on a read.
        if (is_read) rwds_o <= 1'b0;
        else rwds_oe <= 1'b0;
      end
    end else if (cyc >= data_cyc) begin
      if (is_read) begin
        // Drive the byte for the *next* half cycle: [15:8] after a rising
        // edge, [7:0] after the falling one, tDQSCK late.  The first output
        // appears tDQSCK after the rising edge that starts cycle data_cyc.
        if (rising) begin
          dq_oe  <= #(tdqsck) 1'b1;
          dq_o   <= #(tdqsck) mem[waddr][15:8];
          rwds_o <= #(tdqsck) 1'b1;
          nreads = nreads + (cyc == data_cyc);
        end else begin
          dq_o   <= #(tdqsck) mem[waddr][7:0];
          rwds_o <= #(tdqsck) 1'b0;
          waddr = waddr + 1;                    // linear burst
        end
      end else if (is_reg) begin
        check_dq;
        if (rising) cr0[15:8] = dq; else begin cr0[7:0] = dq;
          $display("PSRAM: CR0 = %h at %0t ns (latency %0d, %0s)", cr0, $realtime,
                   `LAT, cr0[3] ? "fixed 2x" : "variable");
        end
      end else begin
        check_dq; check_rwds;
        if (rwds !== 1'b0 && rwds !== 1'b1) error("RWDS mask undriven at a write data edge");
        if (rising) begin if (!rwds) mem[waddr][15:8] = dq; end
        else begin
          if (!rwds) mem[waddr][7:0] = dq;
          nwrites = nwrites + (cyc == data_cyc);
          waddr = waddr + 1;
        end
      end
    end
    if (cyc == data_cyc && rising && two_x && !is_reg) n2x = n2x + 1;
    edge_n = edge_n + 1;
  end

  // A read that keeps CS# low past its data must not see DQ change under a
  // host that is (wrongly) still driving: caught by the setup/hold checks.

  // Peek/poke for testbenches.
  function [7:0] peek_byte(input [31:0] word, input hi);
    peek_byte = hi ? mem[word][15:8] : mem[word][7:0];
  endfunction
`undef LAT
endmodule
