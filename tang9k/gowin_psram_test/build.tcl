set_device -name GW1NR-9C GW1NR-LV9QN88PC6/I5
add_file -type verilog "defines.v"
add_file -type verilog "../psram_hwtest.v"
add_file -type verilog "../psram_ctrl.v"
add_file -type verilog "../../tang20k/uart_tx.v"
add_file -type cst "psram_test.cst"
add_file -type sdc "psram_test.sdc"
set_option -top_module psram_hwtest
set_option -verilog_std sysv2017
set_option -output_base_name psram_test
set_option -use_sspi_as_gpio 1
set_option -place_option 1
set_option -route_option 1
run all
