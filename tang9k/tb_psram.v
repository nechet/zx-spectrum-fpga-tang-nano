// Unit test of psram_ctrl against psram_model: power-up, CR0, then random
// byte writes and reads over 32K checked against a reference copy.
// +DLY=<ns>   path delay FPGA -> chip and chip -> FPGA, each way (default 0)
// +TMIN= / +TMAX=  are fixed in the model parameters below per run (macros).
`timescale 1ns / 1ps
`ifndef TDQ_MIN
`define TDQ_MIN 2.0
`endif
`ifndef TDQ_MAX
`define TDQ_MAX 5.5
`endif
`ifndef PATH_DLY
`define PATH_DLY 0.0
`endif
module tb_psram;
  reg clk = 0, rst_n = 0;
  always #6.1728 clk = ~clk;                  // 81 MHz
  wire ready, busy, rd_done, err;
  reg rd = 0, wr = 0; reg [14:0] addr = 0; reg [7:0] wdata = 0;
  wire [7:0] rdata;
  wire ck, ck_n, cs_n, rst_m, rwds_h; wire [7:0] dq_h;
  psram_ctrl #(.CLK_HZ(81_000_000)) dut (
      .clk(clk), .rst_n(rst_n), .ready(ready), .rd(rd), .wr(wr), .rs(1'b0), .addr(addr),
      .wdata(wdata), .rdata(rdata), .rd_done(rd_done), .busy(busy), .err(err),
      .psram_ck(ck), .psram_ck_n(ck_n), .psram_cs_n(cs_n), .psram_reset_n(rst_m),
      .psram_rwds(rwds_h), .psram_dq(dq_h));

  // The path between the I/O cells and the die: a delay each way.
  localparam real D = `PATH_DLY;
  wire ck_m, cs_m, rwds_m; wire [7:0] dq_m;
  assign #(D) ck_m = ck;
  assign #(D) cs_m = cs_n;
  genvar i;
  generate for (i = 0; i < 8; i = i + 1) begin : p
    assign #(D) dq_m[i] = dut.dq_t[i] ? 1'bz : dut.dq_q[i];
    assign #(D) dq_h[i] = chip.dq_oe ? dq_m[i] : 1'bz;
  end endgenerate
  assign #(D) rwds_m = dut.rwds_t ? 1'bz : dut.rwds_q;
  assign #(D) rwds_h = chip.rwds_oe ? rwds_m : 1'bz;

  psram_model #(.TDQSCK_MIN(`TDQ_MIN), .TDQSCK_MAX(`TDQ_MAX), .REFRESH_PCT(30))
      chip (.ck(ck_m), .cs_n(cs_m), .reset_n(rst_m), .rwds(rwds_m), .dq(dq_m));

  reg [7:0] ref_mem [0:32767];
  reg [32767:0] known = 0;
  integer k, bad = 0, nr = 0, nw = 0, seed = 7;
  reg [14:0] a; reg [7:0] v;
  reg [14:0] wlist [0:8191]; integer nwl = 0;
  initial begin
    #100 rst_n = 1;
    wait (ready);
    $display("ready at %0t ns", $time);
    for (k = 0; k < 6000; k = k + 1) begin
      a = (k < 200) ? k[14:0] : $random(seed);
      if (k % 2 == 0 && nwl > 0) a = wlist[$unsigned($random(seed)) % nwl];
      if (k % 2 != 0 || !known[a]) begin
        v = $random(seed);
        @(posedge clk) begin wr <= 1; addr <= a; wdata <= v; end
        @(posedge clk) wr <= 0;
        #1;
        if (!known[a] && nwl < 8192) begin wlist[nwl] = a; nwl = nwl + 1; end
        ref_mem[a] = v; known[a] = 1; nw = nw + 1;
      end else begin
        @(posedge clk) begin rd <= 1; addr <= a; end
        @(posedge clk) rd <= 0;
        #1;
        @(posedge rd_done); #1;
        nr = nr + 1;
        if (rdata !== ref_mem[a]) begin
          bad = bad + 1;
          if (bad < 8) $display("  read %h = %h, expected %h at %0t", a, rdata, ref_mem[a], $time);
        end
      end
      wait (!busy);
      repeat (k % 4) @(posedge clk);
    end
    $display("writes %0d reads %0d wrong %0d  err=%b  model errors %0d  2x %0d  (tDQSCK %0.1f-%0.1f ns, path %0.1f ns)",
             nw, nr, bad, err, chip.errors, chip.n2x, `TDQ_MIN, `TDQ_MAX, D);
    if (bad == 0 && !err && chip.errors == 0) $display("PASS"); else $display("FAIL");
    $finish;
  end
  // latency of one read, ticks from request to rd_done
  integer t0, lat_min = 999, lat_max = 0;
  always @(posedge clk) begin
    if (rd) t0 = $time;
    if (rd_done) begin
      if (($time - t0) / 12.3456 < lat_min) lat_min = ($time - t0) / 12.3456;
      if (($time - t0) / 12.3456 > lat_max) lat_max = ($time - t0) / 12.3456;
    end
  end
  initial begin #200_000_000 $display("FAIL timeout"); $finish; end
  final $display("read latency %0d..%0d ticks of 81 MHz", lat_min, lat_max);
endmodule
