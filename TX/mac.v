`timescale 1ns / 1ps
`default_nettype none

module rx_mac_top #(
    parameter integer DATA_W        = 8,
    parameter integer FIFO_ADDR_W   = 11,
    parameter integer MIN_FRAME_LEN = 60,
    parameter integer MAX_FRAME_LEN = 1514,
    parameter [7:0]   PREAMBLE_BYTE = 8'h55,
    parameter [7:0]   SFD_BYTE      = 8'hD5,
    parameter integer PRE_MAX       = 32
)(
    input  wire                 rx_clk,
    input  wire                 rx_rst_n,
    input  wire                 speed_select,

    input  wire [7:0]           gmii_rxd,
    input  wire                 gmii_rx_dv,
    input  wire                 gmii_rx_er,

    input  wire                 rd_clk,
    input  wire                 rd_rst_n,
    output wire [DATA_W-1:0]    m_axis_tdata,
    output wire                 m_axis_tvalid,
    input  wire                 m_axis_tready,
    output wire                 m_axis_tlast,
    output wire                 frame_avail_out,

    output wire                 frame_rcvd_out,
    output wire                 frame_drop_out,
    output wire                 overflow_out,
    output wire                 crc_err_out,
    output wire                 len_err_out,
    output wire                 phy_err_out,
    output wire                 no_sfd_out,
    output wire                 sfd_seen_out,
    output wire                 frame_ok_out,
    output wire [10:0]          frame_len_out
);

    wire [7:0] phy_data;
    wire       phy_valid;
    wire       phy_last;
    wire       phy_err;
    wire       phy_frame_done;

    wire [7:0] pre_data;
    wire       pre_valid;
    wire       pre_last;
    wire       pre_err;

    wire [7:0] fcs_data;
    wire       fcs_valid;
    wire       fcs_last;
    wire       fcs_crc_ok;
    wire       fcs_crc_err;

    phy_rx_if u_phy_rx_if (
        .rx_clk         (rx_clk),
        .rst_n          (rx_rst_n),
        .speed_select   (speed_select),

        .gmii_rxd       (gmii_rxd),
        .gmii_rx_dv     (gmii_rx_dv),
        .gmii_rx_er     (gmii_rx_er),

        .data_out       (phy_data),
        .valid_out      (phy_valid),
        .last_out       (phy_last),
        .rx_err_out     (phy_err),
        .frame_done_out (phy_frame_done)
    );

    sfd_strip #(
        .PREAMBLE_BYTE (PREAMBLE_BYTE),
        .SFD_BYTE      (SFD_BYTE),
        .PRE_MAX       (PRE_MAX)
    ) u_sfd_strip (
        .rx_clk       (rx_clk),
        .rst_n        (rx_rst_n),

        .data_in      (phy_data),
        .valid_in     (phy_valid),
        .last_in      (phy_last),
        .rx_err_in    (phy_err),

        .data_out     (pre_data),
        .valid_out    (pre_valid),
        .last_out     (pre_last),
        .rx_err_out   (pre_err),

        .sfd_seen_out (sfd_seen_out),
        .frame_ok_out (frame_ok_out),
        .no_sfd_out   (no_sfd_out)
    );

    frame_check #(
        .MIN_FRAME_LEN (MIN_FRAME_LEN),
        .MAX_FRAME_LEN (MAX_FRAME_LEN)
    ) u_frame_check (
        .rx_clk        (rx_clk),
        .rst_n         (rx_rst_n),

        .data_in       (pre_data),
        .valid_in      (pre_valid),
        .last_in       (pre_last),
        .rx_err_in     (pre_err),

        .data_out      (fcs_data),
        .valid_out     (fcs_valid),
        .last_out      (fcs_last),

        .crc_ok_out    (fcs_crc_ok),
        .crc_err_out   (crc_err_out),
        .len_err_out   (len_err_out),
        .phy_err_out   (phy_err_out),

        .frame_len_out (frame_len_out)
    );

    assign fcs_crc_err = crc_err_out;

    rx_frame_buf #(
        .DATA_W (DATA_W),
        .ADDR_W (FIFO_ADDR_W)
    ) u_rx_frame_buf (
        .wr_clk          (rx_clk),
        .wr_rst_n        (rx_rst_n),
        .data_in         (fcs_data),
        .valid_in        (fcs_valid),
        .last_in         (fcs_last),

        .crc_ok_in       (fcs_crc_ok),
        .crc_err_in      (fcs_crc_err),

        .frame_cmt_out   (frame_rcvd_out),
        .frame_drop_out  (frame_drop_out),
        .overflow_out    (overflow_out),

        .rd_clk          (rd_clk),
        .rd_rst_n        (rd_rst_n),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tlast    (m_axis_tlast),
        .frame_avail_out (frame_avail_out)
    );

    /* verilator lint_off UNUSEDSIGNAL */
    wire phy_frame_done_unused = phy_frame_done;
    /* verilator lint_on UNUSEDSIGNAL */

endmodule

`default_nettype wire