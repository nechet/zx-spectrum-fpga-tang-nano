// -----------------------------------------------------------------------------
// FPGA-backed replacements for the board's memory chips.
//
// Same pin-level interfaces as Krasnodar-48-fpga/Verilog/lib/memory.v, so the
// generated board netlist is used unmodified -- only the implementations under
// it change.
//
// By default this builds a 16K Spectrum: ROM plus the 16 KB of video RAM, and the upper
// 32 KB left unpopulated.  The reason is the BSRAM budget on a GW1N-9C:
//
//   ROM                       8 blocks
//   video RAM  D42-D49        8 blocks   (16K x 1 each -> exactly one block)
//   upper RAM  D23-D30       32 blocks   (64K x 1 each -> four blocks each)
//                            --
//   16K machine              16 of 26    fits
//   48K machine              48 of 26    does not
//
// An unpopulated DRAM reads as all ones, which is what a real board does with
// an empty socket -- and what the ROM's memory test expects to find when it
// works out how much RAM is fitted.
//
// `define RAM48 (the Tang Nano 20K build) fits the upper 32 KB as well, and
// in only 16 more blocks, not 32: the board uses half of each КР565РУ5.  On
// the row strobe, MA7 comes from the RAM-type jumper (D22, input jp_ru6),
// which top.v ties high, and /CAS5 only falls for A15 = 1 accesses -- so each
// chip sees only 7 row bits (A0..A6) and 8 column bits (A7..A14), 32K x 1.
// The model stores those 32K and ignores row bit 7.
//
// `define RAM_PSRAM (the Tang Nano 9K's 48K build) keeps those 32K in the
// on-package PSRAM instead: ../tang20k/psram_bank.v watches the
// bank's pins, stores the bytes, and hands each read back on psram_q.  The
// eight upper sockets are then only output pins -- each drives bit LANE of
// psram_q (its data line, set by bus_resolve.py --net-index-param) while
// psram_oe says a read is on the bus.
// -----------------------------------------------------------------------------
`default_nettype none

module dram_x1 #(parameter ROWBITS = 8,
                 parameter LANE = 0) (     // data bit: bus_resolve.py --net-index-param
    input  wire p2, p3, p4, p5, p6, p7, p9, p10, p11, p12, p13, p15,
    output wire p14,
    input  wire p8, p16,
    input  wire [7:0] psram_q,   // not on the PCB: RAM_PSRAM's read data (--model-input)
    input  wire psram_oe,        //   ... and its output enable
    input  wire clk_sys);        // wired up automatically by bus_resolve.py

`ifdef RAM48
  localparam POPULATED = 1;
`elsif RAM_PSRAM
  localparam POPULATED = (ROWBITS <= 7);    // the 64K parts live in the PSRAM
`else
  localparam POPULATED = (ROWBITS <= 7);    // 16K parts only; see above
