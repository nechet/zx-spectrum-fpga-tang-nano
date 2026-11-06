#!/bin/sh
# Load a bitstream into the Tang Nano 9K with openFPGALoader.
#
#   scripts-9k/upload.sh               the 48K build, into the FPGA
#   scripts-9k/upload.sh flash         ... into the board's flash instead
#   scripts-9k/upload.sh 16k           the 16K build (flash 16k: into the flash)
#   scripts-9k/upload.sh file.fs       any bitstream (flash file.fs: into the flash)
#
#   into the FPGA (default): runs at once, gone at power-off -- for trying a build
#   flash: loaded at every power-up
#
# The JTAG clock is 1 MHz: the default 6 MHz has given a bad IDCODE on this
# board.  If the board is not found, unplug it and plug it in again without
# touching the buttons (see tang9k/README.md).
set -e
cd "$(dirname "$0")/.."
flash=; fs=tang9k/gowin_9k_48k/impl/pnr/krasnodar_9k_48k.fs
for a in "$@"; do
  case "$a" in
    flash) flash=-f ;;
    sram)  flash= ;;
    48k)   fs=tang9k/gowin_9k_48k/impl/pnr/krasnodar_9k_48k.fs ;;
    16k)   fs=tang9k/gowin_9k_sd720/impl/pnr/krasnodar_9k_sd720.fs ;;
    *.fs)  fs=$a ;;
    *)     echo "usage: $0 [flash] [16k | file.fs]" >&2; exit 1 ;;
  esac
done
[ -f "$fs" ] || { echo "no bitstream $fs: run scripts-9k/build.sh first" >&2; exit 1; }
openFPGALoader -b tangnano9k --freq 1000000 $flash "$fs"
