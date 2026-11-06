#!/bin/sh
# Run the Tang Nano 9K simulations with the system's Icarus Verilog
# (iverilog, vvp on the PATH).  Another build: IVERILOG=... VVP=...
#
#   scripts-9k/test.sh       the PSRAM controller, the upper 32 KB in the
#                                PSRAM, the 48K and 16K machines with the real
#                                ROM; normal and worst-case PSRAM timing  (hours)
#
# Needs the ROM (scripts-9k/get_rom.sh).  "read ready N ticks" is the slowest
# PSRAM read met; the CPU takes the byte at 30.
set -e
cd "$(dirname "$0")/.."
[ -f core/spectrum48.hex ] || { echo "no ROM yet: run scripts-9k/get_rom.sh" >&2; exit 1; }
run() { echo "=== $*"; "$@" 2>&1 | grep -v "sorry: constant selects" | grep -E "PASS|FAIL|ALL PASSED|FAILED|TIMEOUT|read ready"; }
W="-DPSRAM_2X_PCT=100 -DPSRAM_TDQ=5.5"
run tang9k/tb_psram.sh
run tang9k/tb_ram48_9k.sh
run env DEFS="$W" OUT=simram48_9kw tang9k/tb_ram48_9k.sh
run tang9k/tb_9k48.sh
run env DEFS="$W" tang9k/tb_9k48.sh z80
run tang9k/tb_9k720.sh
