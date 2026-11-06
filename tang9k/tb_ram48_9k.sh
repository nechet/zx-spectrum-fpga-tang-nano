#!/bin/sh
# The upper-32K test (testrom5, as tb_ram48.sh) on the Tang Nano 9K's 48K
# configuration: the board on 81 MHz, the upper bank in the PSRAM
# (RAM_PSRAM: psram_bank.v, psram_ctrl.v, and psram_model.v for the die).
# DEFS="-DPSRAM_2X_PCT=100 -DPSRAM_TDQ=5.5": every access hits a refresh and
# the data comes as late as the datasheet allows -- the worst case.
set -e
cd "$(dirname "$0")/../core"
L=../tang20k
K=../Krasnodar-48-fpga/Verilog
T=$K/third_party/tv80
IV=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
make gen/krasnodar48_synth.v >/dev/null
$IV -g2012 -DRAM_PSRAM -DHDMI_720P -DBOARD_81 $DEFS -I$L -I../tang9k -o ${OUT:-simram48_9k} $L/tb_ram48.v \
    top.v $L/scan_tripler.v hdmi_out.v third_party/apicula/tmds_channel.v \
    ../tang9k/psram_bank.v ../tang9k/psram_ctrl.v ../tang9k/psram_model.v ../tang9k/gowin_ddr_sim.v \
    gen/krasnodar48_synth.v gen/fpga_memory.v gen/lib_sync.v gen/i8255.v gen/z80_chip.v \
    $K/synth/counters_sync.v $K/synth/synth_parts.v \
    $T/tv80n.v $T/tv80_core.v $T/tv80_alu.v $T/tv80_mcode.v $T/tv80_reg.v pll_sim.v $L/sim_720p.v
$VVP ${OUT:-simram48_9k} +ROMFILE=$L/testrom5.hex
