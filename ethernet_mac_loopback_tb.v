// ethernet_mac_loopback_tb - TX pins wired to RX pins; end-to-end round trip and corruption tests.

`timescale 1ns / 1ps
`default_nettype none

module ethernet_mac_loopback_tb;

    localparam real WRP = 10.0;
    localparam real TXP =  8.0;
    localparam real RDP = 13.0;

    localparam integer MINLEN = 60;
    localparam integer MAXLEN = 1514;
    localparam integer RX_ADDR_W = 11;

    reg wr_clk, tx_clk, rd_clk;
    reg wr_rst_n, tx_rst_n, rd_rst_n;

    initial begin wr_clk = 1'b0; forever #(WRP/2.0) wr_clk = ~wr_clk; end
    initial begin tx_clk = 1'b0; forever #(TXP/2.0) tx_clk = ~tx_clk; end
    initial begin rd_clk = 1'b0; forever #(RDP/2.0) rd_clk = ~rd_clk; end

    wire strap = 1'b1;

    reg  [7:0] s_tdata;
    reg        s_tvalid;
    reg        s_tlast;
    wire       s_tready;
    wire       tx_frame_drop;

    wire [7:0] txd;
    wire       tx_en;
    wire       tx_er;

    wire       tx_frame_sent;
    wire       tx_underrun;
    wire       tx_busy;

    tx_mac_controller #(
        .DATA_W        (8),
        .FIFO_ADDR_W   (11),
        .MIN_FRAME_LEN (MINLEN),
        .PREAMBLE_LEN  (7),
        .IFG_BIT_TIMES (96),
        .ERR_CYCLES    (2)
    ) u_tx (
        .wr_clk         (wr_clk),
        .wr_rst_n       (wr_rst_n),
        .s_axis_tdata   (s_tdata),
        .s_axis_tvalid  (s_tvalid),
        .s_axis_tready  (s_tready),
        .s_axis_tlast   (s_tlast),
        .frame_drop_out (tx_frame_drop),

        .tx_clk         (tx_clk),
        .tx_rst_n       (tx_rst_n),
        .speed_select   (strap),
        .gmii_txd       (txd),
        .gmii_tx_en     (tx_en),
        .gmii_tx_er     (tx_er),

        .frame_sent_out (tx_frame_sent),
        .underrun_out   (tx_underrun),
        .tx_busy_out    (tx_busy)
    );

    reg         chan_flip_en;
    integer     chan_flip_idx;
    reg  [7:0]  chan_flip_mask;
    reg         chan_force_er;
    integer     carrier_cyc;

    wire        hit = chan_flip_en && tx_en && (carrier_cyc == chan_flip_idx);

    wire [7:0]  rxd    = hit && !chan_force_er ? (txd ^ chan_flip_mask) : txd;
    wire        rx_dv  = tx_en;
    wire        rx_er  = tx_er | (hit && chan_force_er);

    always @(posedge tx_clk) begin
        if (!tx_rst_n)      carrier_cyc = 0;
        else if (tx_en)     carrier_cyc = carrier_cyc + 1;
        else                carrier_cyc = 0;
    end

    wire [7:0] m_tdata;
    wire       m_tvalid;
    reg        m_tready;
    wire       m_tlast;
    wire       rx_avail;

    wire       rx_frame_rcvd, rx_frame_drop, rx_overflow;
    wire       rx_crc_err, rx_len_err, rx_phy_err;
    wire       rx_no_sfd, rx_sfd_seen, rx_frame_ok;
    wire[10:0] rx_frame_len;

    rx_mac_controller #(
        .DATA_W        (8),
        .FIFO_ADDR_W   (RX_ADDR_W),
        .MIN_FRAME_LEN (MINLEN),
        .MAX_FRAME_LEN (MAXLEN),
        .PREAMBLE_BYTE (8'h55),
        .SFD_BYTE      (8'hD5),
        .PRE_MAX       (32)
    ) u_rx (
        .rx_clk          (tx_clk),
        .rx_rst_n        (tx_rst_n),
        .speed_select    (strap),
        .gmii_rxd        (rxd),
        .gmii_rx_dv      (rx_dv),
        .gmii_rx_er      (rx_er),

        .rd_clk          (rd_clk),
        .rd_rst_n        (rd_rst_n),
        .m_axis_tdata    (m_tdata),
        .m_axis_tvalid   (m_tvalid),
        .m_axis_tready   (m_tready),
        .m_axis_tlast    (m_tlast),
        .frame_avail_out (rx_avail),

        .frame_rcvd_out  (rx_frame_rcvd),
        .frame_drop_out  (rx_frame_drop),
        .overflow_out    (rx_overflow),
        .crc_err_out     (rx_crc_err),
        .len_err_out     (rx_len_err),
        .phy_err_out     (rx_phy_err),
        .no_sfd_out      (rx_no_sfd),
        .sfd_seen_out    (rx_sfd_seen),
        .frame_ok_out    (rx_frame_ok),
        .frame_len_out   (rx_frame_len)
    );

    integer pass_n, fail_n;

    task ck;
        input          cond;
        input [1023:0] msg;
        begin
            if (cond) begin pass_n = pass_n + 1; $display("    PASS : %0s", msg); end
            else      begin fail_n = fail_n + 1; $display("    FAIL : %0s", msg); end
        end
    endtask

    task ck_eq;
        input [31:0]   got;
        input [31:0]   exp;
        input [1023:0] msg;
        begin
            if (got === exp) begin
                pass_n = pass_n + 1;
                $display("    PASS : %0s (%0d)", msg, got);
            end else begin
                fail_n = fail_n + 1;
                $display("    FAIL : %0s - got %0d, expected %0d", msg, got, exp);
            end
        end
    endtask

    reg [7:0] sent [0:2047];
    integer   sent_n;

    task host_send;
        input integer n;
        integer k;
        begin
            sent_n = n;
            for (k = 0; k < n; k = k + 1) begin
                @(negedge wr_clk);
                s_tdata  <= sent[k];
                s_tvalid <= 1'b1;
                s_tlast  <= (k == n-1);

                @(posedge wr_clk);
                while (!s_tready) @(posedge wr_clk);
            end
            @(negedge wr_clk);
            s_tvalid <= 1'b0;
            s_tlast  <= 1'b0;
            s_tdata  <= 8'h00;
        end
    endtask

    localparam integer SMAX = 64;
    task load_string;
        input [8*SMAX-1:0] s;
        integer k, n;
        reg [7:0] b;
        begin
            n = 0;
            for (k = SMAX-1; k >= 0; k = k - 1) begin
                b = s[k*8 +: 8];
                if (b !== 8'h00) begin
                    sent[n] = b;
                    n = n + 1;
                end
            end
            sent_n = n;
        end
    endtask

    task load_ramp;
        input integer n;
        input [7:0]   first;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) sent[k] = first + k[7:0];
            sent_n = n;
        end
    endtask

    reg [7:0] rcvd [0:2047];
    integer   rcvd_n;
    integer   frames_out;
    reg [7:0] last_frame [0:2047];
    integer   last_len;
    integer   cap_i;

    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            rcvd_n = 0;
        end else if (m_tvalid && m_tready) begin
            if (rcvd_n < 2048) rcvd[rcvd_n] = m_tdata;
            rcvd_n = rcvd_n + 1;
            if (m_tlast) begin
                last_len = rcvd_n;
                for (cap_i = 0; cap_i < rcvd_n; cap_i = cap_i + 1)
                    last_frame[cap_i] = rcvd[cap_i];
                frames_out = frames_out + 1;
                rcvd_n     = 0;
            end
        end
    end

    integer n_sent, n_urun, n_txdrop;
    integer n_rcvd, n_rxdrop, n_ovf, n_crcerr, n_lenerr, n_phyerr, n_nosfd;

    always @(posedge tx_clk) begin
        if (!tx_rst_n) begin
            n_sent = 0; n_urun = 0;
            n_rcvd = 0; n_rxdrop = 0; n_ovf = 0;
            n_crcerr = 0; n_lenerr = 0; n_phyerr = 0; n_nosfd = 0;
        end else begin
            if (tx_frame_sent) n_sent   = n_sent   + 1;
            if (tx_underrun)   n_urun   = n_urun   + 1;
            if (rx_frame_rcvd) n_rcvd   = n_rcvd   + 1;
            if (rx_frame_drop) n_rxdrop = n_rxdrop + 1;
            if (rx_overflow)   n_ovf    = n_ovf    + 1;
            if (rx_crc_err)    n_crcerr = n_crcerr + 1;
            if (rx_len_err)    n_lenerr = n_lenerr + 1;
            if (rx_phy_err)    n_phyerr = n_phyerr + 1;
            if (rx_no_sfd)     n_nosfd  = n_nosfd  + 1;
        end
    end

    always @(posedge wr_clk) begin
        if (!wr_rst_n)          n_txdrop = 0;
        else if (tx_frame_drop) n_txdrop = n_txdrop + 1;
    end

    task clear_counts;
        begin
            #0.1;
            n_sent = 0; n_urun = 0; n_txdrop = 0;
            n_rcvd = 0; n_rxdrop = 0; n_ovf = 0;
            n_crcerr = 0; n_lenerr = 0; n_phyerr = 0; n_nosfd = 0;
            frames_out = 0; last_len = 0;
        end
    endtask

    localparam integer QUIET   = 64;
    localparam integer SET_CAP = 40000;

    task settle;
        integer k, calm;
        begin
            calm = 0;
            k    = 0;
            while (calm < QUIET && k < SET_CAP) begin
                @(posedge rd_clk);
                k = k + 1;
                if (tx_busy || tx_en || m_tvalid || s_tvalid) calm = 0;
                else                                          calm = calm + 1;
            end
            if (k >= SET_CAP)
                $display("    NOTE : settle hit its cap - link never went quiet");
        end
    endtask

    task do_reset;
        begin
            wr_rst_n = 1'b0; tx_rst_n = 1'b0; rd_rst_n = 1'b0;
            s_tdata  = 8'h00; s_tvalid = 1'b0; s_tlast = 1'b0;
            m_tready = 1'b1;
            chan_flip_en = 1'b0; chan_flip_idx = -1;
            chan_flip_mask = 8'h00; chan_force_er = 1'b0;
            repeat (8) @(posedge tx_clk);
            @(negedge tx_clk); tx_rst_n = 1'b1;
            @(negedge wr_clk); wr_rst_n = 1'b1;
            @(negedge rd_clk); rd_rst_n = 1'b1;
            repeat (6) @(posedge rd_clk);
        end
    endtask

    task check_roundtrip;
        input [1023:0] tag;
        input integer  expect_len;
        integer k, bad, padbad;
        begin
            ck_eq(last_len, expect_len, {tag, " : delivered length"});

            bad = 0;
            for (k = 0; k < sent_n; k = k + 1)
                if (last_frame[k] !== sent[k]) bad = bad + 1;
            ck_eq(bad, 0, {tag, " : payload octets identical"});

            padbad = 0;
            for (k = sent_n; k < expect_len; k = k + 1)
                if (last_frame[k] !== 8'h00) padbad = padbad + 1;
            ck_eq(padbad, 0, {tag, " : every pad octet is zero"});
        end
    endtask

    integer txcyc, rdcyc;
    reg     trace_on;
    reg [7:0] w_prev, h_prev;
    integer   w_run,  h_run;

    always @(posedge tx_clk) begin
        txcyc = txcyc + 1;
        if (trace_on && (tx_en || rx_sfd_seen || rx_frame_rcvd)) begin
            if (tx_en && (txd === w_prev) && !rx_sfd_seen && !rx_frame_rcvd) begin
                w_run = w_run + 1;
            end else begin
                if (w_run > 0)
                    $display("  ...     |          x%0d more identical octets", w_run);
                w_run  = 0;
                w_prev = txd;
                $display("  W%0d | TXD=%02h EN=%0b ER=%0b -> RXD=%02h DV=%0b ER=%0b | sfd=%0b rcvd=%0b crcerr=%0b",
                         txcyc, txd, tx_en, tx_er, rxd, rx_dv, rx_er,
                         rx_sfd_seen, rx_frame_rcvd, rx_crc_err);
            end
        end
    end

    always @(posedge rd_clk) begin
        rdcyc = rdcyc + 1;
        if (trace_on && m_tvalid) begin
            if ((m_tdata === h_prev) && !m_tlast) begin
                h_run = h_run + 1;
            end else begin
                if (h_run > 0)
                    $display("       ...  | x%0d more identical octets", h_run);
                h_run  = 0;
                h_prev = m_tdata;
                $display("       H%0d | TDATA=%02h TV=%0b TR=%0b TL=%0b",
                         rdcyc, m_tdata, m_tvalid, m_tready, m_tlast);
            end
        end
    end

    task suite1;
        integer k;
        begin
            $display("");
            $display("=====================================================");
            $display(" SUITE 1 SIMPLE - \"abc\" through TX, over the wire,");
            $display("                  and back out of RX");
            $display("=====================================================");
            $display(" Three octets in. 72 octets on the wire. 60 octets out,");
            $display(" of which the first three are 'abc' and the rest is pad.");
            $display("");

            do_reset;
            clear_counts;

            sent[0] = 8'h61; sent[1] = 8'h62; sent[2] = 8'h63;
            sent_n  = 3;

            trace_on = 1'b1;
            host_send(3);
            settle;
            trace_on = 1'b0;

            $display("");
            $display("  ---- what the host got back ----");
            $display("  length : %0d octets", last_len);
            $write  ("  first 8: ");
            for (k = 0; k < 8 && k < last_len; k = k + 1)
                $write("%02h ", last_frame[k]);
            $display("");
            $write  ("  as text: ");
            for (k = 0; k < 3 && k < last_len; k = k + 1)
                $write("%0s", last_frame[k]);
            $display("");
            $display("  tail   : %02h %02h %02h (pad)",
                     last_frame[57], last_frame[58], last_frame[59]);
            $display("");
            $display("  tx frame_sent  : %0d", n_sent);
            $display("  rx frame_rcvd  : %0d", n_rcvd);
            $display("  rx crc_err     : %0d", n_crcerr);
            $display("  rx frame_len   : %0d", rx_frame_len);
            $display("");
        end
    endtask

    task t2_1;
        begin
            $display("");
            $display(" TEST 2.1 - clean loopback of \"abc\"");
            do_reset;
            clear_counts;
            sent[0] = 8'h61; sent[1] = 8'h62; sent[2] = 8'h63;
            sent_n  = 3;
            host_send(3);
            settle;
            ck_eq(frames_out, 1, "exactly one frame reached the host");
            check_roundtrip("2.1", 60);
            ck(last_frame[0] === 8'h61, "octet 0 is 'a'");
            ck(last_frame[1] === 8'h62, "octet 1 is 'b'");
            ck(last_frame[2] === 8'h63, "octet 2 is 'c'");
            ck_eq(n_sent,   1, "TX reported one frame sent");
            ck_eq(n_rcvd,   1, "RX reported one frame received");
            ck_eq(n_crcerr, 0, "no CRC error");
            ck_eq(n_rxdrop, 0, "no frame dropped");
            ck_eq(n_urun,   0, "no TX underrun");
            ck_eq(rx_frame_len, 60, "rx frame_len_out is 60 (body incl. pad)");
        end
    endtask

    task t2_2;
        integer k;
        begin
            $display("");
            $display(" TEST 2.2 - \"Hello World\" round trip");
            do_reset;
            clear_counts;
            load_string("Hello World");
            ck_eq(sent_n, 11, "11 octets to send");
            host_send(sent_n);
            settle;
            ck_eq(frames_out, 1, "one frame reached the host");
            check_roundtrip("2.2", 60);
            $write("    text out : \"");
            for (k = 0; k < sent_n; k = k + 1) $write("%0s", last_frame[k]);
            $display("\"");
        end
    endtask

    task t2_3;
        begin
            $display("");
            $display(" TEST 2.3 - exactly 60 octets, so nothing is padded");
            do_reset;
            clear_counts;
            load_ramp(60, 8'h10);
            host_send(60);
            settle;
            ck_eq(frames_out, 1, "one frame delivered");
            check_roundtrip("2.3", 60);
        end
    endtask

    task t2_4;
        begin
            $display("");
            $display(" TEST 2.4 - a 1-octet frame padded to 60");
            do_reset;
            clear_counts;
            sent[0] = 8'h5A; sent_n = 1;
            host_send(1);
            settle;
            ck_eq(frames_out, 1, "one frame delivered");
            check_roundtrip("2.4", 60);
        end
    endtask

    task t2_5;
        begin
            $display("");
            $display(" TEST 2.5 - a 200-octet frame (no padding involved)");
            do_reset;
            clear_counts;
            load_ramp(200, 8'h00);
            host_send(200);
            settle;
            ck_eq(frames_out, 1, "one frame delivered");
            check_roundtrip("2.5", 200);
            ck_eq(rx_frame_len, 200, "rx frame_len_out is 200");
        end
    endtask

    task t2_6;
        begin
            $display("");
            $display(" TEST 2.6 - maxUntaggedFrameSize: a 1514-octet body");
            do_reset;
            clear_counts;
            load_ramp(1514, 8'h00);
            host_send(1514);
            settle;
            ck_eq(frames_out, 1, "one frame delivered");
            check_roundtrip("2.6", 1514);
            ck_eq(n_lenerr, 0, "1514 is NOT flagged oversize");
        end
    endtask

    task t2_7;
        begin
            $display("");
            $display(" TEST 2.7 - flip ONE bit mid-payload -> frame must vanish");
            do_reset;
            clear_counts;
            load_ramp(100, 8'h20);

            chan_flip_en   = 1'b1;
            chan_flip_idx  = 20;
            chan_flip_mask = 8'h01;
            host_send(100);
            settle;
            ck_eq(frames_out, 0, "the host saw NOTHING");
            ck_eq(n_crcerr,   1, "RX raised crc_err_out");
            ck_eq(n_rxdrop,   1, "RX raised frame_drop_out");
            ck_eq(n_rcvd,     0, "RX did NOT report a frame received");
            ck_eq(n_sent,     1, "TX still thinks it sent a frame (correct)");
            ck(m_tvalid === 1'b0, "AXI stayed quiet");
        end
    endtask

    task t2_8;
        begin
            $display("");
            $display(" TEST 2.8 - flip a bit in the FIRST body octet");
            do_reset;
            clear_counts;
            load_ramp(80, 8'h30);
            chan_flip_en   = 1'b1;
            chan_flip_idx  = 8;
            chan_flip_mask = 8'h80;
            host_send(80);
            settle;
            ck_eq(frames_out, 0, "nothing delivered");
            ck_eq(n_crcerr,   1, "crc_err_out raised");
        end
    endtask

    task t2_9;
        begin
            $display("");
            $display(" TEST 2.9 - corrupt the FCS, not the body");
            do_reset;
            clear_counts;
            load_ramp(60, 8'h40);

            chan_flip_en   = 1'b1;
            chan_flip_idx  = 69;
            chan_flip_mask = 8'h10;
            host_send(60);
            settle;
            ck_eq(frames_out, 0, "nothing delivered");
            ck_eq(n_crcerr,   1, "crc_err_out raised");
            ck_eq(n_rcvd,     0, "no frame reported received");
        end
    endtask

    task t2_10;
        begin
            $display("");
            $display(" TEST 2.10 - corrupt the LAST octet on the wire");
            do_reset;
            clear_counts;
            load_ramp(60, 8'h50);
            chan_flip_en   = 1'b1;
            chan_flip_idx  = 71;
            chan_flip_mask = 8'h01;
            host_send(60);
            settle;
            ck_eq(frames_out, 0, "nothing delivered");
            ck_eq(n_crcerr,   1, "crc_err_out raised");
        end
    endtask

    task t2_11;
        begin
            $display("");
            $display(" TEST 2.11 - invert a whole octet");
            do_reset;
            clear_counts;
            load_ramp(70, 8'h60);
            chan_flip_en   = 1'b1;
            chan_flip_idx  = 30;
            chan_flip_mask = 8'hFF;
            host_send(70);
            settle;
            ck_eq(frames_out, 0, "nothing delivered");
            ck_eq(n_crcerr,   1, "crc_err_out raised");
        end
    endtask

    task t2_12;
        begin
            $display("");
            $display(" TEST 2.12 - corrupt the SFD -> no_sfd, NOT crc_err");
            do_reset;
            clear_counts;
            load_ramp(60, 8'h70);
            chan_flip_en   = 1'b1;
            chan_flip_idx  = 7;
            chan_flip_mask = 8'h0F;
            host_send(60);
            settle;
            ck_eq(frames_out, 0, "nothing delivered");
            ck_eq(n_nosfd,    1, "no_sfd_out fired");
            ck_eq(n_crcerr,   0, "crc_err_out did NOT fire - no frame existed");
            ck_eq(n_rcvd,     0, "nothing reported received");
        end
    endtask

    task t2_13;
        begin
            $display("");
            $display(" TEST 2.13 - corrupt a preamble octet -> carrier discarded");
            do_reset;
            clear_counts;
            load_ramp(60, 8'h80);
            chan_flip_en   = 1'b1;
            chan_flip_idx  = 3;
            chan_flip_mask = 8'h07;
            host_send(60);
            settle;
            ck_eq(frames_out, 0, "nothing delivered");
            ck_eq(n_nosfd,    1, "no_sfd_out fired");
            ck_eq(n_crcerr,   0, "the real SFD did NOT rescue the carrier");
        end
    endtask

    task t2_14;
        begin
            $display("");
            $display(" TEST 2.14 - RX_ER with a PERFECT CRC is still dropped");
            do_reset;
            clear_counts;
            load_ramp(60, 8'h90);
            chan_flip_en  = 1'b1;
            chan_force_er = 1'b1;
            chan_flip_idx = 25;
            host_send(60);
            settle;
            ck_eq(frames_out, 0, "nothing delivered");
            ck_eq(n_phyerr,   1, "phy_err_out fired");
            ck_eq(n_crcerr,   1, "crc_err_out fired too (phy_err folds in)");
            ck_eq(n_rcvd,     0, "nothing reported received");
        end
    endtask

    task t2_15;
        begin
            $display("");
            $display(" TEST 2.15 - a good frame immediately after a corrupted one");
            do_reset;
            clear_counts;

            load_ramp(60, 8'hA0);
            chan_flip_en   = 1'b1;
            chan_flip_idx  = 20;
            chan_flip_mask = 8'h01;
            host_send(60);
            settle;
            ck_eq(frames_out, 0, "the corrupted frame delivered nothing");

            chan_flip_en = 1'b0;
            load_ramp(60, 8'hB0);
            host_send(60);
            settle;
            ck_eq(frames_out, 1, "the next frame arrived intact");
            check_roundtrip("2.15", 60);
            ck_eq(n_rxdrop, 1, "exactly one drop in total");
            ck_eq(n_rcvd,   1, "exactly one receive in total");
        end
    endtask

    task t2_16;
        integer f;
        begin
            $display("");
            $display(" TEST 2.16 - alternating clean/corrupt x6 -> 3 arrive");
            do_reset;
            clear_counts;
            for (f = 0; f < 6; f = f + 1) begin
                load_ramp(60, 8'hC0 + f[7:0]);
                if (f[0]) begin
                    chan_flip_en   = 1'b1;
                    chan_flip_idx  = 15 + f;
                    chan_flip_mask = 8'h01;
                end else begin
                    chan_flip_en = 1'b0;
                end
                host_send(60);
                settle;
            end
            ck_eq(frames_out, 3, "3 of 6 frames delivered");
            ck_eq(n_rcvd,     3, "3 receives");
            ck_eq(n_rxdrop,   3, "3 drops");

            load_ramp(60, 8'hC0 + 8'd4);
            check_roundtrip("2.16", 60);
        end
    endtask

    task t2_17;
        begin
            $display("");
            $display(" TEST 2.17 - three frames back to back through the link");
            do_reset;
            clear_counts;
            load_ramp(60, 8'h11); host_send(60);
            load_ramp(60, 8'h22); host_send(60);
            load_ramp(60, 8'h33); host_send(60);
            settle;
            ck_eq(frames_out, 3, "all three delivered");
            ck_eq(n_sent,     3, "TX sent three");
            ck_eq(n_rcvd,     3, "RX received three");
            ck_eq(n_rxdrop,   0, "none dropped");
            check_roundtrip("2.17", 60);
        end
    endtask

    task t2_18;
        integer k;
        begin
            $display("");
            $display(" TEST 2.18 - receiving host asserts tready sporadically");
            do_reset;
            clear_counts;
            load_ramp(60, 8'h44);
            fork
                begin
                    host_send(60);
                    settle;
                end
                begin
                    for (k = 0; k < 700; k = k + 1) begin
                        @(negedge rd_clk);
                        m_tready = (k % 3 == 0);
                    end
                end
            join
            m_tready = 1'b1;
            settle;
            ck_eq(frames_out, 1, "frame still delivered to a slow host");
            check_roundtrip("2.18", 60);
        end
    endtask

    task t2_19;
        integer k;
        begin
            $display("");
            $display(" TEST 2.19 - a body made entirely of 0x55 and 0xD5");
            do_reset;
            clear_counts;
            for (k = 0; k < 60; k = k + 1) sent[k] = k[0] ? 8'hD5 : 8'h55;
            sent_n = 60;
            host_send(60);
            settle;
            ck_eq(frames_out, 1, "frame delivered");
            check_roundtrip("2.19", 60);
        end
    endtask

    task t2_20;
        integer k;
        begin
            $display("");
            $display(" TEST 2.20 - an all-zero 60-octet body");
            do_reset;
            clear_counts;
            for (k = 0; k < 60; k = k + 1) sent[k] = 8'h00;
            sent_n = 60;
            host_send(60);
            settle;
            ck_eq(frames_out, 1, "frame delivered");
            ck_eq(last_len,  60, "60 octets");
            ck_eq(n_crcerr,   0, "no CRC error on an all-zero body");
        end
    endtask

    task t2_21;
        integer k;
        begin
            $display("");
            $display(" TEST 2.21 - an all-0xFF 60-octet body");
            do_reset;
            clear_counts;
            for (k = 0; k < 60; k = k + 1) sent[k] = 8'hFF;
            sent_n = 60;
            host_send(60);
            settle;
            ck_eq(frames_out, 1, "frame delivered");
            check_roundtrip("2.21", 60);
        end
    endtask

    task t2_22;
        integer n, expect_len, ok_cnt;
        begin
            $display("");
            $display(" TEST 2.22 - length sweep across the pad boundary");
            do_reset;
            ok_cnt = 0;
            for (n = 1; n <= 8; n = n + 1) begin
                clear_counts;
                load_ramp(n, 8'h70 + n[7:0]);
                host_send(n);
                settle;
                if (frames_out == 1 && last_len == 60) ok_cnt = ok_cnt + 1;
                else $display("      length %0d FAILED: frames=%0d len=%0d",
                              n, frames_out, last_len);
            end
            ck_eq(ok_cnt, 8, "lengths 1..8 all padded to 60 and delivered");

            for (n = 59; n <= 61; n = n + 1) begin
                clear_counts;
                load_ramp(n, 8'h01);
                host_send(n);
                settle;
                expect_len = (n < 60) ? 60 : n;
                ck_eq(frames_out, 1, "pad-boundary frame delivered");
                ck_eq(last_len, expect_len, "pad-boundary length correct");
            end
        end
    endtask

    task t2_23;
        integer b, caught;
        begin
            $display("");
            $display(" TEST 2.23 - all 8 single-bit errors in one octet caught");
            do_reset;
            caught = 0;
            for (b = 0; b < 8; b = b + 1) begin
                clear_counts;
                load_ramp(60, 8'hE0);
                chan_flip_en   = 1'b1;
                chan_flip_idx  = 30;
                chan_flip_mask = (8'h01 << b);
                host_send(60);
                settle;
                if (frames_out == 0 && n_crcerr == 1) caught = caught + 1;
                else $display("      bit %0d ESCAPED: frames=%0d crcerr=%0d",
                              b, frames_out, n_crcerr);
            end
            ck_eq(caught, 8, "all 8 single-bit errors detected and dropped");
            chan_flip_en = 1'b0;
        end
    endtask

    task t2_24;
        integer idx, delivered;
        begin
            $display("");
            $display(" TEST 2.24 - corrupt each of the 72 wire octets in turn");
            do_reset;
            delivered = 0;
            for (idx = 0; idx < 72; idx = idx + 1) begin
                clear_counts;
                load_ramp(60, 8'h0A);
                chan_flip_en   = 1'b1;
                chan_flip_idx  = idx;
                chan_flip_mask = 8'h01;
                host_send(60);
                settle;
                if (frames_out != 0) begin
                    delivered = delivered + 1;
                    $display("      wire octet %0d LEAKED a frame to the host", idx);
                end
            end
            ck_eq(delivered, 0,
                  "no corrupted frame reached the host at ANY wire position");
            chan_flip_en = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("ethernet_mac_loopback_tb.vcd");
        $dumpvars(0, ethernet_mac_loopback_tb);

        pass_n = 0; fail_n = 0;
        txcyc  = 0; rdcyc  = 0;
        trace_on   = 1'b0;
        w_prev = 8'hxx; h_prev = 8'hxx; w_run = 0; h_run = 0;
        frames_out = 0; rcvd_n = 0; last_len = 0;
        sent_n     = 0;
        carrier_cyc = 0;

        $display("");
        $display("#############################################################");
        $display("#     ethernet_mac_loopback_tb - TX pins wired to RX pins   #");
        $display("#############################################################");
        $display("  gmii_txd -> gmii_rxd, tx_en -> rx_dv, tx_er -> rx_er");
        $display("  host write clock %0.1f ns, wire %0.1f ns, host read %0.1f ns",
                 WRP, TXP, RDP);
        $display("  MIN_FRAME_LEN %0d (802.3 4.4.2), RX FIFO %0d octets",
                 MINLEN, (1 << RX_ADDR_W));
        $display("  No reference frame. No golden model. Just octets in and out.");

        suite1;

        $display("");
        $display("=====================================================");
        $display(" SUITE 2 BASIC - clean loopback");
        $display("=====================================================");
        t2_1; t2_2; t2_3; t2_4; t2_5; t2_6;

        $display("");
        $display("=====================================================");
        $display(" SUITE 2 BASIC - channel error injection");
        $display("=====================================================");
        t2_7;  t2_8;  t2_9;  t2_10; t2_11; t2_12; t2_13; t2_14;
        t2_15; t2_16;

        $display("");
        $display("=====================================================");
        $display(" SUITE 2 BASIC - throughput, payload traps, sweeps");
        $display("=====================================================");
        t2_17; t2_18; t2_19; t2_20; t2_21; t2_22; t2_23; t2_24;

        $display("");
        $display("=====================================================");
        $display(" RESULT : %0d passed, %0d failed, %0d total",
                 pass_n, fail_n, pass_n + fail_n);
        if (fail_n == 0)
            $display(" ethernet_mac_loopback_tb : ALL CHECKS PASS");
        else
            $display(" ethernet_mac_loopback_tb : FAILURES PRESENT");
        $display("=====================================================");
        $display("");
        $finish;
    end

    initial begin
        #200000000;
        $display("");
        $display(" TIMEOUT - watchdog fired at %0t", $time);
        $display(" RESULT : %0d passed, %0d failed", pass_n, fail_n);
        $finish;
    end

endmodule

`default_nettype wire

