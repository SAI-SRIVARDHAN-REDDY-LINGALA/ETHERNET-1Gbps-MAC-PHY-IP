// tx_ifg - Inter-frame gap timer.

`timescale 1ns / 1ps
`default_nettype none

module tx_ifg #(

    parameter integer IFG_BIT_TIMES = 96,

    parameter integer NIBBLE_BITS   = 4,
    parameter integer OCTET_BITS    = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire speed_select,

    input  wire ifg_start,
    output reg  ifg_active,
    output reg  ifg_done
);

    localparam integer IFG_CYCLES_NIBBLE = IFG_BIT_TIMES / NIBBLE_BITS;
    localparam integer IFG_CYCLES_OCTET  = IFG_BIT_TIMES / OCTET_BITS;

    reg [5:0] count;

    reg speed_sel_meta;
    reg speed_sel_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            speed_sel_meta <= 1'b0;
            speed_sel_sync <= 1'b0;
        end else begin
            speed_sel_meta <= speed_select;
            speed_sel_sync <= speed_sel_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count      <= 6'd0;
            ifg_active <= 1'b0;
            ifg_done   <= 1'b0;
        end else begin

            ifg_done <= 1'b0;

            if (!ifg_active) begin

                if (ifg_start) begin
                    count      <= speed_sel_sync ? IFG_CYCLES_OCTET[5:0]
                                                  : IFG_CYCLES_NIBBLE[5:0];
                    ifg_active <= 1'b1;
                end
            end else begin

                if (count == 6'd1) begin
                    count      <= 6'd0;
                    ifg_active <= 1'b0;
                    ifg_done   <= 1'b1;
                end else begin
                    count <= count - 6'd1;
                end
            end
        end
    end

endmodule

`default_nettype wire

