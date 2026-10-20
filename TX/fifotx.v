`timescale 1ns / 1ps
`default_nettype none

module tx_fifo #(
    parameter integer ADDR_W = 11
)(
    input  wire             wr_clk,
    input  wire             wr_rst_n,
    input  wire [7:0]       s_axis_tdata,
    input  wire             s_axis_tvalid,
    output wire             s_axis_tready,
    input  wire             s_axis_tlast,
    output reg              frame_drop_out,

    input  wire             rd_clk,
    input  wire             rd_rst_n,
    output wire [7:0]       data_out,
    output reg              valid_out,
    input  wire             ready_out,
    output wire             last_out,
    output wire             frame_avail_out
);

    localparam integer    DEPTH    = (1 << ADDR_W);
    localparam [ADDR_W:0] FULL_LVL = {1'b1, {ADDR_W{1'b0}}};
    localparam [ADDR_W:0] ONE      = {{ADDR_W{1'b0}}, 1'b1};

    function [ADDR_W:0] bin2gray;
        input [ADDR_W:0] b;
        bin2gray = b ^ (b >> 1);
    endfunction

    function [ADDR_W:0] gray2bin;
        input [ADDR_W:0] g;
        integer          i;
        begin
            gray2bin[ADDR_W] = g[ADDR_W];
            for (i = ADDR_W - 1; i >= 0; i = i - 1)
                gray2bin[i] = gray2bin[i+1] ^ g[i];
        end
    endfunction

    reg [8:0] mem [0:DEPTH-1];
    reg [8:0] mem_q;

    reg [ADDR_W:0] wr_bin, wr_cmt_bin, wr_frm, wr_frm_gray;
    reg            dropping;

    reg [ADDR_W:0] rd_bin, rd_gray, rd_frm;
    reg            streaming;

    wire rst_all_n = wr_rst_n & rd_rst_n;

    (* ASYNC_REG = "TRUE" *) reg [1:0] wr_rst_sr;
    (* ASYNC_REG = "TRUE" *) reg [1:0] rd_rst_sr;

    always @(posedge wr_clk or negedge rst_all_n)
        if (!rst_all_n) wr_rst_sr <= 2'b00;
        else            wr_rst_sr <= {wr_rst_sr[0], 1'b1};

    always @(posedge rd_clk or negedge rst_all_n)
        if (!rst_all_n) rd_rst_sr <= 2'b00;
        else            rd_rst_sr <= {rd_rst_sr[0], 1'b1};

    wire wr_rst_sn = wr_rst_sr[1];
    wire rd_rst_sn = rd_rst_sr[1];

    (* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] rd_gray_wr1,     rd_gray_wr2;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] wr_frm_gray_rd1, wr_frm_gray_rd2;

    always @(posedge wr_clk or negedge wr_rst_sn)
        if (!wr_rst_sn) {rd_gray_wr2, rd_gray_wr1} <= 0;
        else            {rd_gray_wr2, rd_gray_wr1} <= {rd_gray_wr1, rd_gray};

    always @(posedge rd_clk or negedge rd_rst_sn)
        if (!rd_rst_sn) {wr_frm_gray_rd2, wr_frm_gray_rd1} <= 0;
        else            {wr_frm_gray_rd2, wr_frm_gray_rd1} <= {wr_frm_gray_rd1, wr_frm_gray};

    wire [ADDR_W:0] rd_bin_wr = gray2bin(rd_gray_wr2);
    wire            full      = ((wr_bin - rd_bin_wr) == FULL_LVL);
    wire            deadlock  = full && (wr_cmt_bin == rd_bin_wr);

    assign s_axis_tready = !full || dropping;

    wire [ADDR_W:0] wr_bin_next = wr_bin + ONE;
    wire [ADDR_W:0] wr_frm_next = wr_frm + ONE;
    wire            wr_en       = s_axis_tvalid && s_axis_tready && !dropping;

    always @(posedge wr_clk)
        if (wr_en) mem[wr_bin[ADDR_W-1:0]] <= {s_axis_tlast, s_axis_tdata};

    always @(posedge wr_clk or negedge wr_rst_sn) begin
        if (!wr_rst_sn) begin
            wr_bin         <= 0;
            wr_cmt_bin     <= 0;
            wr_frm         <= 0;
            wr_frm_gray    <= 0;
            dropping       <= 1'b0;
            frame_drop_out <= 1'b0;
        end else begin
            frame_drop_out <= 1'b0;

            if (dropping) begin
                if (s_axis_tvalid && s_axis_tlast) dropping <= 1'b0;
            end else if (deadlock) begin
                wr_bin         <= wr_cmt_bin;
                dropping       <= 1'b1;
                frame_drop_out <= 1'b1;
            end else if (wr_en) begin
                wr_bin <= wr_bin_next;
                if (s_axis_tlast) begin
                    wr_cmt_bin  <= wr_bin_next;
                    wr_frm      <= wr_frm_next;
                    wr_frm_gray <= bin2gray(wr_frm_next);
                end
            end
        end
    end

    wire [ADDR_W:0] wr_frm_rd = gray2bin(wr_frm_gray_rd2);
    wire            frame_rdy = (wr_frm_rd != rd_frm);
    wire [ADDR_W:0] rd_bin_next = rd_bin + ONE;

    wire start = !streaming && !valid_out && frame_rdy;
    wire cont  = streaming && !(valid_out && last_out) && (!valid_out || ready_out);
    wire load  = start || cont;

    always @(posedge rd_clk)
        if (load) mem_q <= mem[rd_bin[ADDR_W-1:0]];

    always @(posedge rd_clk or negedge rd_rst_sn) begin
        if (!rd_rst_sn) begin
            rd_bin    <= 0;
            rd_gray   <= 0;
            rd_frm    <= 0;
            streaming <= 1'b0;
            valid_out <= 1'b0;
        end else begin
            if (load) begin
                rd_bin  <= rd_bin_next;
                rd_gray <= bin2gray(rd_bin_next);
            end

            if (start) begin
                streaming <= 1'b1;
                rd_frm    <= rd_frm + ONE;
            end else if (valid_out && last_out && ready_out) begin
                streaming <= 1'b0;
            end

            if (load)                         valid_out <= 1'b1;
            else if (valid_out && ready_out)  valid_out <= 1'b0;
        end
    end

    assign data_out        = mem_q[7:0];
    assign last_out        = mem_q[8];
    assign frame_avail_out = frame_rdy || streaming || valid_out;

endmodule

`default_nettype wire
