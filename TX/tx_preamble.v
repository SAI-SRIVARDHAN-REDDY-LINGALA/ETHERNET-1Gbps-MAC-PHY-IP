// tx_preamble - Generates the preamble and SFD.

`timescale 1ns / 1ps
`default_nettype none

module tx_preamble #(
    parameter integer DATA_WIDTH     = 8,
    parameter [7:0]   PREAMBLE_BYTE  = 8'h55,
    parameter [7:0]   SFD_BYTE       = 8'hD5,
    parameter integer PREAMBLE_COUNT = 7
)(
    input  wire                  tx_clk,

    input  wire                  rst_n,
    input  wire                  start_in,
    input  wire                  ready_out,
    output reg  [DATA_WIDTH-1:0] data_out,
    output reg                   valid_out,
    output reg                   sfd_done_out
);

    localparam [1:0] ST_IDLE     = 2'd0;
    localparam [1:0] ST_PREAMBLE = 2'd1;
    localparam [1:0] ST_SFD      = 2'd2;

    reg [1:0] state;

    reg [3:0] byte_count;

    wire xfer = valid_out & ready_out;

    always @(posedge tx_clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            byte_count   <= 4'd0;
            data_out     <= {DATA_WIDTH{1'b0}};
            valid_out    <= 1'b0;
            sfd_done_out <= 1'b0;
        end else begin

            sfd_done_out <= 1'b0;

            case (state)

                ST_IDLE: begin
                    if (start_in) begin
                        data_out   <= PREAMBLE_BYTE;
                        valid_out  <= 1'b1;
                        byte_count <= 4'd1;
                        state      <= ST_PREAMBLE;
                    end else begin
                        valid_out  <= 1'b0;
                        byte_count <= 4'd0;
                    end
                end

                ST_PREAMBLE: begin
                    if (xfer) begin
                        if (byte_count == PREAMBLE_COUNT[3:0]) begin
                            data_out <= SFD_BYTE;
                            state    <= ST_SFD;
                        end else begin
                            data_out   <= PREAMBLE_BYTE;
                            byte_count <= byte_count + 4'd1;
                        end
                    end
                end

                ST_SFD: begin
                    if (xfer) begin
                        data_out     <= {DATA_WIDTH{1'b0}};
                        valid_out    <= 1'b0;
                        sfd_done_out <= 1'b1;
                        byte_count   <= 4'd0;
                        state        <= ST_IDLE;
                    end
                end

                default: begin
                    state      <= ST_IDLE;
                    valid_out  <= 1'b0;
                    byte_count <= 4'd0;
                end

            endcase
        end
    end

endmodule

`default_nettype wire