`endif
  // Cells stored: all of a 16K part; for a 64K part, the half the board uses
  // (row bit 7 is the jumper, constant -- see above).
  localparam RB = (ROWBITS == 8) ? 7 : ROWBITS;   // row bits stored
  localparam AW = RB + ROWBITS;

  wire [7:0] addr = {p9, p13, p10, p11, p12, p6, p7, p5};   // A7..A0
  wire [ROWBITS-1:0] a = addr[ROWBITS-1:0];

  generate
    if (POPULATED) begin : populated
      reg mem [0:(1 << AW) - 1];
      reg [RB-1:0] row = {RB{1'b0}};
      reg [ROWBITS-1:0] col = {ROWBITS{1'b0}};
      reg dout = 1'b1;
      reg wr_d = 1'b0;
      reg [1:0] hold = 2'd0;
      // pins as latched on the last two clk_sys edges, and the strobes as
      // believed (see "Settling" below)
      reg ras_1 = 1'b1, cas_1 = 1'b1, we_1 = 1'b1, ras_2 = 1'b1, cas_2 = 1'b1, we_2 = 1'b1;
      reg d_1 = 1'b0, d_2 = 1'b0;
      reg [ROWBITS-1:0] a_1 = {ROWBITS{1'b0}}, a_2 = {ROWBITS{1'b0}};
      reg ras_f = 1'b1, cas_f = 1'b1, we_f = 1'b1;
      reg rd_valid = 1'b0;                     // a read started at the last /CAS fall
      integer i;
      initial for (i = 0; i < (1 << AW); i = i + 1) mem[i] = 1'b0;

      // A DRAM write can be timed two ways.  In an *early* write /WE is already
      // low when /CAS falls, and the data is taken at that edge.  In a *late*
      // write /WE falls afterwards, while /CAS is low, and the data is taken
      // then.  This board does late writes exclusively -- every one of them --
      // so a model that only samples /WE at the /CAS edge loses every write and
      // performs spurious ones with whatever /WE was left over from the
      // previous cycle.  That looks exactly like broken memory: correct
      // addresses, correct data on the bus, correct strobes, nothing stored.
      //
      // Writing on the first edge where /RAS, /CAS and /WE are all low covers
      // both styles, and sampling on the system clock rather than on the
      // strobes themselves keeps it a single always block that synthesises.
      // Settling.  The strobes reach these pins through the board's gates
      // (the D35 delay line, decoders, the /CAS multiplexer), and on the FPGA
      // that is up to ~11 ns of logic against a 7.4 ns clk_sys period: on the
      // first clock after a strobe changes, some of this chip's flip-flops
      // could see the new level and others the old one, or a passing glitch.
      // On hardware that wrote the wrong cells -- the SD menu's colour bytes
      // came out different every time -- and whether it happened depended on
      // the build's placement.  So, as a TTL designer would with a noisy
      // strobe: latch every pin once (_1), keep the previous latch (_2), and
      // believe a strobe level (_f) only when two latches in a row agree.
      // The address and data then come from _2, at least two clocks after
      // they changed.  The cost is ~3 clocks (22 ns) of extra access time,
      // against the board's ~150 ns.
      wire ras_n = (ras_1 == ras_2) ? ras_1 : ras_f;
      wire cas_n = (cas_1 == cas_2) ? cas_1 : cas_f;
      wire we_n  = (we_1  == we_2)  ? we_1  : we_f;
      wire wr_now = ~ras_n & ~cas_n & ~we_n;
      wire [ROWBITS-1:0] col_now = (cas_f && !cas_n) ? a_2 : col;

      always @(posedge clk_sys) begin
        {ras_1, cas_1, we_1, d_1, a_1} <= {p4, p15, p3, p2, a};
        {ras_2, cas_2, we_2, d_2, a_2} <= {ras_1, cas_1, we_1, d_1, a_1};
        ras_f <= ras_n;
        cas_f <= cas_n;
        we_f  <= we_n;
        wr_d  <= wr_now;

        if (ras_f && !ras_n) row <= a_2[RB-1:0];      // /RAS falling: row
        if (cas_f && !cas_n) begin                    // /CAS falling: column
          col <= a_2;
          if (!ras_n && we_n) dout <= mem[{row, a_2}]; // ... and a read
        end

        if (wr_now && !wr_d) mem[{row, col_now}] <= d_2;

        // The output follows /CAS alone once a read has started: /RAS rising
        // first does not turn it off on the real part, and on this board /RAS
        // does rise before /CAS at the end of the pixel read.  Then hold for
        // the turn-off time after /CAS rises: 1 clock here, plus the 3 the
        // settling adds, is the 4 clocks (~30 ns) the pins see.
        if (cas_f && !cas_n) rd_valid <= !ras_n && we_n;
        else if (cas_n)      rd_valid <= 1'b0;
        if (!cas_n && rd_valid) hold <= 2'd1;
        else if (hold != 2'd0) hold <= hold - 2'd1;
      end

      // Live from a read's /CAS fall until /CAS rises -- regardless of /RAS --
      // plus a short hold.  A real КР565РУ6 keeps its output valid for its
      // turn-off time after /CAS rises, and
      // this board relies on that: VCLK, which loads the pixel shifter
      // (U_D51/U_D52), falls on the very edge that ends the pixel read.
      // Releasing the bus at that instant left the shifter loading an
      // undriven, all-ones bus -- every pixel ink, a black screen.  Three
      // system clocks (~22 ns) is within the real part's turn-off time and far
      // short of the next access.  It must release to z, not to 1: the CPU,
      // the ROM and the '245 all drive this same net.
      assign p14 = ((!cas_f && rd_valid) || hold != 2'd0) ? dout : 1'bz;
`ifdef RAM_PSRAM
    end else if (ROWBITS == 8) begin : psram
      assign p14 = psram_oe ? psram_q[LANE] : 1'bz;  // the socket wired to psram_bank
