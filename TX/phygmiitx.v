`timescale 1ns / 1ps
`default_nettype none

module tx_phy (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       speed,

    input  wire [7:0] data_in,
    input  wire       valid_in,
    output wire       ready_in,

    output reg  [7:0] txd,
    output reg        tx_en,
    output reg        frame_done
);

    reg       half;
    reg [3:0] hi;

    assign ready_in = speed | ~half;

    wire take = ready_in & valid_in;
    wire en_n = half | take;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            half       <= 1'b0;
            hi         <= 4'd0;
            txd        <= 8'd0;
            tx_en      <= 1'b0;
            frame_done <= 1'b0;
        end else begin
            tx_en      <= en_n;
            frame_done <= tx_en & ~en_n;
            half       <= ~speed & take;
            if (take) hi <= data_in[7:4];

            if (half)      txd <= {4'b0000, hi};
            else if (take) txd <= speed ? data_in : {4'b0000, data_in[3:0]};
            else           txd <= 8'h00;
        end
    end

endmodule

`default_nettype wire
