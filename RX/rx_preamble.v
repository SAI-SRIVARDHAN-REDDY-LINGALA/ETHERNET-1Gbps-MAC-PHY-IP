// rx_preamble - Strips preamble and SFD.

`timescale 1ns / 1ps
`default_nettype none

module rx_preamble #(
    parameter [7:0]   PREAMBLE_BYTE = 8'h55,
    parameter [7:0]   SFD_BYTE      = 8'hD5,

    parameter integer PRE_MAX       = 32
)(

    input  wire       rx_clk,
    input  wire       rst_n,

    input  wire [7:0] data_in,
    input  wire       valid_in,
    input  wire       last_in,
    input  wire       rx_err_in,

    output reg  [7:0] data_out,
    output reg        valid_out,
    output reg        last_out,
    output reg        rx_err_out,

    output reg        sfd_seen_out,
    output reg        frame_ok_out,
    output reg        no_sfd_out
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_PRE  = 2'd1;
    localparam [1:0] ST_DATA = 2'd2;
    localparam [1:0] ST_DUMP = 2'd3;

    reg [1:0] state;

    reg [5:0] pre_cnt;

    always @(posedge rx_clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            pre_cnt      <= 6'd0;
            data_out     <= 8'd0;
            valid_out    <= 1'b0;
            last_out     <= 1'b0;
            rx_err_out   <= 1'b0;
            sfd_seen_out <= 1'b0;
            frame_ok_out <= 1'b0;
            no_sfd_out   <= 1'b0;
        end else begin

            valid_out    <= 1'b0;
            last_out     <= 1'b0;
            rx_err_out   <= 1'b0;
            sfd_seen_out <= 1'b0;
            frame_ok_out <= 1'b0;
            no_sfd_out   <= 1'b0;

            case (state)

                ST_IDLE: begin
                    pre_cnt <= 6'd0;

                    if (valid_in) begin
                        if (data_in == SFD_BYTE) begin

                            sfd_seen_out <= 1'b1;
                            state        <= last_in ? ST_IDLE : ST_DATA;
                            if (last_in) no_sfd_out <= 1'b1;
                        end else if (data_in == PREAMBLE_BYTE) begin
                            pre_cnt <= 6'd1;
                            state   <= last_in ? ST_IDLE : ST_PRE;
                            if (last_in) no_sfd_out <= 1'b1;
                        end else begin

                            state <= last_in ? ST_IDLE : ST_DUMP;
                            if (last_in) no_sfd_out <= 1'b1;
                        end
                    end
                end

                ST_PRE: begin
                    if (valid_in) begin
                        if (last_in) begin

                            no_sfd_out <= 1'b1;
                            state      <= ST_IDLE;
                        end else if (data_in == SFD_BYTE) begin
                            sfd_seen_out <= 1'b1;
                            state        <= ST_DATA;
                        end else if (data_in == PREAMBLE_BYTE) begin
                            if (pre_cnt >= PRE_MAX[5:0]) begin

                                state <= ST_DUMP;
                            end else begin
                                pre_cnt <= pre_cnt + 6'd1;
                            end
                        end else begin

                            state <= ST_DUMP;
                        end
                    end
                end

                ST_DATA: begin
                    if (valid_in) begin
                        data_out  <= data_in;
                        valid_out <= 1'b1;

                        if (last_in) begin
                            last_out     <= 1'b1;
                            rx_err_out   <= rx_err_in;
                            frame_ok_out <= 1'b1;
                            state        <= ST_IDLE;
                        end
                    end
                end

                ST_DUMP: begin
                    if (valid_in && last_in) begin
                        no_sfd_out <= 1'b1;
                        state      <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end

            endcase
        end
    end

endmodule

`default_nettype wire

