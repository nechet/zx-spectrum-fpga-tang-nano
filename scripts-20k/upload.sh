#!/bin/sh
# Load a bitstream into the Tang Nano 20K with openFPGALoader.
#
#   scripts-20k/upload.sh              the 720p build, into the FPGA
#   scripts-20k/upload.sh flash        ... into the board's flash instead
#   scripts-20k/upload.sh 576p         the 576p build (flash 576p: into the flash)
#   scripts-20k/upload.sh file.fs      any bitstream (flash file.fs: into the flash)
#
#   into the FPGA (default): runs at once, gone at power-off -- for trying a build
#   flash: loaded at every power-up
#
# If the board is not found, check the USB cable and that your user may open
# the device (udev rules, see openFPGALoader's documentation).
set -e
cd "$(dirname "$0")/.."
flash=; fs=tang20k/gowin_sd720/impl/pnr/krasnodar_20k_sd720.fs
for a in "$@"; do
  case "$a" in
    flash) flash=-f ;;
    sram)  flash= ;;
    720p)  fs=tang20k/gowin_sd720/impl/pnr/krasnodar_20k_sd720.fs ;;
    576p)  fs=tang20k/gowin_sd/impl/pnr/krasnodar_20k_sd.fs ;;
    *.fs)  fs=$a ;;
    *)     echo "usage: $0 [flash] [576p | file.fs]" >&2; exit 1 ;;
  esac
done
[ -f "$fs" ] || { echo "no bitstream $fs: run scripts-20k/build.sh first" >&2; exit 1; }
openFPGALoader -b tangnano20k $flash "$fs"
