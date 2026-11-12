# Krasnodar-48 on the Tang Nano 9K: technical notes

The [Tang Nano 9K](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/Nano-9K.html) design (GW1NR-LV9QN88PC6/I5, GW1N-9C). The machine is
the Tang Nano 20K's: 720p HDMI with sound, the PS/2 keyboard, the microSD
loader and its menu, all from [`../tang20k/`](../tang20k/README.md) and
[`../core/`](../core/). This folder holds only what the smaller chip needs
differently, chiefly the **upper 32 KB of RAM in the chip's on-package
PSRAM**: the 9K has 26 blocks of RAM against the 20K's 46, and the design
already uses 21 of them without the upper 32 KB. For building and using it,
see the [top-level README](../README.md).

## Builds

Gowin projects, built with `../tang20k/build.sh ../tang9k/<folder>` or
`../scripts-9k/build.sh` (`../scripts-9k/build.sh 16k` for the 16K build).

| folder | what | output |
|---|---|---|
| `gowin_9k_48k/` | **the main build**: 48K, the upper 32 KB in the PSRAM (`RAM_PSRAM`), 720p, sound, SD loader, PS/2 keyboard | `krasnodar_9k_48k.fs` |
| `gowin_9k_sd720/` | the same as a 16K machine, no PSRAM | `krasnodar_9k_sd720.fs` |
| `gowin_psram_test/` | the PSRAM tested on its own, results on the USB serial port (below) | `bitstreams/psram_test_9k.fs` |

Load with `../scripts-9k/upload.sh` (`flash` to write the flash, `16k` for the 16K build), or
`openFPGALoader -b tangnano9k --freq 1000000 <file.fs>`: the default 6 MHz
JTAG clock has given a bad IDCODE and a CRC failure on this board. If the
board is not found at all, unplug it and plug it in again without touching
the buttons: the board's USB chip can come up in its own bootloader
instead (it then shows as a "CDC Virtual ComPort" with ID `ffff:ffff`),
and the FPGA is not reachable until the next plug-in.

## What differs from the 20K

| | Tang Nano 9K | Tang Nano 20K |
|---|---|---|
| FPGA | GW1NR-9C: 26 block RAMs, 8 MB PSRAM on the package | GW2AR-18C: 46 block RAMs |
| upper 32 KB of RAM | in the PSRAM (`RAM_PSRAM`, `psram_bank.v`) | block RAM (`RAM48`) |
| board logic clock | 81 MHz (`BOARD_81`): the 405 MHz PLL's /5, the same clock as the pixels | 135 MHz |
| the menu's ROM bank | only the part that holds code (`ROM_BANK1_SMALL`) | the full 16 KB |
| HDMI output buffers | emulated LVDS (`ELVDS_OBUF`) | true LVDS |
| buttons S1, S2 | idle high (pulled up) | S1 idles low |

Both run the board at 13.5 MHz and 48.29 frames a second, with the same
1280x720 raster, so a picture or a sound on one is the same on the other.
The 135 MHz clock is too fast for the GW1N-9; at 81 MHz every delay the
board makes with RC networks and the CD4015 shift registers is counted in
81 MHz ticks instead. Those counts were measured again for 81 MHz rather
than scaled from 135: the scaled value for one of them opened a write
window one tick late and lost one CPU write in about 17,000
([LEARNING.md](../tang20k/LEARNING.md) 7.25).

## The upper 32 KB in the PSRAM

On the board the upper 32 KB are eight 565RU5 DRAMs, one per data bit,
sharing /RAS5, /CAS5, /WR5 and the multiplexed address. `psram_bank.v`
watches those same signals as the chips would, decodes row, column, read
and late write exactly as the block-RAM model does, and turns each access
into one PSRAM transaction. The eight sockets stay in the netlist; each
drives its own data bit from the bank's answer.

`psram_ctrl.v` speaks the PSRAM's HyperBus-style protocol on die 0: CS#,
a differential clock CK at 40.5 MHz (made from the 81 MHz clock by DDR
output cells, so no second PLL), RWDS, and eight data lines carrying a
byte on each CK edge. A read is three CK cycles of command and address, a
latency of L = 3 cycles (6 if the die is refreshing, which it signals on
RWDS), and the data. The die puts the data on **CK cycle 3 + L** (3 + 2L
when refreshing). That was measured on the board: the first version
expected 2 + L, read one cycle early and crashed games, while passing
every simulation, because the simulation model of the die had been written
from the same reading of the datasheet. The test jig below found it
([LEARNING.md](../tang20k/LEARNING.md) 7.26 tells the story).

Timing: the CPU takes the data 30 ticks (81 MHz) after /CAS5 falls. The
worst read, with a refresh collision and the data from the later RWDS
sample, is ready 29 ticks after /CAS5, so there is **one tick (12 ns) to
spare**. The whole-board tests print the slowest read they meet
(`psram_bank: read ready N ticks after /CAS5`), so any change that uses up
that tick shows at once. Writes are posted: the PSRAM write runs after the
CPU has moved on and is over long before the next access to the bank.

