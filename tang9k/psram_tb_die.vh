// Included by the whole-board testbenches under RAM_PSRAM: the PSRAM model on
// the core's psram_* pins.  PSRAM_2X_PCT = % of accesses that hit a refresh
// (2x latency; 100 = every one, the worst case), PSRAM_TDQ = the chip's
// output delay in ns (default: random 2-5.5 per access).
`ifndef PSRAM_2X_PCT
`define PSRAM_2X_PCT 20
`endif
`ifdef PSRAM_TDQ
  localparam real PS_TMIN = `PSRAM_TDQ, PS_TMAX = `PSRAM_TDQ;
`else
  localparam real PS_TMIN = 2.0, PS_TMAX = 5.5;
`endif
  psram_model #(.WORDS(1 << 15), .TDQSCK_MIN(PS_TMIN), .TDQSCK_MAX(PS_TMAX),
                .REFRESH_PCT(`PSRAM_2X_PCT))
      psram_die (.ck(psram_ck), .cs_n(psram_cs_n), .reset_n(psram_reset_n),
                 .rwds(psram_rwds), .dq(psram_dq));
