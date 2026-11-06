#!/bin/sh
# Unit test of the PSRAM controller (tb_psram.v): psram_ctrl.v against the
# strict die model psram_model.v -- power-up, CR0, then random writes and
# reads over 32K checked against a reference copy.  Every read's data delay
# is drawn from the datasheet's whole range (tDQSCK 2.0-5.5 ns), and 30 % of
# the accesses collide with a refresh.  DEFS="-DPATH_DLY=1.5" adds a board
# delay each way; -DTDQ_MIN= / -DTDQ_MAX= change the range.
set -e
cd "$(dirname "$0")"
IV=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
$IV -g2012 $DEFS -o ${OUT:-simpsram} tb_psram.v psram_ctrl.v psram_model.v gowin_ddr_sim.v
$VVP ${OUT:-simpsram}
