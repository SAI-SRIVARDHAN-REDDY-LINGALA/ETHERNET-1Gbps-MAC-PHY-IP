// crc32_parallel - Combinational CRC-32 step, shared by TX and RX.

`timescale 1ns/1ps
`default_nettype none

module crc32_parallel (
    input  wire [7:0]  data_in,
    input  wire [31:0] crc_in,
    output reg  [31:0] crc_out
);

    function [31:0] calc_next_crc;
        input [7:0]  d;
        input [31:0] c;
        reg   [31:0] crc_tmp;
        integer i;
        begin
            crc_tmp = c;
            for (i = 0; i < 8; i = i + 1) begin
                if ((crc_tmp[0] ^ d[i]) == 1'b1) begin
                    crc_tmp = {1'b0, crc_tmp[31:1]} ^ 32'hEDB88320;
                end else begin
                    crc_tmp = {1'b0, crc_tmp[31:1]};
                end
            end
            calc_next_crc = crc_tmp;
        end
    endfunction

    always @(*) begin
        crc_out = calc_next_crc(data_in, crc_in);
    end

endmodule

`default_nettype wire

