// Timing constraints for the Tang Nano 9K build (BOARD_81).
//
// The 27 MHz crystal; Gowin derives the PLL outputs itself: 405 MHz (the
// serialisers) and, through CLKDIV, 81 MHz -- the pixel clock, which on the
// 9K is also the board's clk_sys (top.v, BOARD_81).  One clock domain for
// everything but the SD card side (27 MHz) and the 48 kHz audio clock.
create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]

// The Z80 core runs on clk_sys but only steps on a detected edge of its CLK
// pin, which the board's dividers make: 24 clk_sys ticks a CPU clock at 81
// MHz, and the edges never closer than about 5 ticks.  Its internal paths
// therefore have 4 cycles to settle, not one.  The register file (i_reg) is
// distributed RAM, written only on the same clock enable; its cells are not
// registers, so its read and write address, data and write-enable pins are
// named.  The bus strobes and the data-in latch, one level up in tv80n_sync,
// are loaded only on the same enables (its rise and fall).  The CPU clock's
// edge detector there (clk_s*, clk_d, rise, fall) is NOT included: it runs
// every clock and drives every enable -- a true one-cycle path.
set_multicycle_path -from [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -setup -end 4
set_multicycle_path -from [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -hold -end 3
set_multicycle_path -from [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -to [get_pins {core/kras/U_D1/core/i_tv80_core/i_reg/*/DI* core/kras/U_D1/core/i_tv80_core/i_reg/*/AD* core/kras/U_D1/core/i_tv80_core/i_reg/*/WAD* core/kras/U_D1/core/i_tv80_core/i_reg/*/WRE}] -setup -end 4
set_multicycle_path -from [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -to [get_pins {core/kras/U_D1/core/i_tv80_core/i_reg/*/DI* core/kras/U_D1/core/i_tv80_core/i_reg/*/AD* core/kras/U_D1/core/i_tv80_core/i_reg/*/WAD* core/kras/U_D1/core/i_tv80_core/i_reg/*/WRE}] -hold -end 3
set_multicycle_path -from [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -to [get_regs {core/kras/U_D1/core/mreq_n* core/kras/U_D1/core/iorq_n* core/kras/U_D1/core/rd_n* core/kras/U_D1/core/wr_n* core/kras/U_D1/core/di_reg*}] -setup -end 4
set_multicycle_path -from [get_regs {core/kras/U_D1/core/i_tv80_core/*}] -to [get_regs {core/kras/U_D1/core/mreq_n* core/kras/U_D1/core/iorq_n* core/kras/U_D1/core/rd_n* core/kras/U_D1/core/wr_n* core/kras/U_D1/core/di_reg*}] -hold -end 3
// The strobes, loaded on fall, reach the core's registers (through the
// board's memory decoding and the data bus) loaded on rise: half a CPU clock.
set_multicycle_path -from [get_regs {core/kras/U_D1/core/mreq_n* core/kras/U_D1/core/iorq_n* core/kras/U_D1/core/rd_n* core/kras/U_D1/core/wr_n*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -setup -end 4
set_multicycle_path -from [get_regs {core/kras/U_D1/core/mreq_n* core/kras/U_D1/core/iorq_n* core/kras/U_D1/core/rd_n* core/kras/U_D1/core/wr_n*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -hold -end 3

// The ROM (fpga_memory.v, ROM_BANK1_SMALL) into the Z80: its output register
// d follows the CPU's address two clocks later, and the CPU takes the byte
// at least a CPU clock (24 ticks) after it set the address -- so the byte is
// stable for many clocks before it is used.
set_multicycle_path -from [get_regs {core/kras/U_D15/d_*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -setup -end 2
set_multicycle_path -from [get_regs {core/kras/U_D15/d_*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -hold -end 1
// The DRAM chips' read data into the Z80: read on /CAS falling, early in the
// CPU's memory cycle, and taken by the CPU at the end of T2 -- tens of
// clocks later.  The read lands in the block RAM's own output register,
// which has no register name to start from, so the paths are named by the
// RAM's data-out pins they pass through.
set_multicycle_path -through [get_pins {core/kras/*/populated.mem*/DO*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -setup -end 2
set_multicycle_path -through [get_pins {core/kras/*/populated.mem*/DO*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -hold -end 1
// ... and the same chips' output enable (cas_f, rd_valid, hold): it turns on
// at /CAS falling and off after /CAS rises, both far from the CPU's CLK edge.
set_multicycle_path -through [get_pins {core/kras/*/populated.cas_f*/Q}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -setup -end 2
set_multicycle_path -through [get_pins {core/kras/*/populated.cas_f*/Q}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -hold -end 1
set_multicycle_path -through [get_pins {core/kras/*/populated.rd_valid*/Q}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -setup -end 2
set_multicycle_path -through [get_pins {core/kras/*/populated.rd_valid*/Q}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -hold -end 1
set_multicycle_path -through [get_pins {core/kras/*/populated.hold*/Q}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -setup -end 2
set_multicycle_path -through [get_pins {core/kras/*/populated.hold*/Q}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -hold -end 1

// The 8255 (i8255.v) tracks the data bus, port select and /CS only while
// /WR is low, and commits the last values when /WR rises; the CPU holds its
// address and data steady for a whole CPU clock around that.
set_multicycle_path -from [get_regs {core/kras/U_D1/core/* core/kras/U_D1/core/i_tv80_core/*}] -to [get_regs {core/kras/U_D3/din_r* core/kras/U_D3/sel_r* core/kras/U_D3/cs_r*}] -setup -end 2
set_multicycle_path -from [get_regs {core/kras/U_D1/core/* core/kras/U_D1/core/i_tv80_core/*}] -to [get_regs {core/kras/U_D3/din_r* core/kras/U_D3/sel_r* core/kras/U_D3/cs_r*}] -hold -end 1
set_multicycle_path -through [get_pins {core/kras/*/populated.mem*/DO*}] -to [get_regs {core/kras/U_D3/din_r*}] -setup -end 2
set_multicycle_path -through [get_pins {core/kras/*/populated.mem*/DO*}] -to [get_regs {core/kras/U_D3/din_r*}] -hold -end 1
// ... and its registers into the Z80, through the read multiplexer and the
// data bus: they change only when the CPU writes the 8255, and the CPU's next
// read is a machine cycle later.
set_multicycle_path -from [get_regs {core/kras/U_D3/ctrl* core/kras/U_D3/pa_* core/kras/U_D3/pb_* core/kras/U_D3/pc_*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -setup -end 2
set_multicycle_path -from [get_regs {core/kras/U_D3/ctrl* core/kras/U_D3/pa_* core/kras/U_D3/pb_* core/kras/U_D3/pc_*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -hold -end 1

// The SD bridge's port A byte into the Z80 (the menu's IN from the card),
// the same kind of path as the 8255 ports above: set long before the read
// cycle, taken on a CPU clock edge.
set_multicycle_path -from [get_regs {core/sdb/pa_ext*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -setup -end 2
set_multicycle_path -from [get_regs {core/sdb/pa_ext*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -hold -end 1
// Inside the 8255: its control word (port directions) into its bus latch.
// The control word changes only on a CPU write, many clocks before the next
// access.
set_multicycle_path -from [get_regs {core/kras/U_D3/ctrl*}] -to [get_regs {core/kras/U_D3/din_r*}] -setup -end 2
set_multicycle_path -from [get_regs {core/kras/U_D3/ctrl*}] -to [get_regs {core/kras/U_D3/din_r*}] -hold -end 1
// The keyboard's key state into the Z80, through the matrix and the data bus.
// A key press is asynchronous to the CPU, on the real board as here; the
// matrix's other input, the CPU's address, is covered above.
set_multicycle_path -from [get_regs {core/kbd/keymap/*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -setup -end 2
set_multicycle_path -from [get_regs {core/kbd/keymap/*}] -to [get_regs {core/kras/U_D1/core/i_tv80_core/* core/kras/U_D1/core/di_reg*}] -hold -end 1

// DRAM chips (fpga_memory.v): each pin is latched once (_1) and only trusted
// when the next latch agrees, so the board's gates have two clocks to settle
// into these flip-flops, not one.  (Named by their D pins: get_regs does not
// find these registers inside the generate block.)  One rule per latch: in one
// build a single list of five patterns caught nothing at all.  And -through,
// not -to: Gowin 1.9.11 matched no "-to [get_pins .../D]" at all.
set_multicycle_path -through [get_pins {core/kras/*/populated.ras_1*/D}] -setup -end 2
set_multicycle_path -through [get_pins {core/kras/*/populated.ras_1*/D}] -hold -end 1
set_multicycle_path -through [get_pins {core/kras/*/populated.cas_1*/D}] -setup -end 2
set_multicycle_path -through [get_pins {core/kras/*/populated.cas_1*/D}] -hold -end 1
set_multicycle_path -through [get_pins {core/kras/*/populated.we_1*/D}] -setup -end 2
set_multicycle_path -through [get_pins {core/kras/*/populated.we_1*/D}] -hold -end 1
set_multicycle_path -through [get_pins {core/kras/*/populated.d_1*/D}] -setup -end 2
set_multicycle_path -through [get_pins {core/kras/*/populated.d_1*/D}] -hold -end 1
set_multicycle_path -through [get_pins {core/kras/*/populated.a_1*/D}] -setup -end 2
set_multicycle_path -through [get_pins {core/kras/*/populated.a_1*/D}] -hold -end 1

// nmi_gen.v: the timer moves only on its microsecond tick, 81 clocks apart.
set_multicycle_path -from [get_regs {core/nmig/t_* core/nmig/armed* core/nmig/bstable*}] -to [get_regs {core/nmig/t_* core/nmig/armed* core/nmig/pulse*}] -setup -end 2
set_multicycle_path -from [get_regs {core/nmig/t_* core/nmig/armed* core/nmig/bstable*}] -to [get_regs {core/nmig/t_* core/nmig/armed* core/nmig/pulse*}] -hold -end 1

// SD loader (sd_bridge.v): the card side runs on the 27 MHz crystal clock,
// the board on 81 MHz.  Each crossing is either a first synchroniser stage
// (STROBE, ACK) or a byte that is stable long before the toggle announcing
// it (command, answer).
set_false_path -to [get_regs {core/sdb/st_s*}]
set_false_path -to [get_regs {core/sdb/pb_s1*}]
set_false_path -to [get_regs {core/sdb/ack_s*}]
set_false_path -to [get_regs {core/sdb/pa_ext*}]

// HDMI sound: clk_audio is a 48 kHz clock made by a flip-flop.  Name it, so
// the paths it clocks are timed against its own 20.8 us period; the
// crossings between it and clk_pixel are synchronised inside packet_picker
// (toggle + two flops) or carry data that is stable for half an audio period
// around the edge.
set_false_path -to [get_regs {core/hdmi_gen.beep/spk_s* core/hdmi_gen.beep/tap_s*}]
// beeper_audio.v at 720p: everything its sample arithmetic reads (spk_q,
// tap_q, sum, x_prev, y, acc) changes only on its clock enable, every third
// pixel clock, and its results are loaded only then.
set_multicycle_path -from [get_regs {core/hdmi_gen.beep/spk_q* core/hdmi_gen.beep/tap_q* core/hdmi_gen.beep/sum* core/hdmi_gen.beep/x_prev* core/hdmi_gen.beep/y_* core/hdmi_gen.beep/acc*}] -to [get_regs {core/hdmi_gen.beep/sum* core/hdmi_gen.beep/x_prev* core/hdmi_gen.beep/y_* core/hdmi_gen.beep/sample* core/hdmi_gen.beep/acc* core/hdmi_gen.beep/clk_audio*}] -setup -end 3
set_multicycle_path -from [get_regs {core/hdmi_gen.beep/spk_q* core/hdmi_gen.beep/tap_q* core/hdmi_gen.beep/sum* core/hdmi_gen.beep/x_prev* core/hdmi_gen.beep/y_* core/hdmi_gen.beep/acc*}] -to [get_regs {core/hdmi_gen.beep/sum* core/hdmi_gen.beep/x_prev* core/hdmi_gen.beep/y_* core/hdmi_gen.beep/sample* core/hdmi_gen.beep/acc* core/hdmi_gen.beep/clk_audio*}] -hold -end 2
create_clock -name clk_audio -period 20833.333 [get_nets {core/hdmi_gen.clk_audio}]
set_clock_groups -asynchronous -group [get_clocks {clk_audio}]

// Line tripler: board and pixel side share the clock here, but its line,
// frame and buffer-select signals still pass through two-flop synchronisers
// (they must on the 20K); the first stage carries no timing.
set_false_path -to [get_regs {core/dbl/hs_m* core/dbl/vs_m* core/dbl/wbuf_m*}]
// The board reset from the crystal's domain: the first synchroniser stage.
set_false_path -to [get_regs {core/res_s_0*}]
// The serialisers' reset, released once at power-up (see the 20K's file).
set_false_path -from [get_regs {core/tmdsrst*}]

report_timing -setup -max_paths 300 -max_common_paths 1
