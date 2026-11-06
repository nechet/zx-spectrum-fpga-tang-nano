// Implementation of HDMI packet ECC calculation.
// By Sameer Puri https://github.com/sameer

module packet_assembler (
    input logic clk_pixel,
    input logic reset,
    input logic data_island_period,
    // timing: header and sub arrive pre-shifted -- the bits for this pixel at
    // the bottom (header[0], sub[i][1:0]) -- from shift registers in
    // hdmi_audio_out.sv, instead of being indexed here by the counter (a 28:1
    // multiplexer ahead of the ECC, too slow for the Tang Nano 9K at 81 MHz)
    input logic [23:0] header, // See Table 5-8 Packet Types
    input logic [55:0] sub [3:0],
    output logic [8:0] packet_data, // See Figure 5-4 Data Island Packet and ECC Structure
    output logic [4:0] counter = 5'd0
);

// 32 pixel wrap-around counter. See Section 5.2.3.4 for further information.
always_ff @(posedge clk_pixel)
begin
    if (reset)
        counter <= 5'd0;
    else if (data_island_period)
        counter <= counter + 5'd1;
end
// BCH packets 0 to 3 are transferred two bits at a time, see Section 5.2.3.4 for further information.

// Initialize parity bits to 0
logic [7:0] parity [4:0];
initial begin parity[0] = 8'd0; parity[1] = 8'd0; parity[2] = 8'd0; parity[3] = 8'd0; parity[4] = 8'd0; end  // iverilog: element by element

// timing: the data bits come from the bottom of the shifted inputs; the ECC
// bits at the end of the packet (counter 28-31, 24-31 for the header) by a
// small index into parity
wire       ecc_out  = counter >= 5'd28;
wire       ecc_out4 = counter >= 5'd24;
wire [5:0] pi = {counter[1:0], 1'b0};       // 28 -> 0, 29 -> 2, ...
wire [3:0] lo, hi;
genvar j;
generate
    for (j = 0; j < 4; j++)
    begin: bits
        assign lo[j] = ecc_out ? parity[j][pi[2:0]]        : sub[j][0];
        assign hi[j] = ecc_out ? parity[j][pi[2:0] + 3'd1] : sub[j][1];
    end
endgenerate
wire bit4 = ecc_out4 ? parity[4][counter[2:0]] : header[0];
assign packet_data = {hi[3], hi[2], hi[1], hi[0], lo[3], lo[2], lo[1], lo[0], bit4};

// See Figure 5-5 Error Correction Code generator. Generalization of a CRC with binary BCH.
// See https://web.archive.org/web/20190520020602/http://hamsterworks.co.nz/mediawiki/index.php/Minimal_HDMI#Computing_the_ECC for an explanation of the implementation.
// See https://en.wikipedia.org/wiki/BCH_code#Systematic_encoding:_The_message_as_a_prefix for further information.
function automatic [7:0] next_ecc;
input [7:0] ecc, next_bch_bit;
begin
    next_ecc = (ecc >> 1) ^ ((ecc[0] ^ next_bch_bit) ? 8'b10000011 : 8'd0);
end
endfunction

logic [7:0] parity_next [4:0];

// The parity needs to be calculated 2 bits at a time for blocks 0 to 3.
// There's 56 bits being sent 2 bits at a time over TMDS channels 1 & 2, so the parity bits wouldn't be ready in time otherwise.
logic [7:0] parity_next_next [3:0];

genvar i;
generate
    for(i = 0; i < 5; i++)
    begin: parity_calc
        if (i == 4)
            assign parity_next[i] = next_ecc(parity[i], header[0]);           // timing: pre-shifted
        else
        begin
            assign parity_next[i] = next_ecc(parity[i], sub[i][0]);           // timing: pre-shifted
            assign parity_next_next[i] = next_ecc(parity_next[i], sub[i][1]);
        end
    end
endgenerate

always_ff @(posedge clk_pixel)
begin
    if (reset)
        begin parity[0] <= 8'd0; parity[1] <= 8'd0; parity[2] <= 8'd0; parity[3] <= 8'd0; parity[4] <= 8'd0; end  // iverilog: element by element
    else if (data_island_period)
    begin
        if (counter < 5'd28) // Compute ECC only on subpacket data, not on itself
        begin
            // iverilog: element by element, not parity[3:0] <= parity_next_next
            parity[0] <= parity_next_next[0];
            parity[1] <= parity_next_next[1];
            parity[2] <= parity_next_next[2];
            parity[3] <= parity_next_next[3];
            if (counter < 5'd24) // Header only has 24 bits, whereas subpackets have 56 and 56 / 2 = 28.
                parity[4] <= parity_next[4];
        end
        else if (counter == 5'd31)
            begin parity[0] <= 8'd0; parity[1] <= 8'd0; parity[2] <= 8'd0; parity[3] <= 8'd0; parity[4] <= 8'd0; end  // Reset ECC for next packet; iverilog: element by element
    end
    else
        begin parity[0] <= 8'd0; parity[1] <= 8'd0; parity[2] <= 8'd0; parity[3] <= 8'd0; parity[4] <= 8'd0; end  // iverilog: element by element
end

endmodule
