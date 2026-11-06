// rx_fifo - Asynchronous store-and-forward RX frame FIFO with commit/rewind.

`timescale 1ns / 1ps
`default_nettype none

module rx_fifo #(
    parameter integer DATA_W = 8,
    parameter integer ADDR_W = 11
)(

    input  wire                 wr_clk,
    input  wire                 wr_rst_n,

    input  wire [DATA_W-1:0]    data_in,
    input  wire                 valid_in,
    input  wire                 last_in,

    input  wire                 crc_ok_in,
    input  wire                 crc_err_in,

    output reg                  frame_cmt_out,
    output reg                  frame_drop_out,
    output reg                  overflow_out,

    input  wire                 rd_clk,
    input  wire                 rd_rst_n,
    output wire [DATA_W-1:0]    m_axis_tdata,
    output reg                  m_axis_tvalid,
    input  wire                 m_axis_tready,
    output wire                 m_axis_tlast,
    output wire                 frame_avail_out
);

    localparam integer      DEPTH    = (1 << ADDR_W);
    localparam [ADDR_W:0]   FULL_LVL = {1'b1, {ADDR_W{1'b0}}};
    localparam [ADDR_W:0]   ONE      = {{ADDR_W{1'b0}}, 1'b1};

    function [ADDR_W:0] bin2gray;
        input [ADDR_W:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    function [ADDR_W:0] gray2bin;
        input [ADDR_W:0] g;
        integer          i;
        reg [ADDR_W:0]   b;
        begin
            b[ADDR_W] = g[ADDR_W];
            for (i = ADDR_W - 1; i >= 0; i = i - 1) begin
                b[i] = b[i+1] ^ g[i];
            end
            gray2bin = b;
        end
    endfunction

    reg [DATA_W:0] mem [0:DEPTH-1];
    reg [DATA_W:0] mem_q;

    reg [ADDR_W:0] wr_bin;
    reg [ADDR_W:0] wr_cmt_bin;
    reg [ADDR_W:0] wr_frm;
    reg [ADDR_W:0] wr_frm_gray;
    reg            awaiting_verdict;
    reg            ovf_sticky;

    reg [ADDR_W:0] rd_bin;
    reg [ADDR_W:0] rd_gray;
    reg [ADDR_W:0] rd_frm;
    reg            streaming;

    wire rst_all_n = wr_rst_n & rd_rst_n;

    (* ASYNC_REG = "TRUE" *)
    reg [1:0] wr_rst_sr;
    (* ASYNC_REG = "TRUE" *)
    reg [1:0] rd_rst_sr;

    always @(posedge wr_clk or negedge rst_all_n) begin
        if (!rst_all_n) wr_rst_sr <= 2'b00;
        else            wr_rst_sr <= {wr_rst_sr[0], 1'b1};
    end

    always @(posedge rd_clk or negedge rst_all_n) begin
        if (!rst_all_n) rd_rst_sr <= 2'b00;
        else            rd_rst_sr <= {rd_rst_sr[0], 1'b1};
    end

    wire wr_rst_sn = wr_rst_sr[1];
    wire rd_rst_sn = rd_rst_sr[1];

    (* ASYNC_REG = "TRUE" *)
    reg [ADDR_W:0] rd_gray_wr1,      rd_gray_wr2;
    (* ASYNC_REG = "TRUE" *)
    reg [ADDR_W:0] wr_frm_gray_rd1,  wr_frm_gray_rd2;

    always @(posedge wr_clk or negedge wr_rst_sn) begin
        if (!wr_rst_sn) begin
            rd_gray_wr1 <= {(ADDR_W+1){1'b0}};
            rd_gray_wr2 <= {(ADDR_W+1){1'b0}};
        end else begin
            rd_gray_wr1 <= rd_gray;
            rd_gray_wr2 <= rd_gray_wr1;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_sn) begin
        if (!rd_rst_sn) begin
            wr_frm_gray_rd1 <= {(ADDR_W+1){1'b0}};
            wr_frm_gray_rd2 <= {(ADDR_W+1){1'b0}};
        end else begin
            wr_frm_gray_rd1 <= wr_frm_gray;
            wr_frm_gray_rd2 <= wr_frm_gray_rd1;
        end
    end

    wire [ADDR_W:0] rd_bin_wr = gray2bin(rd_gray_wr2);
    wire [ADDR_W:0] used      = wr_bin - rd_bin_wr;
    wire            full      = (used == FULL_LVL);

    wire [ADDR_W:0] wr_bin_next = wr_bin + ONE;
    wire [ADDR_W:0] wr_frm_next = wr_frm + ONE;

    wire            wr_en = valid_in && !ovf_sticky && !full;

    wire [ADDR_W:0] wr_bin_cmt = wr_en ? wr_bin_next : wr_bin;

    always @(posedge wr_clk) begin
        if (wr_en) begin
            mem[wr_bin[ADDR_W-1:0]] <= {last_in, data_in};
        end
    end

    always @(posedge wr_clk or negedge wr_rst_sn) begin
        if (!wr_rst_sn) begin
            wr_bin           <= {(ADDR_W+1){1'b0}};
            wr_cmt_bin       <= {(ADDR_W+1){1'b0}};
            wr_frm           <= {(ADDR_W+1){1'b0}};
            wr_frm_gray      <= {(ADDR_W+1){1'b0}};
            awaiting_verdict <= 1'b0;
            ovf_sticky       <= 1'b0;
            frame_cmt_out    <= 1'b0;
            frame_drop_out   <= 1'b0;
            overflow_out     <= 1'b0;
        end else begin
            frame_cmt_out  <= 1'b0;
            frame_drop_out <= 1'b0;
            overflow_out   <= 1'b0;

            if (valid_in) begin
                if (!ovf_sticky && !full) begin
                    wr_bin <= wr_bin_next;
                end else if (!ovf_sticky) begin

                    ovf_sticky <= 1'b1;
                end

                if (last_in) begin
                    awaiting_verdict <= 1'b1;
                end
            end

            if (awaiting_verdict && (crc_ok_in || crc_err_in)) begin
                awaiting_verdict <= 1'b0;
                ovf_sticky       <= 1'b0;

                if (crc_ok_in && !ovf_sticky) begin

                    wr_cmt_bin  <= wr_bin_cmt;
                    wr_frm      <= wr_frm_next;
                    wr_frm_gray <= bin2gray(wr_frm_next);

                    frame_cmt_out <= 1'b1;
                end else begin

                    wr_bin         <= wr_cmt_bin;
                    frame_drop_out <= 1'b1;
                    if (ovf_sticky) overflow_out <= 1'b1;
                end
            end
        end
    end

    wire [ADDR_W:0] wr_frm_rd = gray2bin(wr_frm_gray_rd2);

    wire            frame_rdy = (wr_frm_rd != rd_frm);

    wire [ADDR_W:0] rd_bin_next = rd_bin + ONE;
    wire [ADDR_W:0] rd_frm_next = rd_frm + ONE;

    wire            start = (!streaming) && (!m_axis_tvalid) && frame_rdy;
    wire            cont  = streaming && (!(m_axis_tvalid && m_axis_tlast)) &&
                            ((!m_axis_tvalid) || m_axis_tready);
    wire            load  = start || cont;

    always @(posedge rd_clk) begin
        if (load) begin
            mem_q <= mem[rd_bin[ADDR_W-1:0]];
        end
    end

    always @(posedge rd_clk or negedge rd_rst_sn) begin
        if (!rd_rst_sn) begin
            rd_bin        <= {(ADDR_W+1){1'b0}};
            rd_gray       <= {(ADDR_W+1){1'b0}};
            rd_frm        <= {(ADDR_W+1){1'b0}};
            streaming     <= 1'b0;
            m_axis_tvalid <= 1'b0;
        end else begin
            if (load) begin
                rd_bin  <= rd_bin_next;
                rd_gray <= bin2gray(rd_bin_next);
            end

            if (start) begin
                streaming <= 1'b1;
                rd_frm    <= rd_frm_next;
            end else if (streaming && m_axis_tvalid && m_axis_tlast &&
                         m_axis_tready) begin
                streaming <= 1'b0;
            end

            if (load) begin
                m_axis_tvalid <= 1'b1;
            end else if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end
        end
    end

    assign m_axis_tdata    = mem_q[DATA_W-1:0];
    assign m_axis_tlast    = mem_q[DATA_W];

    assign frame_avail_out = frame_rdy || streaming || m_axis_tvalid;

endmodule

`default_nettype wire

