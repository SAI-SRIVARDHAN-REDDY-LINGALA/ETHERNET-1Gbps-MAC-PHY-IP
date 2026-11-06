// tx_fcs - TX CRC-32 accumulator and FCS output latch.

`timescale 1ns/1ps

module tx_fcs (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        init,
    input  wire        data_valid,
    input  wire [7:0]  data_in,
    output reg  [31:0] fcs_out,
    output reg         fcs_valid
);

    reg  [31:0] crc_reg;
    wire [31:0] crc_next;
    reg         data_valid_d;

    crc32_parallel u_crc32 (
        .data_in (data_in),
        .crc_in  (crc_reg),
        .crc_out (crc_next)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_valid_d <= 1'b0;
        else
            data_valid_d <= data_valid;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg   <= 32'hFFFF_FFFF;
            fcs_out   <= 32'h0;
            fcs_valid <= 1'b0;
        end else begin
            fcs_valid <= 1'b0;

            if (init) begin

                crc_reg <= 32'hFFFF_FFFF;
            end else if (data_valid) begin

                crc_reg <= crc_next;
            end else if (data_valid_d && !data_valid) begin

                fcs_out   <= ~crc_reg;
                fcs_valid <= 1'b1;
            end
        end
    end

endmodule

