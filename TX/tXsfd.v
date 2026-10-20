`timescale 1ns / 1ps
`default_nettype none

module tx_sfd #(
    parameter integer MIN_LEN = 60
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire       ready,

    input  wire [7:0] in_data,
    input  wire       in_valid,
    input  wire       in_last,
    output wire       in_ready,

    output reg  [7:0] data,
    output reg        valid,
    output reg        body,
    output reg        last
);

    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] PRE  = 2'd1;
    localparam [1:0] BODY = 2'd2;
    localparam [1:0] PAD  = 2'd3;

    reg [1:0] state;
    reg [2:0] n;
    reg [7:0] cnt;

    wire enough = (cnt >= MIN_LEN - 1);
    wire xfer   = valid && ready;

    always @(*) begin
        data  = 8'h00;
        valid = 1'b0;
        body  = 1'b0;
        last  = 1'b0;
        case (state)
            PRE: begin
                data  = (n == 3'd7) ? 8'hD5 : 8'h55;
                valid = 1'b1;
            end
            BODY: begin
                data  = in_data;
                valid = in_valid;
                body  = 1'b1;
                last  = in_last && enough;
            end
            PAD: begin
                valid = 1'b1;
                body  = 1'b1;
                last  = enough;
            end
            default: ;
        endcase
    end

    assign in_ready = ready && (state == BODY);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            n     <= 3'd0;
            cnt   <= 8'd0;
        end else begin
            case (state)
                IDLE: if (start) begin
                    n     <= 3'd0;
                    cnt   <= 8'd0;
                    state <= PRE;
                end

                PRE: if (xfer) begin
                    n <= n + 3'd1;
                    if (n == 3'd7) state <= BODY;
                end

                BODY: if (xfer) begin
                    if (!enough) cnt <= cnt + 8'd1;
                    if (in_last) state <= enough ? IDLE : PAD;
                end

                PAD: if (xfer) begin
                    if (!enough) cnt <= cnt + 8'd1;
                    else         state <= IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
