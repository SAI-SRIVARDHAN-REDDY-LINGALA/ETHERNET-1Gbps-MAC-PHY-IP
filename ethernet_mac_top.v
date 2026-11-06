// ethernet_mac_top - Combined full-duplex Ethernet MAC: AXI4-Stream host ports, GMII/MII pins, internal loopback.

`timescale 1ns / 1ps
`default_nettype none

module ethernet_mac_top #(

    parameter integer DATA_W        = 8,

    parameter integer TX_FIFO_ADDR_W = 11,
    parameter integer RX_FIFO_ADDR_W = 11,

    parameter integer MIN_FRAME_LEN = 60,

    parameter integer MAX_FRAME_LEN = 1514,

    parameter integer PREAMBLE_LEN  = 7,

    parameter integer IFG_BIT_TIMES = 96,

    parameter integer ERR_CYCLES    = 2,

    parameter         PREAMBLE_BYTE = 8'h55,
    parameter         SFD_BYTE      = 8'hD5,

    parameter integer PRE_MAX       = 32,

    parameter integer INT_LOOPBACK = 1
)(

    input  wire                 host_clk,
    input  wire                 host_rst_n,

    input  wire [DATA_W-1:0]    s_axis_tdata,
    input  wire                 s_axis_tvalid,
    output wire                 s_axis_tready,
    input  wire                 s_axis_tlast,

    output wire [DATA_W-1:0]    m_axis_tdata,
    output wire                 m_axis_tvalid,
    input  wire                 m_axis_tready,
    output wire                 m_axis_tlast,

    input  wire                 gtx_clk,
    input  wire                 gtx_rst_n,
    output wire [7:0]           gmii_txd,
    output wire                 gmii_tx_en,
    output wire                 gmii_tx_er,

    input  wire                 rx_clk,
    input  wire                 rx_rst_n,
    input  wire [7:0]           gmii_rxd,
    input  wire                 gmii_rx_dv,
    input  wire                 gmii_rx_er,

    input  wire                 speed_select,

    input  wire                 loopback_en,

    output wire                 tx_frame_drop_out,

    output wire                 tx_frame_sent_out,
    output wire                 tx_underrun_out,
    output wire                 tx_busy_out,

    output wire                 rx_frame_rcvd_out,
    output wire                 rx_frame_drop_out,
    output wire                 rx_overflow_out,
    output wire                 rx_crc_err_out,
    output wire                 rx_len_err_out,
    output wire                 rx_phy_err_out,
    output wire                 rx_no_sfd_out,
    output wire                 rx_sfd_seen_out,
    output wire                 rx_frame_ok_out,
    output wire [10:0]          rx_frame_len_out,

    output wire                 rx_frame_avail_out

);

    wire [7:0] tx_d;
    wire       tx_en;
    wire       tx_er;

    assign gmii_txd   = tx_d;
    assign gmii_tx_en = tx_en;
    assign gmii_tx_er = tx_er;

    tx_mac_controller #(
        .DATA_W        (DATA_W),
        .FIFO_ADDR_W   (TX_FIFO_ADDR_W),
        .MIN_FRAME_LEN (MIN_FRAME_LEN),
        .PREAMBLE_LEN  (PREAMBLE_LEN),
        .IFG_BIT_TIMES (IFG_BIT_TIMES),
        .ERR_CYCLES    (ERR_CYCLES)
    ) u_tx_mac (
        .wr_clk         (host_clk),
        .wr_rst_n       (host_rst_n),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .frame_drop_out (tx_frame_drop_out),

        .tx_clk         (gtx_clk),
        .tx_rst_n       (gtx_rst_n),
        .speed_select   (speed_select),
        .gmii_txd       (tx_d),
        .gmii_tx_en     (tx_en),
        .gmii_tx_er     (tx_er),

        .frame_sent_out (tx_frame_sent_out),
        .underrun_out   (tx_underrun_out),
        .tx_busy_out    (tx_busy_out)
    );

    wire [7:0] rx_d_int;
    wire       rx_dv_int;
    wire       rx_er_int;

    generate
    if (INT_LOOPBACK != 0) begin : g_loopback
        assign rx_d_int  = loopback_en ? tx_d  : gmii_rxd;
        assign rx_dv_int = loopback_en ? tx_en : gmii_rx_dv;
        assign rx_er_int = loopback_en ? tx_er : gmii_rx_er;
    end else begin : g_no_loopback

        assign rx_d_int  = gmii_rxd;
        assign rx_dv_int = gmii_rx_dv;
        assign rx_er_int = gmii_rx_er;
    end
    endgenerate

    rx_mac_controller #(
        .DATA_W        (DATA_W),
        .FIFO_ADDR_W   (RX_FIFO_ADDR_W),
        .MIN_FRAME_LEN (MIN_FRAME_LEN),
        .MAX_FRAME_LEN (MAX_FRAME_LEN),
        .PREAMBLE_BYTE (PREAMBLE_BYTE),
        .SFD_BYTE      (SFD_BYTE),
        .PRE_MAX       (PRE_MAX)
    ) u_rx_mac (
        .rx_clk          (rx_clk),
        .rx_rst_n        (rx_rst_n),
        .speed_select    (speed_select),
        .gmii_rxd        (rx_d_int),
        .gmii_rx_dv      (rx_dv_int),
        .gmii_rx_er      (rx_er_int),

        .rd_clk          (host_clk),
        .rd_rst_n        (host_rst_n),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tlast    (m_axis_tlast),
        .frame_avail_out (rx_frame_avail_out),

        .frame_rcvd_out  (rx_frame_rcvd_out),
        .frame_drop_out  (rx_frame_drop_out),
        .overflow_out    (rx_overflow_out),
        .crc_err_out     (rx_crc_err_out),
        .len_err_out     (rx_len_err_out),
        .phy_err_out     (rx_phy_err_out),
        .no_sfd_out      (rx_no_sfd_out),
        .sfd_seen_out    (rx_sfd_seen_out),
        .frame_ok_out    (rx_frame_ok_out),
        .frame_len_out   (rx_frame_len_out)
    );

endmodule

`default_nettype wire

