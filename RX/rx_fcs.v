// rx_fcs - Verifies CRC-32 by residue, strips FCS, checks frame length.

`timescale 1ns / 1ps
`default_nettype none

module rx_fcs #(

    parameter integer MIN_FRAME_LEN = 60,

    parameter integer MAX_FRAME_LEN = 1514
)(

    input  wire        rx_clk,
    input  wire        rst_n,

    input  wire [7:0]  data_in,
    input  wire        valid_in,
    input  wire        last_in,
    input  wire        rx_err_in,

    output reg  [7:0]  data_out,
    output reg         valid_out,
    output reg         last_out,

    output reg         crc_ok_out,
    output reg         crc_err_out,
    output reg         len_err_out,
    output reg         phy_err_out,

    output reg  [10:0] frame_len_out
);

    localparam [31:0] CRC_RESIDUE = 32'hDEBB20E3;

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_RUN  = 2'd1;
    localparam [1:0] ST_DONE = 2'd2;

    reg [1:0] state;

    reg [7:0] pipe0, pipe1, pipe2, pipe3;
    reg [2:0] fill;

    reg  [31:0] crc_reg;
    wire [31:0] crc_next;

    crc32_parallel u_crc32 (
        .data_in (data_in),
        .crc_in  (crc_reg),
        .crc_out (crc_next)
    );

    reg [10:0] body_cnt;
    reg        phy_err_q;

    wire runt   = (body_cnt < MIN_FRAME_LEN[10:0]);
    wire giant  = (body_cnt > MAX_FRAME_LEN[10:0]);
    wire len_ng = runt || giant;

    wire crc_ng = (crc_reg != CRC_RESIDUE);

    always @(posedge rx_clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            pipe0         <= 8'd0;
            pipe1         <= 8'd0;
            pipe2         <= 8'd0;
            pipe3         <= 8'd0;
            fill          <= 3'd0;
            crc_reg       <= 32'hFFFF_FFFF;
            body_cnt      <= 11'd0;
            phy_err_q     <= 1'b0;
            data_out      <= 8'd0;
            valid_out     <= 1'b0;
            last_out      <= 1'b0;
            crc_ok_out    <= 1'b0;
            crc_err_out   <= 1'b0;
            len_err_out   <= 1'b0;
            phy_err_out   <= 1'b0;
            frame_len_out <= 11'd0;
        end else begin

            valid_out   <= 1'b0;
            last_out    <= 1'b0;
            crc_ok_out  <= 1'b0;
            crc_err_out <= 1'b0;
            len_err_out <= 1'b0;
            phy_err_out <= 1'b0;

            case (state)

                ST_IDLE: begin
                    if (valid_in) begin

                        crc_reg   <= crc_seed_step(data_in);
                        pipe0     <= data_in;
                        fill      <= 3'd1;
                        body_cnt  <= 11'd0;
                        phy_err_q <= 1'b0;

                        if (last_in) begin

                            phy_err_q <= rx_err_in;
                            state     <= ST_DONE;
                        end else begin
                            state <= ST_RUN;
                        end
                    end
                end

                ST_RUN: begin
                    if (valid_in) begin
                        crc_reg <= crc_next;

                        pipe3 <= pipe2;
                        pipe2 <= pipe1;
                        pipe1 <= pipe0;
                        pipe0 <= data_in;

                        if (fill == 3'd4) begin

                            data_out  <= pipe3;
                            valid_out <= 1'b1;
                            last_out  <= last_in;
                            body_cnt  <= body_cnt + 11'd1;
                        end else begin
                            fill <= fill + 3'd1;
                        end

                        if (last_in) begin
                            phy_err_q <= rx_err_in;
                            state     <= ST_DONE;
                        end
                    end
                end

                ST_DONE: begin
                    frame_len_out <= body_cnt;

                    if (!crc_ng && !len_ng && !phy_err_q) begin
                        crc_ok_out <= 1'b1;
                    end else begin
                        crc_err_out <= 1'b1;
                        if (len_ng)    len_err_out <= 1'b1;
                        if (phy_err_q) phy_err_out <= 1'b1;
                    end

                    crc_reg  <= 32'hFFFF_FFFF;
                    fill     <= 3'd0;
                    state    <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                    fill  <= 3'd0;
                end

            endcase
        end
    end

    function [31:0] crc_seed_step;
        input [7:0] d;
        reg   [31:0] c;
        integer i;
        begin
            c = 32'hFFFF_FFFF;
            for (i = 0; i < 8; i = i + 1) begin
                if ((c[0] ^ d[i]) == 1'b1)
                    c = {1'b0, c[31:1]} ^ 32'hEDB88320;
                else
                    c = {1'b0, c[31:1]};
            end
            crc_seed_step = c;
        end
    endfunction

endmodule

`default_nettype wire

