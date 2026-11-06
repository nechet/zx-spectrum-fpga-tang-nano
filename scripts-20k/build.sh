#!/bin/sh
# Build the Tang Nano 20K bitstream with the Gowin toolchain (Gowin EDA
# 1.9.11; the free Education edition covers the GW2AR-18C).
#
#   export GOWIN=/path/to/gowin/IDE      the folder that holds bin/gw_sh
#   scripts-20k/build.sh             1280x720 16:9, sound, SD loader, PS/2 keyboard
#   scripts-20k/build.sh 576p        720x576 4:3, the same machine with the scan doubler
#
# Needs the ROM first (scripts-20k/get_rom.sh), python3 and z80asm (the SD menu
# ROM is assembled during the build).  The bitstream:
#   720p  tang20k/gowin_sd720/impl/pnr/krasnodar_20k_sd720.fs
#   576p  tang20k/gowin_sd/impl/pnr/krasnodar_20k_sd.fs
set -e
cd "$(dirname "$0")/.."
[ -f core/spectrum48.hex ] || { echo "no ROM yet: run scripts-20k/get_rom.sh" >&2; exit 1; }
command -v z80asm >/dev/null || { echo "z80asm not found (Debian/Ubuntu: apt install z80asm)" >&2; exit 1; }
case "${1:-720p}" in
  720p) tang20k/build.sh gowin_sd720 ;;
  576p) tang20k/build.sh gowin_sd ;;
  *)    echo "usage: $0 [576p]" >&2; exit 1 ;;
esac
