// tx_gmii_mii - GMII/MII transmit pin driver.

`timescale 1ns / 1ps
`default_nettype none

module tx_gmii_mii #(

    parameter integer ERR_CYCLES = 2
)(

    input  wire       tx_clk,

    input  wire       rst_n,

    input  wire       speed_select,

    input  wire [7:0] data_in,
    input  wire       valid_in,
    input  wire       last_in,

    input  wire       err_in,
    output wire       ready_in,

    output reg  [7:0] gmii_txd,

    output reg        gmii_tx_en,
    output reg        gmii_tx_er,

    output reg        frame_done_out,

    output reg        underrun_out
);

    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_OCTET = 3'd1;
    localparam [2:0] ST_HI    = 3'd2;
    localparam [2:0] ST_EOF   = 3'd3;
    localparam [2:0] ST_ABORT = 3'd4;
    localparam [2:0] ST_DRAIN = 3'd5;

    localparam integer ERR_LOAD_I = ERR_CYCLES - 1;
    localparam [1:0]   ERR_LOAD   = ERR_LOAD_I[1:0];

    generate
        if (ERR_CYCLES < 1 || ERR_CYCLES > 4) begin : gen_err_cycles_range
            ERR_CYCLES_must_be_1_to_4 illegal_parameter_value ();
        end
    endgenerate

    reg [2:0] state;
    reg       mode_q;
    reg [3:0] octet_hi;
    reg       err_q;
    reg       last_q;
    reg [1:0] err_cnt;

    assign ready_in = (state == ST_IDLE ) ||
                       (state == ST_OCTET) ||
                       (state == ST_DRAIN);

    always @(posedge tx_clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            mode_q         <= 1'b0;
            octet_hi       <= 4'd0;
            err_q          <= 1'b0;
            last_q         <= 1'b0;
            err_cnt        <= 2'd0;
            gmii_txd       <= 8'd0;
            gmii_tx_en     <= 1'b0;
            gmii_tx_er     <= 1'b0;
            frame_done_out <= 1'b0;
            underrun_out   <= 1'b0;
        end else begin

            frame_done_out <= 1'b0;
            underrun_out   <= 1'b0;

            case (state)

                ST_IDLE: begin
                    mode_q <= speed_select;

                    if (valid_in) begin
                        if (speed_select) begin

                            gmii_txd   <= data_in;
                            gmii_tx_en <= 1'b1;
                            gmii_tx_er <= err_in;
                            state      <= last_in ? ST_EOF : ST_OCTET;
                        end else begin

                            gmii_txd   <= {4'b0000, data_in[3:0]};
                            gmii_tx_en <= 1'b1;
                            gmii_tx_er <= err_in;
                            octet_hi   <= data_in[7:4];
                            err_q      <= err_in;
                            last_q     <= last_in;
                            state      <= ST_HI;
                        end
                    end else begin
                        gmii_txd   <= 8'd0;
                        gmii_tx_en <= 1'b0;
                        gmii_tx_er <= 1'b0;
                    end
                end

                ST_OCTET: begin
                    if (valid_in) begin
                        if (mode_q) begin
                            gmii_txd   <= data_in;
                            gmii_tx_en <= 1'b1;
                            gmii_tx_er <= err_in;
                            state      <= last_in ? ST_EOF : ST_OCTET;
                        end else begin
                            gmii_txd   <= {4'b0000, data_in[3:0]};
                            gmii_tx_en <= 1'b1;
                            gmii_tx_er <= err_in;
                            octet_hi   <= data_in[7:4];
                            err_q      <= err_in;
                            last_q     <= last_in;
                            state      <= ST_HI;
                        end
                    end else begin

                        gmii_txd     <= 8'd0;
                        gmii_tx_en   <= 1'b1;
                        gmii_tx_er   <= 1'b1;
                        err_cnt      <= ERR_LOAD;
                        underrun_out <= 1'b1;
                        state        <= ST_ABORT;
                    end
                end

                ST_HI: begin
                    gmii_txd   <= {4'b0000, octet_hi};
                    gmii_tx_en <= 1'b1;
                    gmii_tx_er <= err_q;
                    state      <= last_q ? ST_EOF : ST_OCTET;
                end

                ST_EOF: begin
                    gmii_txd       <= 8'd0;
                    gmii_tx_en     <= 1'b0;
                    gmii_tx_er     <= 1'b0;
                    frame_done_out <= 1'b1;
                    err_q          <= 1'b0;
                    last_q         <= 1'b0;
                    state          <= ST_IDLE;
                end

                ST_ABORT: begin
                    if (err_cnt == 2'd0) begin
                        gmii_txd   <= 8'd0;
                        gmii_tx_en <= 1'b0;
                        gmii_tx_er <= 1'b0;
                        state      <= ST_DRAIN;
                    end else begin
                        gmii_tx_en <= 1'b1;
                        gmii_tx_er <= 1'b1;
                        err_cnt    <= err_cnt - 2'd1;
                    end
                end

                ST_DRAIN: begin
                    mode_q     <= speed_select;
                    gmii_txd   <= 8'd0;
                    gmii_tx_en <= 1'b0;
                    gmii_tx_er <= 1'b0;
                    if (valid_in && last_in) state <= ST_IDLE;
                end

                default: begin
                    gmii_txd   <= 8'd0;
                    gmii_tx_en <= 1'b0;
                    gmii_tx_er <= 1'b0;
                    state      <= ST_IDLE;
                end

            endcase
        end
    end

endmodule

`default_nettype wire

