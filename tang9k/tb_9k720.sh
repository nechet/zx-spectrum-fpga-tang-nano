#!/bin/sh
# The Tang Nano 9K configuration (gowin_9k_sd720) on the whole board: the
# board on the 81 MHz pixel clock (BOARD_81), a 16K machine (no RAM48), the
# small ROM bank 1 (ROM_BANK1_SMALL).  Boot to BASIC (WAIT_BASIC: a 16K
# machine has no RAM where the stack starts), F12, the menu, then one 1280 x
# 720 frame checked pixel by pixel, as tb_720p.sh does for the 20K.  Leaves
# the frame as frame9k.ppm here.
set -e
cd "$(dirname "$0")/../tang20k"
python3 mk_sdrom.py                                  # spectrum48_sd.hex: the testbench's copy of bank 0
SMALL_BANK1=1 python3 mk_sdrom.py ../core/spectrum48.hex spectrum48_sd9k.hex
L=../tang20k
cd ../core
K=../Krasnodar-48-fpga/Verilog
T=$K/third_party/tv80
IV=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
make gen/krasnodar48_synth.v >/dev/null
$IV -g2012 -DPS2_KBD -DSD_LOADER -DROM_BANKS -DROM_BANK1_SMALL -DBOARD_81 \
    -DHDMI_720P -DFRAME_TEST -DWAIT_BASIC -o sim9k720 $L/tb_sdmenu.v \
    $L/ps2_keyboard.v $L/ps2_rx.v $L/ps2_zx_keymap.v $L/zx_matrix.v \
    $L/sd_bridge.v $L/sd_spi.v $L/fat32.v $L/nmi_gen.v $L/sd_card_model.v \
    top.v $L/scan_tripler.v hdmi_out.v third_party/apicula/tmds_channel.v \
    gen/krasnodar48_synth.v gen/fpga_memory.v gen/lib_sync.v gen/i8255.v gen/z80_chip.v \
    $K/synth/counters_sync.v $K/synth/synth_parts.v \
    $T/tv80n.v $T/tv80_core.v $T/tv80_alu.v $T/tv80_mcode.v $T/tv80_reg.v pll_sim.v $L/sim_720p.v
$VVP sim9k720 +ROMFILE=$L/spectrum48_sd9k.hex +ROMFILE1LO=$L/spectrum48_sd9k_1lo.hex \
    +ROMFILE1HI=$L/spectrum48_sd9k_1hi.hex
mv -f frame720.ppm $L/frame9k.ppm 2>/dev/null || true