`endif
    end else begin : empty
      assign p14 = 1'bz;                            // no chip in the socket
    end
  endgenerate
endmodule

// --- 27C128, 16K x 8, initialised from a $readmemh image ---------------------
module rom_27c128 #(parameter ROMFILE     = "spectrum48.hex",
                    parameter ROMFILE1LO  = "spectrum48_1lo.hex",   // ROM_BANK1_SMALL only
                    parameter ROMFILE1HI  = "spectrum48_1hi.hex") (
    input  wire p26, p23, p2, p21, p24, p25, p9, p10, p3, p4, p5, p6, p7, p8,
    input  wire p20, p22, p1, p27,
    output wire p11, p12, p13, p15, p16, p17, p18, p19,
    input  wire p14, p28,
    input  wire rom_bank,        // not on the PCB: bus_resolve.py --model-input
    input  wire clk_sys);        // wired up automatically by bus_resolve.py

  // `define ROM_BANKS (the SD loader build): a second 16K bank behind the
  // first, like a divIDE's EPROM sharing the socket's lines -- ROMFILE then
  // holds 32K, and rom_bank picks the half.  Otherwise rom_bank is ignored.
  //
  // `define ROM_BANK1_SMALL as well (the Tang Nano 9K, short of block RAM):
  // bank 1 is only the two windows the menu uses, 0000-0FFF and 3800-3FFF,
  // 6K instead of 16K -- like fitting a small EPROM and decoding only the
  // addresses it answers.  Three memories, each a power of two (Gowin builds
  // ROMs from power-of-two slices, and rounds one 22K array up to 32K): bank
  // 0 from ROMFILE, the windows from ROMFILE1LO and ROMFILE1HI (mk_sdrom.py
  // SMALL_BANK1=1).  Elsewhere in bank 1 the windows repeat; nothing reads
  // there.  8 + 2 + 1 blocks.
  wire [13:0] ra = {p26, p2, p23, p21, p24, p25, p3, p4, p5, p6, p7, p8, p9, p10};
`ifdef ROM_BANKS
`ifdef ROM_BANK1_SMALL
  localparam AB = 14;
  wire [13:0] a = ra;
  reg [7:0] mem1lo [0:4095];
  reg [7:0] mem1hi [0:2047];
`else
  localparam AB = 15;
  wire [14:0] a = {rom_bank, ra};
`endif
`else
  localparam AB = 14;
  wire [13:0] a = ra;
`endif
  reg [7:0] mem [0:(1 << AB) - 1];
  reg [7:0] d;
  reg [8*64:1] romfile;
`ifdef ROM_BANK1_SMALL
  reg [8*64:1] romfile1lo, romfile1hi;
`endif
  initial begin
    // +ROMFILE=<path> swaps the image in simulation.  testrom.hex writes the
    // screen immediately; the real ROM takes a second of machine time to get
    // there, which is hours of simulation.
`ifdef SYNTHESIS
    // $value$plusargs is simulation-only -- yosys cannot resolve it -- and
    // $readmemh needs a literal path, not a variable, so use the parameter.
    $readmemh(ROMFILE, mem);
`ifdef ROM_BANK1_SMALL
    $readmemh(ROMFILE1LO, mem1lo);
    $readmemh(ROMFILE1HI, mem1hi);
`endif
`else
    if (!$value$plusargs("ROMFILE=%s", romfile)) romfile = ROMFILE;
    $readmemh(romfile, mem);
`ifdef ROM_BANK1_SMALL
    if (!$value$plusargs("ROMFILE1LO=%s", romfile1lo)) romfile1lo = ROMFILE1LO;
    if (!$value$plusargs("ROMFILE1HI=%s", romfile1hi)) romfile1hi = ROMFILE1HI;
    $readmemh(romfile1lo, mem1lo);
    $readmemh(romfile1hi, mem1hi);
`endif
`endif
  end

  // A real 27C128 reads asynchronously, but block RAM needs a clock, and an
  // asynchronous 16K x 8 would have to be built from LUTs -- tens of thousands
  // of them, which is why the first attempt at this silently optimised the
  // whole CPU away instead.
  //
  // So the block RAM reads synchronously on clk_sys, every cycle: the data
  // follows the address one clk_sys (7.4 ns) behind, far quicker than a real
  // 27C128's 150-250 ns.  (It used to read on the falling edge of /CE, which
  // made /CE -- a board signal -- one more separately routed FPGA clock.)
`ifdef ROM_BANK1_SMALL
  // All three read every clock; the bank and A13, registered alongside,
  // pick the one that answers, into a register of its own: two clocks from
  // address to data (25 ns at 81 MHz, against the 27C128's 150-250), and a
  // named register the timing constraints can start from.
  reg [7:0] d0, d1lo, d1hi;
  reg [1:0] sel;
  always @(posedge clk_sys) begin
    d0   <= mem[a];
    d1lo <= mem1lo[ra[11:0]];
    d1hi <= mem1hi[ra[10:0]];
    sel  <= {rom_bank, ra[13]};
    d    <= !sel[1] ? d0 : sel[0] ? d1hi : d1lo;
  end
`else
  always @(posedge clk_sys) d <= mem[a];
`endif

  wire oe = ~p20 & ~p22;
  // Release to `z`, not to FF -- see the note on the DRAM output above.
  assign {p19, p18, p17, p16, p15, p13, p12, p11} = oe ? d : 8'hzz;
endmodule
`default_nettype wire
