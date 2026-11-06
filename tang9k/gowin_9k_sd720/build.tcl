set_device -name GW1NR-9C GW1NR-LV9QN88PC6/I5
add_file -type verilog "defines.v"
add_file -type verilog "top9k.v"
add_file -type verilog "../../tang20k/ps2_rx.v"
add_file -type verilog "../../tang20k/ps2_zx_keymap.v"
add_file -type verilog "../../tang20k/zx_matrix.v"
add_file -type verilog "../../tang20k/sd_bridge.v"
add_file -type verilog "../../tang20k/sd_spi.v"
add_file -type verilog "../../tang20k/fat32.v"
add_file -type verilog "../../tang20k/nmi_gen.v"
add_file -type verilog "../../tang20k/ps2_keyboard.v"
add_file -type verilog "../../core/top.v"
add_file -type verilog "../../tang20k/scan_tripler.v"
add_file -type verilog "../../core/hdmi_out.v"
# HDMI with sound: the encoder from hdl-util/hdmi (apicula's copy of the same
# file has the data-island modes stubbed out), its packet modules, ours
add_file -type verilog "../../tang20k/third_party/hdmi/tmds_channel.sv"
add_file -type verilog "../../tang20k/third_party/hdmi/packet_picker.sv"
add_file -type verilog "../../tang20k/third_party/hdmi/packet_assembler.sv"
add_file -type verilog "../../tang20k/third_party/hdmi/audio_clock_regeneration_packet.sv"
add_file -type verilog "../../tang20k/third_party/hdmi/audio_sample_packet.sv"
add_file -type verilog "../../tang20k/third_party/hdmi/auxiliary_video_information_info_frame.sv"
add_file -type verilog "../../tang20k/third_party/hdmi/source_product_description_info_frame.sv"
add_file -type verilog "../../tang20k/third_party/hdmi/audio_info_frame.sv"
add_file -type verilog "../../tang20k/hdmi_audio_out.sv"
add_file -type verilog "../../tang20k/beeper_audio.v"
add_file -type verilog "../../core/gen/krasnodar48_synth.v"
add_file -type verilog "../../core/gen/fpga_memory.v"
add_file -type verilog "../../core/gen/lib_sync.v"
add_file -type verilog "../../core/gen/i8255.v"
add_file -type verilog "../../core/gen/z80_chip.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/synth/counters_sync.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/synth/synth_parts.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/third_party/tv80/tv80n.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/third_party/tv80/tv80_core.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/third_party/tv80/tv80_alu.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/third_party/tv80/tv80_mcode.v"
add_file -type verilog "../../Krasnodar-48-fpga/Verilog/third_party/tv80/tv80_reg.v"
add_file -type verilog "../../tang20k/pll_405.v"
add_file -type cst "tangnano9k_gowin.cst"
add_file -type sdc "krasnodar.sdc"
# The ROM: the 48K ROM with the loader menu patched in (mk_sdrom.py), written
# here as spectrum48.hex -- the name the board's ROM model loads.  Generated
# on every build; the original image is not touched.  SMALL_BANK1: the
# compact 22K image ROM_BANK1_SMALL expects.
set ::env(SMALL_BANK1) 1
exec python3 ../../tang20k/mk_sdrom.py ../../core/spectrum48.hex spectrum48.hex
set_option -top_module top9k
set_option -verilog_std sysv2017
set_option -output_base_name krasnodar_9k_sd720
set_option -use_sspi_as_gpio 1
set_option -looplimit 40000      ;# 16384-cell power-up clear of each video DRAM (dram_x1)
set_option -place_option 1      ;# timing-driven placement
set_option -route_option 1
run all
