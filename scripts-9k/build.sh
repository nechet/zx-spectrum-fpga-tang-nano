#!/bin/sh
# Build the Tang Nano 9K bitstream with the Gowin toolchain (Gowin EDA
# 1.9.11; the free Education edition covers the GW1NR-9C).
#
#   export GOWIN=/path/to/gowin/IDE      the folder that holds bin/gw_sh
#   scripts-9k/build.sh              48K (upper 32 KB in the PSRAM), 720p, sound, SD loader, PS/2
#   scripts-9k/build.sh 16k          the same as a 16K machine, no PSRAM
#
# Needs the ROM first (scripts-9k/get_rom.sh), python3 and z80asm (the SD menu
# ROM is assembled during the build).  The bitstream:
#   48K  tang9k/gowin_9k_48k/impl/pnr/krasnodar_9k_48k.fs
#   16K  tang9k/gowin_9k_sd720/impl/pnr/krasnodar_9k_sd720.fs
set -e
cd "$(dirname "$0")/.."
[ -f core/spectrum48.hex ] || { echo "no ROM yet: run scripts-9k/get_rom.sh" >&2; exit 1; }
command -v z80asm >/dev/null || { echo "z80asm not found (Debian/Ubuntu: apt install z80asm)" >&2; exit 1; }
case "${1:-48k}" in
  48k) tang20k/build.sh ../tang9k/gowin_9k_48k ;;
  16k) tang20k/build.sh ../tang9k/gowin_9k_sd720 ;;
  *)   echo "usage: $0 [16k]" >&2; exit 1 ;;
esac
