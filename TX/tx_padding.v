// tx_padding - Pads short frames to MIN_FRAME_LEN body octets.

`timescale 1ns/1ps
`default_nettype none

module tx_padding #(
    parameter DATA_WIDTH    = 8,
    parameter MIN_FRAME_LEN = 60
)(

    input  wire                  tx_clk,
    input  wire                  rst_n,

    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  valid_in,
    input  wire                  sof_in,
    input  wire                  eof_in,
    output wire                  ready_in,

    output reg  [DATA_WIDTH-1:0] data_out,
    output reg                   valid_out,
    output reg                   sof_out,
    output reg                   eof_out,
    input  wire                  ready_out
);

    localparam ST_IDLE    = 2'b00;
    localparam ST_DATA    = 2'b01;
    localparam ST_PADDING = 2'b10;

    reg [1:0]  state_reg;
    reg [15:0] byte_count;

    assign ready_in = (state_reg == ST_IDLE || state_reg == ST_DATA) && ready_out;

    always @(posedge tx_clk or negedge rst_n) begin
        if (!rst_n) begin

            state_reg  <= ST_IDLE;
            byte_count <= 16'd0;
            data_out   <= {DATA_WIDTH{1'b0}};
            valid_out  <= 1'b0;
            sof_out    <= 1'b0;
            eof_out    <= 1'b0;

        end else if (!ready_out && valid_out) begin

            state_reg  <= state_reg;
            byte_count <= byte_count;
            data_out   <= data_out;
            valid_out  <= valid_out;
            sof_out    <= sof_out;
            eof_out    <= eof_out;

        end else begin

            sof_out <= 1'b0;
            eof_out <= 1'b0;

            case (state_reg)

                ST_IDLE: begin
                    valid_out <= 1'b0;

                    if (valid_in && sof_in && ready_out) begin

                        data_out   <= data_in;
                        valid_out  <= 1'b1;
                        sof_out    <= 1'b1;
                        byte_count <= 16'd1;

                        if (eof_in) begin
                            if (16'd1 >= MIN_FRAME_LEN) begin

                                eof_out   <= 1'b1;
                                state_reg <= ST_IDLE;
                            end else begin

                                state_reg <= ST_PADDING;
                            end
                        end else begin

                            state_reg <= ST_DATA;
                        end
                    end
                end

                ST_DATA: begin
                    if (valid_in && ready_out) begin
                        data_out   <= data_in;
                        valid_out  <= 1'b1;
                        byte_count <= byte_count + 1'b1;

                        if (eof_in) begin

                            if ((byte_count + 1'b1) >= MIN_FRAME_LEN) begin

                                eof_out   <= 1'b1;
                                state_reg <= ST_IDLE;
                            end else begin

                                state_reg <= ST_PADDING;
                            end
                        end

                    end else if (!valid_in) begin

                        valid_out <= 1'b0;
                    end

                end

                ST_PADDING: begin
                    if (ready_out) begin
                        data_out   <= {DATA_WIDTH{1'b0}};
                        valid_out  <= 1'b1;
                        byte_count <= byte_count + 1'b1;

                        if ((byte_count + 1'b1) >= MIN_FRAME_LEN) begin

                            eof_out   <= 1'b1;
                            state_reg <= ST_IDLE;
                        end

                    end
                end

                default: state_reg <= ST_IDLE;

            endcase
        end
    end

endmodule

`default_nettype wire

