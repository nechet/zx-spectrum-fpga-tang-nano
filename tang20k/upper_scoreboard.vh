// Upper-RAM scoreboard, included by tb_sdmenu.v under SCOREBOARD.
// A shadow copy of 8000-FFFF: every CPU write is recorded as the CPU puts
// it out, every CPU read (opcode or data) is checked, at the very tick the
// core takes the byte, against the last write to that address.  Addresses
// never written are not checked (their power-up contents are arbitrary).
// TTL picture: a logic analyser with a second, known-good memory on the
// same bus, comparing every byte.
  `define SB_CPU dut.kras.U_D1.core
  reg [7:0] sb_mem [0:32767];
  reg       sb_ok  [0:32767];
  integer   sb_i, sb_rd = 0, sb_wr = 0, sb_bad = 0;
  initial for (sb_i = 0; sb_i < 32768; sb_i = sb_i + 1) sb_ok[sb_i] = 1'b0;
  wire [15:0] sb_a = `SB_CPU.A;
  always @(posedge dut.clk_x5) begin
    if (!`SB_CPU.mreq_n && !`SB_CPU.wr_n && sb_a[15]) begin
      if (!sb_ok[sb_a[14:0]] || sb_mem[sb_a[14:0]] !== `SB_CPU.dout) sb_wr = sb_wr + 1;
      sb_mem[sb_a[14:0]] = `SB_CPU.dout;
      sb_ok[sb_a[14:0]]  = 1'b1;
    end
    if (`SB_CPU.rise && `SB_CPU.tstate[2] && `SB_CPU.wait_q &&
        !`SB_CPU.mreq_n && !`SB_CPU.rd_n && sb_a[15] && sb_ok[sb_a[14:0]]) begin
      sb_rd = sb_rd + 1;
      if (`SB_CPU.di !== sb_mem[sb_a[14:0]]) begin
        sb_bad = sb_bad + 1;
        if (sb_bad <= 20)
          $display("SCOREBOARD BAD read %h: got %h, written %h  (%0s, %0t us)", sb_a,
                   `SB_CPU.di, sb_mem[sb_a[14:0]], `SB_CPU.m1_n ? "data" : "opcode", $time / 1000);
      end
    end
  end
  always begin #100_000_000;
    $display("  scoreboard at %0d ms: %0d upper reads checked, %0d bad, %0d write changes",
             $time / 1_000_000, sb_rd, sb_bad, sb_wr);
  end
