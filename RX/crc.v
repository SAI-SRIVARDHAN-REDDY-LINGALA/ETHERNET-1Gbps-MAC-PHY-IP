`timescale 1ns / 1ps
`default_nettype none

module crc (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        init,
    input  wire        valid,
    input  wire [7:0]  data,
    output reg  [31:0] value,
    output wire        good
);

    localparam [31:0] SEED    = 32'hFFFF_FFFF;
    localparam [31:0] POLY    = 32'hEDB88320;
    localparam [31:0] RESIDUE = 32'hDEBB20E3;

    function [31:0] step;
        input [7:0]  d;
        input [31:0] c;
        integer i;
        begin
            step = c;
            for (i = 0; i < 8; i = i + 1)
                step = (step[0] ^ d[i]) ? ({1'b0, step[31:1]} ^ POLY)
                                        :  {1'b0, step[31:1]};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            value <= SEED;
        else if (valid)
            value <= step(data, init ? SEED : value);
        else if (init)
            value <= SEED;
    end

    assign good = (value == RESIDUE);

endmodule

`default_nettype wire
