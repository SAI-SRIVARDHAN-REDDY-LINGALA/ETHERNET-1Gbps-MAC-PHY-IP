// rx_gmii_mii - GMII/MII receive pin sampler; derives end-of-frame.

`timescale 1ns / 1ps
`default_nettype none

module rx_gmii_mii (

    input  wire       rx_clk,
    input  wire       rst_n,

    input  wire       speed_select,

    input  wire [7:0] gmii_rxd,
    input  wire       gmii_rx_dv,
    input  wire       gmii_rx_er,

    output reg  [7:0] data_out,
    output reg        valid_out,
    output reg        last_out,
    output reg        rx_err_out,

    output reg        frame_done_out
);

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_LO   = 3'd1;
    localparam [2:0] ST_HI   = 3'd2;
    localparam [2:0] ST_OCT  = 3'd3;
    localparam [2:0] ST_END  = 3'd4;

    reg [2:0] state;

    reg       mode_q;

    reg [3:0] oct_lo;

    reg [7:0] hold_d;
    reg       hold_v;

    reg       err_sticky;

    wire [7:0] gmii_oct = gmii_rxd;
    wire [7:0] mii_oct  = {gmii_rxd[3:0], oct_lo};

    always @(posedge rx_clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            mode_q         <= 1'b1;
            oct_lo         <= 4'd0;
            hold_d         <= 8'd0;
            hold_v         <= 1'b0;
            err_sticky     <= 1'b0;
            data_out       <= 8'd0;
            valid_out      <= 1'b0;
            last_out       <= 1'b0;
            rx_err_out     <= 1'b0;
            frame_done_out <= 1'b0;
        end else begin

            valid_out      <= 1'b0;
            last_out       <= 1'b0;
            rx_err_out     <= 1'b0;
            frame_done_out <= 1'b0;

            case (state)

                ST_IDLE: begin
                    hold_v     <= 1'b0;
                    err_sticky <= 1'b0;

                    if (gmii_rx_dv) begin
                        mode_q     <= speed_select;
                        err_sticky <= gmii_rx_er;

                        if (speed_select) begin

                            hold_d <= gmii_oct;
                            hold_v <= 1'b1;
                            state  <= ST_OCT;
                        end else begin

                            oct_lo <= gmii_rxd[3:0];
                            state  <= ST_HI;
                        end
                    end
                end

                ST_OCT: begin
                    if (gmii_rx_dv) begin
                        if (gmii_rx_er) err_sticky <= 1'b1;

                        if (hold_v) begin
                            data_out  <= hold_d;
                            valid_out <= 1'b1;
                        end
                        hold_d <= gmii_oct;
                        hold_v <= 1'b1;
                    end else begin

                        if (hold_v) begin
                            data_out   <= hold_d;
                            valid_out  <= 1'b1;
                            last_out   <= 1'b1;
                            rx_err_out <= err_sticky;
                        end
                        hold_v <= 1'b0;
                        state  <= ST_END;
                    end
                end

                ST_HI: begin
                    if (gmii_rx_dv) begin
                        if (gmii_rx_er) err_sticky <= 1'b1;

                        if (hold_v) begin
                            data_out  <= hold_d;
                            valid_out <= 1'b1;
                        end
                        hold_d <= mii_oct;
                        hold_v <= 1'b1;
                        state  <= ST_LO;
                    end else begin

                        if (hold_v) begin
                            data_out   <= hold_d;
                            valid_out  <= 1'b1;
                            last_out   <= 1'b1;
                            rx_err_out <= 1'b1;
                        end
                        err_sticky <= 1'b1;
                        hold_v     <= 1'b0;
                        state      <= ST_END;
                    end
                end

                ST_LO: begin
                    if (gmii_rx_dv) begin
                        if (gmii_rx_er) err_sticky <= 1'b1;
                        oct_lo <= gmii_rxd[3:0];
                        state  <= ST_HI;
                    end else begin

                        if (hold_v) begin
                            data_out   <= hold_d;
                            valid_out  <= 1'b1;
                            last_out   <= 1'b1;
                            rx_err_out <= err_sticky;
                        end
                        hold_v <= 1'b0;
                        state  <= ST_END;
                    end
                end

                ST_END: begin

                    if (hold_v) begin
                        data_out   <= hold_d;
                        valid_out  <= 1'b1;
                        last_out   <= 1'b1;
                        rx_err_out <= err_sticky;
                    end
                    frame_done_out <= 1'b1;
                    hold_v         <= 1'b0;
                    err_sticky     <= 1'b0;
                    state          <= ST_IDLE;
                end

                default: begin
                    state  <= ST_IDLE;
                    hold_v <= 1'b0;
                end

            endcase
        end
    end

endmodule

`default_nettype wire

