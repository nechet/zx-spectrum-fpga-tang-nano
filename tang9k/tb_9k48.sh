#!/bin/sh
# The Tang Nano 9K 48K configuration (gowin_9k_48k) on the whole board: as
# tb_9k720.sh, but with the upper 32 KB in the PSRAM (RAM_PSRAM, the die
# modelled by psram_model.v), so the real ROM boots as on a 48K machine.
#   ./tb_9k48.sh          boot, F12, the menu, one 720p frame pixel by pixel
#   ./tb_9k48.sh z80      boot, F12, load the test .z80, all 48K checked byte by byte
#   ./tb_9k48.sh game     a real game's .tap (TAPE=, GAME_PC= as tb_sdgame.sh), run on
#                         for GAME_RUN_MS (default 2000) with the upper-RAM scoreboard
# DEFS="-DPSRAM_2X_PCT=100 -DPSRAM_TDQ=5.5" for the PSRAM's worst case.
set -e
cd "$(dirname "$0")/../tang20k"
python3 mk_sdrom.py                                  # spectrum48_sd.hex: the testbench's copy of bank 0
SMALL_BANK1=1 python3 mk_sdrom.py ../core/spectrum48.hex spectrum48_sd9k.hex
if [ "$1" = game ]; then
  TAPE=${TAPE:-../zx-games/tap/MANIC.TAP}
  TINY_TAP=$TAPE IMAGE_OUT=tb_game_image.hex EXPECT_OUT=/dev/null python3 mk_fat_image.py
  MODE="-DTAP_TEST -DGAME_TAP -DSCOREBOARD -DGAME_RUN_MS=${GAME_RUN_MS:-2000} -DGAME_PC=16'h${GAME_PC:-8400} -DSD_SECTORS=512"
  IMGDEF="-DSD_IMAGE=\"../tang20k/tb_game_image.hex\""
  OUT=sim9k48g
elif [ "$1" = z80 ]; then MODE="-DSCOREBOARD"; OUT=sim9k48z; else MODE="-DFRAME_TEST"; OUT=sim9k48f; fi
L=../tang20k
cd ../core
K=../Krasnodar-48-fpga/Verilog
T=$K/third_party/tv80
IV=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
make gen/krasnodar48_synth.v >/dev/null
$IV -g2012 -DPS2_KBD -DSD_LOADER -DROM_BANKS -DROM_BANK1_SMALL -DBOARD_81 -DRAM_PSRAM \
    -DHDMI_720P $MODE ${IMGDEF:+"$IMGDEF"} $DEFS -I$L -I../tang9k -o $OUT $L/tb_sdmenu.v \
    $L/ps2_keyboard.v $L/ps2_rx.v $L/ps2_zx_keymap.v $L/zx_matrix.v \
    $L/sd_bridge.v $L/sd_spi.v $L/fat32.v $L/nmi_gen.v $L/sd_card_model.v \
    ../tang9k/psram_bank.v ../tang9k/psram_ctrl.v ../tang9k/psram_model.v ../tang9k/gowin_ddr_sim.v \
    top.v $L/scan_tripler.v hdmi_out.v third_party/apicula/tmds_channel.v \
    gen/krasnodar48_synth.v gen/fpga_memory.v gen/lib_sync.v gen/i8255.v gen/z80_chip.v \
    $K/synth/counters_sync.v $K/synth/synth_parts.v \
    $T/tv80n.v $T/tv80_core.v $T/tv80_alu.v $T/tv80_mcode.v $T/tv80_reg.v pll_sim.v $L/sim_720p.v
$VVP $OUT +ROMFILE=$L/spectrum48_sd9k.hex +ROMFILE1LO=$L/spectrum48_sd9k_1lo.hex \
    +ROMFILE1HI=$L/spectrum48_sd9k_1hi.hex
[ "$1" = z80 ] || mv -f frame720.ppm $L/frame9k48.ppm 2>/dev/null || true
