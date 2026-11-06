#!/bin/sh
# Run the Tang Nano 20K simulations with the system's Icarus Verilog
# (iverilog, vvp on the PATH).  Another build: IVERILOG=... VVP=...
#
#   scripts-20k/test.sh          quick: line tripler, HDMI audio at 720p   (~10 min)
#   scripts-20k/test.sh full     also the whole board: SD menu, .z80 load, .tap
#                                    load, 720p frame check            (several hours)
#
# The whole-board tests need the ROM (scripts-20k/get_rom.sh).
set -e
cd "$(dirname "$0")/.."
T=tang20k
run() { echo "=== $*"; "$@" 2>&1 | grep -v "sorry: constant selects" | grep -E "PASS|FAIL|ALL PASSED|FAILED|TIMEOUT"; }
run $T/tb_tripler.sh
run $T/tb_hdmi_audio.sh 720
if [ "$1" = full ]; then
  [ -f core/spectrum48.hex ] || { echo "no ROM yet: run scripts-20k/get_rom.sh" >&2; exit 1; }
  run $T/tb_hdmi_audio.sh
  run $T/tb_sdmenu.sh
  run $T/tb_sdpage.sh
  run $T/tb_sdtap.sh
  run $T/tb_720p.sh
fi
