// tx_mac_controller - TX integration top: frame FSM, source multiplexer, FCS serialiser, payload lead register.

`timescale 1ns / 1ps
`default_nettype none

module tx_mac_controller #(
    parameter integer DATA_W        = 8,
    parameter integer FIFO_ADDR_W   = 11,
    parameter integer MIN_FRAME_LEN = 60,
    parameter integer PREAMBLE_LEN  = 7,
    parameter integer IFG_BIT_TIMES = 96,

    parameter integer ERR_CYCLES    = 2
)(

    input  wire                 wr_clk,
    input  wire                 wr_rst_n,
    input  wire [DATA_W-1:0]    s_axis_tdata,
    input  wire                 s_axis_tvalid,
    output wire                 s_axis_tready,
    input  wire                 s_axis_tlast,
    output wire                 frame_drop_out,

    input  wire                 tx_clk,
    input  wire                 tx_rst_n,
    input  wire                 speed_select,

    output wire [7:0]           gmii_txd,
    output wire                 gmii_tx_en,
    output wire                 gmii_tx_er,

    output wire                 frame_sent_out,
    output wire                 underrun_out,
    output wire                 tx_busy_out

);

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_PRE  = 3'd1;
    localparam [2:0] ST_PAY  = 3'd2;
    localparam [2:0] ST_FCS  = 3'd3;
    localparam [2:0] ST_WAIT = 3'd4;
    localparam [2:0] ST_ABRT = 3'd5;
    localparam [2:0] ST_FLSH = 3'd6;

    localparam integer PRE_LAST_I = PREAMBLE_LEN;
    localparam [3:0]   PRE_LAST   = PRE_LAST_I[3:0];

    reg [2:0] state;
    reg [3:0] pre_cnt;
    reg [1:0] fcs_cnt;
    reg       abrt_gap;

    reg [7:0] pay_d;
    reg       pay_v;
    reg       pay_e;

    reg spd_q1, spd_q2;

    always @(posedge tx_clk or negedge tx_rst_n) begin
        if (!tx_rst_n) begin
            spd_q1 <= 1'b0;
            spd_q2 <= 1'b0;
        end else begin
            spd_q1 <= speed_select;
            spd_q2 <= spd_q1;
        end
    end

    wire spd = spd_q2;

    wire [DATA_W-1:0] fifo_data;
    wire              fifo_valid;
    wire              fifo_last;
    wire              fifo_avail;
    wire              fifo_ready;

    wire [DATA_W-1:0] pad_data;
    wire              pad_valid;
    wire              pad_sof;
    wire              pad_eof;

    wire [DATA_W-1:0] pre_data;
    wire              pre_valid;

    wire [31:0]       fcs_word;

    wire              ifg_active;

    wire              phy_ready;
    wire              phy_frame_done;
    wire              phy_underrun;

    wire              pre_sfd_done;
    wire              ifg_done;
    wire              fcs_valid;

    wire adv = phy_ready;

    wire pay_taken = (state == ST_PAY) && pay_v && adv;

    wire pay_room  = (!pay_v) || pay_taken;

    wire pad_ready = (adv && pay_room && (!pay_e) &&
                        ((state == ST_PRE) || (state == ST_PAY)))
                     || (state == ST_FLSH);

    wire pad_xfer  = pad_valid && pad_ready;

    wire pre_ready = (adv && (state == ST_PRE)) || (state == ST_FLSH);
    wire pre_xfer  = pre_valid && pre_ready;

    wire fcs_dv    = pad_xfer && (state != ST_FLSH);

    wire may_start  = ~(ifg_active | phy_frame_done | abrt_gap);
    wire have_frame = fifo_avail | pad_valid;
    wire launch     = (state == ST_IDLE) && have_frame && may_start;

    wire pre_start = launch;

    wire fcs_init = launch;

    wire ifg_start = (phy_frame_done | abrt_gap) & (~ifg_active);

    reg [7:0] fcs_byte;

    always @(*) begin
        case (fcs_cnt)
            2'd0:    fcs_byte = fcs_word[7:0];
            2'd1:    fcs_byte = fcs_word[15:8];
            2'd2:    fcs_byte = fcs_word[23:16];
            default: fcs_byte = fcs_word[31:24];
        endcase
    end

    reg [7:0] phy_data;
    reg       phy_valid;
    reg       phy_last;

    always @(*) begin
        case (state)
            ST_PRE: begin
                phy_data  = pre_data;
                phy_valid = pre_valid;
                phy_last  = 1'b0;
            end
            ST_PAY: begin
                phy_data  = pay_d;
                phy_valid = pay_v;
                phy_last  = 1'b0;
            end
            ST_FCS: begin
                phy_data  = fcs_byte;
                phy_valid = 1'b1;
                phy_last  = (fcs_cnt == 2'd3);
            end
            ST_ABRT: begin

                phy_data  = 8'h00;
                phy_valid = 1'b1;
                phy_last  = 1'b1;
            end
            default: begin
                phy_data  = 8'h00;
                phy_valid = 1'b0;
                phy_last  = 1'b0;
            end
        endcase
    end

    reg in_frame;

    always @(posedge tx_clk or negedge tx_rst_n) begin
        if (!tx_rst_n)
            in_frame <= 1'b0;
        else if (fifo_valid && fifo_ready)
            in_frame <= ~fifo_last;
    end

    wire fifo_sof = fifo_valid && (!in_frame);
    wire fifo_eof = fifo_valid && fifo_last;

    always @(posedge tx_clk or negedge tx_rst_n) begin
        if (!tx_rst_n) begin
            pay_d <= 8'h00;
            pay_v <= 1'b0;
            pay_e <= 1'b0;
        end else if ((state == ST_ABRT) || (state == ST_FLSH)) begin

            pay_v <= 1'b0;
            pay_e <= 1'b0;
        end else if (pad_xfer) begin
            pay_d <= pad_data;
            pay_v <= 1'b1;
            pay_e <= pad_eof;
        end else if (pay_taken) begin
            pay_v <= 1'b0;
            pay_e <= 1'b0;
        end
    end

    always @(posedge tx_clk or negedge tx_rst_n) begin
        if (!tx_rst_n) begin
            state    <= ST_IDLE;
            pre_cnt  <= 4'd0;
            fcs_cnt  <= 2'd0;
            abrt_gap <= 1'b0;
        end else begin

            abrt_gap <= 1'b0;

            if (phy_underrun) begin

                state   <= ST_ABRT;
                pre_cnt <= 4'd0;
                fcs_cnt <= 2'd0;
            end else begin
                case (state)

                    ST_IDLE: begin
                        if (launch) begin
                            pre_cnt <= 4'd0;
                            state   <= ST_PRE;
                        end
                    end

                    ST_PRE: begin
                        if (pre_xfer) begin
                            if (pre_cnt == PRE_LAST)
                                state   <= ST_PAY;
                            else
                                pre_cnt <= pre_cnt + 4'd1;
                        end
                    end

                    ST_PAY: begin
                        if (pay_taken && pay_e) begin
                            fcs_cnt <= 2'd0;
                            state   <= ST_FCS;
                        end
                    end

                    ST_FCS: begin
                        if (adv) begin
                            if (fcs_cnt == 2'd3)
                                state   <= ST_WAIT;
                            else
                                fcs_cnt <= fcs_cnt + 2'd1;
                        end
                    end

                    ST_WAIT: begin
                        if (phy_frame_done)
                            state <= ST_IDLE;
                    end

                    ST_ABRT: begin
                        if (adv)
                            state <= ST_FLSH;
                    end

                    ST_FLSH: begin
                        if (pad_xfer && pad_eof) begin
                            abrt_gap <= 1'b1;
                            state    <= ST_IDLE;
                        end
                    end

                    default: begin
                        state   <= ST_IDLE;
                        pre_cnt <= 4'd0;
                        fcs_cnt <= 2'd0;
                    end

                endcase
            end
        end
    end

    assign frame_sent_out = phy_frame_done;
    assign underrun_out   = phy_underrun;
    assign tx_busy_out    = (state != ST_IDLE) | ifg_active;

    tx_fifo #(
        .DATA_W (DATA_W),
        .ADDR_W (FIFO_ADDR_W)
    ) u_tx_fifo (
        .wr_clk          (wr_clk),
        .wr_rst_n        (wr_rst_n),
        .s_axis_tdata    (s_axis_tdata),
        .s_axis_tvalid   (s_axis_tvalid),
        .s_axis_tready   (s_axis_tready),
        .s_axis_tlast    (s_axis_tlast),
        .frame_drop_out  (frame_drop_out),

        .rd_clk          (tx_clk),
        .rd_rst_n        (tx_rst_n),
        .data_out        (fifo_data),
        .valid_out       (fifo_valid),
        .ready_out       (fifo_ready),
        .last_out        (fifo_last),
        .frame_avail_out (fifo_avail)
    );

    tx_padding #(
        .DATA_WIDTH    (DATA_W),
        .MIN_FRAME_LEN (MIN_FRAME_LEN)
    ) u_tx_padding (
        .tx_clk    (tx_clk),
        .rst_n     (tx_rst_n),

        .data_in   (fifo_data),
        .valid_in  (fifo_valid),
        .sof_in    (fifo_sof),
        .eof_in    (fifo_eof),
        .ready_in  (fifo_ready),

        .data_out  (pad_data),
        .valid_out (pad_valid),
        .sof_out   (pad_sof),
        .eof_out   (pad_eof),
        .ready_out (pad_ready)
    );

    tx_fcs u_tx_fcs (
        .clk        (tx_clk),
        .rst_n      (tx_rst_n),
        .init       (fcs_init),
        .data_valid (fcs_dv),
        .data_in    (pad_data),
        .fcs_out    (fcs_word),
        .fcs_valid  (fcs_valid)
    );

    tx_preamble #(
        .DATA_WIDTH     (DATA_W),
        .PREAMBLE_BYTE  (8'h55),
        .SFD_BYTE       (8'hD5),
        .PREAMBLE_COUNT (PREAMBLE_LEN)
    ) u_tx_preamble (
        .tx_clk       (tx_clk),
        .rst_n        (tx_rst_n),
        .start_in     (pre_start),
        .ready_out     (pre_ready),
        .data_out     (pre_data),
        .valid_out    (pre_valid),
        .sfd_done_out (pre_sfd_done)
    );

    tx_ifg #(
        .IFG_BIT_TIMES (IFG_BIT_TIMES),
        .NIBBLE_BITS   (4),
        .OCTET_BITS    (8)
    ) u_tx_ifg (
        .clk          (tx_clk),
        .rst_n        (tx_rst_n),
        .speed_select (spd),
        .ifg_start    (ifg_start),
        .ifg_active   (ifg_active),
        .ifg_done     (ifg_done)
    );

    tx_gmii_mii #(
        .ERR_CYCLES (ERR_CYCLES)
    ) u_tx_gmii_mii (
        .tx_clk         (tx_clk),
        .rst_n          (tx_rst_n),
        .speed_select   (spd),

        .data_in        (phy_data),
        .valid_in       (phy_valid),
        .last_in        (phy_last),
        .err_in         (1'b0),
        .ready_in      (phy_ready),

        .gmii_txd       (gmii_txd),
        .gmii_tx_en     (gmii_tx_en),
        .gmii_tx_er     (gmii_tx_er),

        .frame_done_out (phy_frame_done),
        .underrun_out   (phy_underrun)
    );

    wire pad_sof_unused = pad_sof;

endmodule

`default_nettype wire