LED1 is a sticky PSRAM fault: a request while busy, or RWDS in the wrong
state when a byte was taken. It should never light.

**Diagnostic build.** With `` `define PSRAM_DIAG `` added to
`gowin_9k_48k/defines.v`, LEDs 0-4 show the fault causes separately
(request while busy, RWDS wrong, early sample used, late sample used, a
double-latency read seen) and `psram_diag_uart.v` sends read-timing counts
once a second on pin 17, the board's USB serial port (115200 8N1): reads,
errors, double-latency reads, and a histogram of where in a 12-sample
window RWDS rose.

**The test jig** (`gowin_psram_test/`, `psram_hwtest.v`, ready-made in
`bitstreams/`): the controller alone on the real PSRAM, no Spectrum. It
reads the die's ID0 and CR0 registers (00 5F and 8F E7 on this die), then
writes and reads back all 32 KB endlessly, and once a second prints the
counts and four raw traces of the PSRAM pins as the controller sees them,
tick by tick (see the comment at the top of `psram_hwtest.v`). LED0 lights
on any error. A healthy board prints `E000000` for ever.

## Pins

| signal | pin | notes |
|---|---|---|
| `clk` (27 MHz) | 52 | |
| `rst_s1` (button S1) | 3 | resets the machine |
| `menu_s2` (button S2) | 4 | opens the games menu, as F12 does |
| `led[0..5]` | 10, 11, 13, 14, 15, 16 | active low |
| `tmds_clk_p` | 69 (68) | emulated LVDS pair |
| `tmds_d_p[0..2]` | 71, 73, 75 (70, 72, 74) | emulated LVDS pairs |
| `ps2_clk`, `ps2_data` | 31, 32 | 3.3 V only |
| `sd_clk`, `sd_cmd`, `sd_dat3`, `sd_dat0` | 36, 37, 38, 39 | the on-board microSD slot, SPI mode |
| `uart_tx` | 17 | the USB serial port: diagnostic build and the test jig |

The PSRAM is inside the package and needs no pins in the constraints:
`top9k.v` names its signals `O_psram_*` / `IO_psram_*`, which Gowin
connects to the dies.

### LEDs

| LED | `gowin_9k_48k` | `gowin_9k_sd720` |
|---|---|---|
| 0 | the menu has been opened (NMI seen) | same |
| 1 | PSRAM fault (sticky, should stay off) | the realignment found the raster 1-2 pixels off (tolerated) |
| 2 | the raster was further off after the first lock | same |
| 3 | SD card mounted | same |
| 4 | SD error | same |
| 5 | heartbeat, about 1 Hz | same |

## Tests

Icarus Verilog (the system's `iverilog`). Run from anywhere, or all of
them through `../scripts-9k/test.sh`.

| script | what it checks |
|---|---|
| `tb_psram.sh` | the controller against a strict model of the die (`psram_model.v`): power-up, CR0, then thousands of random writes and reads with random refresh collisions and data delays |
| `tb_ram48_9k.sh` | the whole board with the PSRAM, running a test ROM that checks every byte of the upper 32 KB |
| `tb_9k48.sh` | the 48K machine with the real ROM: boot, F12, the menu, one 720p frame pixel by pixel. `z80`: loads a test snapshot and checks all 48 KB, every CPU read of the upper 32 KB compared with a reference copy. `game`: a real game's tape (`TAPE=...`, not included) run for a while with the same check |
| `tb_9k720.sh` | the 16K machine: boot, F12, the menu, one 720p frame |

For the whole-board tests, `DEFS="-DPSRAM_2X_PCT=100 -DPSRAM_TDQ=5.5"`
gives the PSRAM's worst case: every access collides with a refresh and the
data comes as late as the datasheet allows. (`tb_psram.sh` draws the data
delay from the datasheet's whole range anyway; see the script.) The whole-board tests need the ROM
(`../scripts-9k/get_rom.sh`) and z80asm.

## Files

| | |
|---|---|
| `psram_ctrl.v` | the PSRAM controller: power-up, CR0, one-byte reads and writes, RWDS sampling |
| `psram_bank.v` | the upper 32 KB: the eight DRAMs' signals turned into PSRAM transactions |
| `psram_diag_uart.v` | read-timing counters on the USB serial port (`PSRAM_DIAG`) |
| `psram_hwtest.v`, `gowin_psram_test/` | the stand-alone PSRAM test jig |
| `psram_model.v`, `psram_tb_die.vh`, `gowin_ddr_sim.v` | the die model, its hookup in the board testbenches, simulation models of Gowin's DDR cells |
| `tb_psram.v`, `tb_*.sh` | testbenches (above) |
| `gowin_9k_48k/`, `gowin_9k_sd720/` | the two machine builds: `top9k.v` (the board wrapper), `defines.v`, pins (`tangnano9k_gowin.cst`), timing constraints |
| `bitstreams/psram_test_9k.fs` | the test jig, ready to load (it carries no ROM) |
