`timescale 1ns / 1ps
`default_nettype none

module tx_mac #(
    parameter integer FIFO_ADDR_W   = 11,
    parameter integer MIN_FRAME_LEN = 60,
    parameter integer IFG_BIT_TIMES = 96
)(
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    output wire        frame_drop_out,

    input  wire        tx_clk,
    input  wire        tx_rst_n,
    input  wire        speed_select,
    output wire [7:0]  gmii_txd,
    output wire        gmii_tx_en,

    output wire        frame_sent_out,
    output wire        tx_busy_out
);

    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] SFD  = 2'd1;
    localparam [1:0] FCS  = 2'd2;
    localparam [1:0] WAIT = 2'd3;

    reg [1:0] state;
    reg [1:0] fcs_cnt;
    reg [5:0] gap;
    reg [1:0] spd_q;

    wire spd = spd_q[1];

    wire [7:0]  f_data;
    wire        f_valid, f_last, f_avail, f_ready;

    wire [7:0]  s_data;
    wire        s_valid, s_body, s_last;

    wire        phy_ready, phy_done;
    wire [31:0] crc_val;

    wire launch   = (state == IDLE) && f_avail && (gap == 0) && !phy_done;
    wire s_xfer   = s_valid && phy_ready;

    always @(posedge tx_clk or negedge tx_rst_n) begin
        if (!tx_rst_n) begin
            spd_q   <= 2'b00;
            state   <= IDLE;
            fcs_cnt <= 2'd0;
            gap     <= 6'd0;
        end else begin
            spd_q <= {spd_q[0], speed_select};

            if (phy_done)
                gap <= spd ? (IFG_BIT_TIMES / 8) : (IFG_BIT_TIMES / 4);
            else if (gap != 0)
                gap <= gap - 6'd1;

            case (state)
                IDLE: if (launch) state <= SFD;

                SFD: if (s_xfer && s_last) begin
                    fcs_cnt <= 2'd0;
                    state   <= FCS;
                end

                FCS: if (phy_ready) begin
                    fcs_cnt <= fcs_cnt + 2'd1;
                    if (fcs_cnt == 2'd3) state <= WAIT;
                end

                WAIT: if (phy_done) state <= IDLE;
            endcase
        end
    end

    wire [31:0] fcs = ~crc_val;

    wire [7:0] fcs_byte = (fcs_cnt == 2'd0) ? fcs[7:0]   :
                          (fcs_cnt == 2'd1) ? fcs[15:8]  :
                          (fcs_cnt == 2'd2) ? fcs[23:16] : fcs[31:24];

    wire [7:0] phy_data  = (state == SFD) ? s_data  : fcs_byte;
    wire       phy_valid = (state == SFD) ? s_valid : (state == FCS);

    assign frame_sent_out = phy_done;
    assign tx_busy_out    = (state != IDLE) || (gap != 0);

    tx_fifo #(
        .ADDR_W (FIFO_ADDR_W)
    ) u_fifo (
        .wr_clk          (wr_clk),
        .wr_rst_n        (wr_rst_n),
        .s_axis_tdata    (s_axis_tdata),
        .s_axis_tvalid   (s_axis_tvalid),
        .s_axis_tready   (s_axis_tready),
        .s_axis_tlast    (s_axis_tlast),
        .frame_drop_out  (frame_drop_out),

        .rd_clk          (tx_clk),
        .rd_rst_n        (tx_rst_n),
        .data_out        (f_data),
        .valid_out       (f_valid),
        .ready_out       (f_ready),
        .last_out        (f_last),
        .frame_avail_out (f_avail)
    );

    tx_sfd #(
        .MIN_LEN (MIN_FRAME_LEN)
    ) u_sfd (
        .clk      (tx_clk),
        .rst_n    (tx_rst_n),
        .start    (launch),
        .ready    (phy_ready),
        .in_data  (f_data),
        .in_valid (f_valid),
        .in_last  (f_last),
        .in_ready (f_ready),
        .data     (s_data),
        .valid    (s_valid),
        .body     (s_body),
        .last     (s_last)
    );

    crc u_crc (
        .clk   (tx_clk),
        .rst_n (tx_rst_n),
        .init  (state == IDLE),
        .valid (s_body && s_xfer),
        .data  (s_data),
        .value (crc_val),
        .good  ()
    );

    tx_phy u_phy (
        .clk        (tx_clk),
        .rst_n      (tx_rst_n),
        .speed      (spd),
        .data_in    (phy_data),
        .valid_in   (phy_valid),
        .ready_in   (phy_ready),
        .txd        (gmii_txd),
        .tx_en      (gmii_tx_en),
        .frame_done (phy_done)
    );

endmodule

`default_nettype wire
