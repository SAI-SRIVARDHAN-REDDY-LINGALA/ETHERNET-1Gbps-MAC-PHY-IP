`timescale 1ns / 1ps
`default_nettype none

module rx_crc #(
    parameter integer MIN_LEN = 60,
    parameter integer MAX_LEN = 1514
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  data_in,
    input  wire        valid_in,
    input  wire        last_in,
    input  wire        err_in,

    output reg  [7:0]  data_out,
    output reg         valid_out,
    output reg         last_out,

    output reg         ok_out,
    output reg         crc_err_out,
    output reg         len_err_out,
    output reg         phy_err_out,
    output reg  [10:0] len_out
);

    reg [31:0] dly;
    reg [11:0] cnt;
    reg        busy, done, phy_err;

    wire take  = valid_in && !done;
    wire good;

    crc u_crc (
        .clk   (clk),
        .rst_n (rst_n),
        .init  (!busy),
        .valid (take),
        .data  (data_in),
        .value (),
        .good  (good)
    );

    wire len_ng = (cnt < MIN_LEN + 4) || (cnt > MAX_LEN + 4);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dly         <= 32'd0;
            cnt         <= 12'd0;
            busy        <= 1'b0;
            done        <= 1'b0;
            phy_err     <= 1'b0;
            data_out    <= 8'd0;
            valid_out   <= 1'b0;
            last_out    <= 1'b0;
            ok_out      <= 1'b0;
            crc_err_out <= 1'b0;
            len_err_out <= 1'b0;
            phy_err_out <= 1'b0;
            len_out     <= 11'd0;
        end else begin
            valid_out   <= 1'b0;
            last_out    <= 1'b0;
            ok_out      <= 1'b0;
            crc_err_out <= 1'b0;
            len_err_out <= 1'b0;
            phy_err_out <= 1'b0;

            if (done) begin
                done    <= 1'b0;
                len_out <= (cnt >= 4) ? (cnt - 12'd4) : 11'd0;

                if (good && !len_ng && !phy_err)
                    ok_out <= 1'b1;
                else begin
                    crc_err_out <= 1'b1;
                    len_err_out <= len_ng;
                    phy_err_out <= phy_err;
                end
            end else if (valid_in) begin
                busy <= !last_in;
                done <= last_in;
                dly  <= {dly[23:0], data_in};

                if (!busy)
                    cnt <= 12'd1;
                else if (cnt != 12'hFFF)
                    cnt <= cnt + 12'd1;

                if (busy && cnt >= 4) begin
                    data_out  <= dly[31:24];
                    valid_out <= 1'b1;
                    last_out  <= last_in;
                end

                if (last_in) phy_err <= err_in;
            end
        end
    end

endmodule

`default_nettype wire
