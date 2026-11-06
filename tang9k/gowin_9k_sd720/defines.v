// Macros for the Gowin build of the Tang Nano 9K port (GW1NR-9C).  Listed
// first so they apply to every later file: the project compiles as a single
// unit, as the 20K builds do.  No GW2A: pll_405.v picks the 9K's PLL.
`define SYNTHESIS
`define PS2_KBD                // PS/2 keyboard on pins 31 (CLK), 32 (DATA)
`define SD_LOADER              // microSD games loader: 8255 bridge, NMI menu (F12 / S2)
`define ROM_BANKS              // the stock ROM and the SD ROM, paged by the 8255 PC5
`define ROM_BANK1_SMALL        // ...with only the 6K of bank 1 the menu uses (block RAM)
`define HDMI_AUDIO             // beeper over HDMI: data islands with 48 kHz audio
`define HDMI_720P              // 1280x720: 3x3 line tripler (scan_tripler.v), one PLL for all clocks
`define BOARD_81               // the board on the 81 MHz pixel clock: 135 MHz is too fast for this chip
// No RAM48: the 9K has 26 blocks of RAM, and the upper 32 KB would take 16
// of them.  A 16K Spectrum for now; the upper RAM goes into the PSRAM next.
