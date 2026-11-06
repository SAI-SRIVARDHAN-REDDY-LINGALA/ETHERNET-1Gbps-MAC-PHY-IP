// rx_mac_controller_tb - Full RX chain tests, pins to AXI.

`timescale 1ns / 1ps
`default_nettype none

module rx_mac_controller_tb;

    localparam real RXP = 8.0;
    localparam real RDP = 10.0;

    localparam integer ADDR_W = 6;
    localparam integer MINLEN = 3;
    localparam integer MAXLEN = 1514;

    reg        rx_clk;
    reg        rx_rst_n;
    reg        speed_select;
    reg  [7:0] gmii_rxd;
    reg        gmii_rx_dv;
    reg        gmii_rx_er;

    reg        rd_clk;
    reg        rd_rst_n;
    wire [7:0] m_axis_tdata;
    wire       m_axis_tvalid;
    reg        m_axis_tready;
    wire       m_axis_tlast;
    wire       frame_avail_out;

    wire       frame_rcvd_out;
    wire       frame_drop_out;
    wire       overflow_out;
    wire       crc_err_out;
    wire       len_err_out;
    wire       phy_err_out;
    wire       no_sfd_out;
    wire       sfd_seen_out;
    wire       frame_ok_out;
    wire[10:0] frame_len_out;

    rx_mac_controller #(
        .DATA_W        (8),
        .FIFO_ADDR_W   (ADDR_W),
        .MIN_FRAME_LEN (MINLEN),
        .MAX_FRAME_LEN (MAXLEN),
        .PREAMBLE_BYTE (8'h55),
        .SFD_BYTE      (8'hD5),
        .PRE_MAX       (32)
    ) dut (
        .rx_clk          (rx_clk),
        .rx_rst_n        (rx_rst_n),
        .speed_select    (speed_select),
        .gmii_rxd        (gmii_rxd),
        .gmii_rx_dv      (gmii_rx_dv),
        .gmii_rx_er      (gmii_rx_er),

        .rd_clk          (rd_clk),
        .rd_rst_n        (rd_rst_n),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tlast    (m_axis_tlast),
        .frame_avail_out (frame_avail_out),

        .frame_rcvd_out  (frame_rcvd_out),
        .frame_drop_out  (frame_drop_out),
        .overflow_out    (overflow_out),
        .crc_err_out     (crc_err_out),
        .len_err_out     (len_err_out),
        .phy_err_out     (phy_err_out),
        .no_sfd_out      (no_sfd_out),
        .sfd_seen_out    (sfd_seen_out),
        .frame_ok_out    (frame_ok_out),
        .frame_len_out   (frame_len_out)
    );

    reg  [31:0] ref_crc;
    reg  [7:0]  ref_byte;
    wire [31:0] ref_next;

    crc32_parallel u_ref (
        .crc_in   (ref_crc),
        .data_in  (ref_byte),
        .crc_out  (ref_next)
    );

    initial begin rx_clk = 1'b0; forever #(RXP/2.0) rx_clk = ~rx_clk; end
    initial begin rd_clk = 1'b0; forever #(RDP/2.0) rd_clk = ~rd_clk; end

    integer pass_n, fail_n;

    task ck;
        input        cond;
        input [1023:0] msg;
        begin
            if (cond) begin
                pass_n = pass_n + 1;
                $display("    PASS : %0s", msg);
            end else begin
                fail_n = fail_n + 1;
                $display("    FAIL : %0s", msg);
            end
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
                $display("    FAIL : %0s - got %0d, expected %0d",
                         msg, got, exp);
            end
        end
    endtask

    reg [7:0]  body [0:1600];
    integer    blen;

    reg [31:0] fcs;

    task compute_fcs;
        integer k;
        begin
            ref_crc = 32'hFFFFFFFF;
            for (k = 0; k < blen; k = k + 1) begin
                ref_byte = body[k];
                #0;
                ref_crc  = ref_next;
            end
            fcs = ~ref_crc;
        end
    endtask

    task make_body;
        input integer n;
        input [7:0]   first;
        integer k;
        begin
            blen = n;
            for (k = 0; k < n; k = k + 1) body[k] = first + k[7:0];
            compute_fcs;
        end
    endtask

    task pin;
        input [7:0] d;
        input       er;
        begin
            @(negedge rx_clk);
            gmii_rxd   <= d;
            gmii_rx_dv <= 1'b1;
            gmii_rx_er <= er;
        end
    endtask

    task pins_idle;
        input integer n;
        integer k;
        begin
            @(negedge rx_clk);
            gmii_rxd   <= 8'h00;
            gmii_rx_dv <= 1'b0;
            gmii_rx_er <= 1'b0;
            for (k = 0; k < n; k = k + 1) @(negedge rx_clk);
        end
    endtask

    task send_frame;
        input integer npre;
        input         send_sfd;
        input integer corrupt_i;
        input         fcs_rev;
        input integer er_i;
        integer k;
        reg [7:0] b;
        begin
            for (k = 0; k < npre; k = k + 1) pin(8'h55, 1'b0);
            if (send_sfd) pin(8'hD5, 1'b0);

            for (k = 0; k < blen; k = k + 1) begin
                b = body[k];
                if (k == corrupt_i) b = b ^ 8'h01;
                pin(b, (k == er_i) ? 1'b1 : 1'b0);
            end

            if (fcs_rev) begin
                pin(fcs[31:24], 1'b0);
                pin(fcs[23:16], 1'b0);
                pin(fcs[15:8],  1'b0);
                pin(fcs[7:0],   1'b0);
            end else begin
                pin(fcs[7:0],   1'b0);
                pin(fcs[15:8],  1'b0);
                pin(fcs[23:16], 1'b0);
                pin(fcs[31:24], 1'b0);
            end

            pins_idle(4);
        end
    endtask

    task send_clean;
        begin
            send_frame(7, 1'b1, -1, 1'b0, -1);
        end
    endtask

    reg [7:0]  got  [0:2047];
    integer    got_n;
    integer    frames_out;
    reg [7:0]  last_frame [0:2047];
    integer    last_len;

    integer    ord_err;
    integer    rcv_i;

    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            got_n      = 0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            if (got_n < 2048) got[got_n] = m_axis_tdata;
            got_n = got_n + 1;

            if (m_axis_tlast) begin
                last_len = got_n;
                for (rcv_i = 0; rcv_i < got_n; rcv_i = rcv_i + 1)
                    last_frame[rcv_i] = got[rcv_i];
                frames_out = frames_out + 1;
                got_n      = 0;
            end
        end
    end

    integer n_rcvd, n_drop, n_ovf, n_crcerr, n_lenerr, n_phyerr;
    integer n_nosfd, n_sfd, n_ok;

    always @(posedge rx_clk) begin
        if (!rx_rst_n) begin
            n_rcvd = 0; n_drop = 0; n_ovf = 0; n_crcerr = 0;
            n_lenerr = 0; n_phyerr = 0; n_nosfd = 0; n_sfd = 0; n_ok = 0;
        end else begin
            if (frame_rcvd_out) n_rcvd   = n_rcvd   + 1;
            if (frame_drop_out) n_drop   = n_drop   + 1;
            if (overflow_out)   n_ovf    = n_ovf    + 1;
            if (crc_err_out)    n_crcerr = n_crcerr + 1;
            if (len_err_out)    n_lenerr = n_lenerr + 1;
            if (phy_err_out)    n_phyerr = n_phyerr + 1;
            if (no_sfd_out)     n_nosfd  = n_nosfd  + 1;
            if (sfd_seen_out)   n_sfd    = n_sfd    + 1;
            if (frame_ok_out)   n_ok     = n_ok     + 1;
        end
    end

    task clear_counts;
        begin
            #0.1;
            n_rcvd = 0; n_drop = 0; n_ovf = 0; n_crcerr = 0;
            n_lenerr = 0; n_phyerr = 0; n_nosfd = 0; n_sfd = 0; n_ok = 0;
            frames_out = 0; last_len = 0; ord_err = 0;
        end
    endtask

    task settle;
        integer k;
        begin
            for (k = 0; k < 300; k = k + 1) @(posedge rd_clk);
        end
    endtask

    task do_reset;
        begin
            rx_rst_n      = 1'b0;
            rd_rst_n      = 1'b0;
            speed_select  = 1'b1;
            gmii_rxd      = 8'h00;
            gmii_rx_dv    = 1'b0;
            gmii_rx_er    = 1'b0;
            m_axis_tready = 1'b1;
            repeat (6) @(posedge rx_clk);
            @(negedge rx_clk);
            rx_rst_n = 1'b1;
            rd_rst_n = 1'b1;
            repeat (4) @(posedge rd_clk);
        end
    endtask

    task check_last_frame;
        input [1023:0] tag;
        integer k, bad;
        begin
            bad = 0;
            for (k = 0; k < blen; k = k + 1)
                if (last_frame[k] !== body[k]) bad = bad + 1;
            ck_eq(last_len, blen, {tag, " : delivered length"});
            ck_eq(bad,      0,    {tag, " : octet mismatches"});
        end
    endtask

    integer rxcyc, rdcyc;
    reg     trace_on;

    always @(posedge rx_clk) begin
        rxcyc = rxcyc + 1;
        if (trace_on)
            $display("  P%0d | RXD=%02h DV=%0b | preV=%0b preD=%02h | fcsV=%0b fcsD=%02h L=%0b | OK=%0b ER=%0b",
                     rxcyc, gmii_rxd, gmii_rx_dv,
                     dut.pre_valid, dut.pre_data,
                     dut.fcs_valid, dut.fcs_data, dut.fcs_last,
                     dut.fcs_crc_ok, dut.crc_err_out);
    end

    always @(posedge rd_clk) begin
        rdcyc = rdcyc + 1;
        if (trace_on && (m_axis_tvalid || frame_avail_out))
            $display("       H%0d | TDATA=%02h TV=%0b TR=%0b TL=%0b | avail=%0b",
                     rdcyc, m_axis_tdata, m_axis_tvalid,
                     m_axis_tready, m_axis_tlast, frame_avail_out);
    end

    task suite1;
        begin
            $display("");
            $display("=====================================================");
            $display(" SUITE 1 SIMPLE - GMII pins to AXI host, one frame");
            $display("=====================================================");
            $display(" GMII, 7 preamble octets, 4-octet body 'abcd'.");
            $display(" 16 octets go on the pins. 4 must come out.");
            $display("");

            do_reset;
            clear_counts;

            blen = 4;
            body[0] = 8'h61; body[1] = 8'h62;
            body[2] = 8'h63; body[3] = 8'h64;
            compute_fcs;
            $display("  body = 61 62 63 64   FCS = %08h", fcs);
            $display("  wire order (low octet first) : %02h %02h %02h %02h",
                     fcs[7:0], fcs[15:8], fcs[23:16], fcs[31:24]);
            $display("");
            $display("  P<n> = RX_CLK cycle n (PHY side)");
            $display("  H<n> = rd_clk cycle n (host side), printed only when busy");
            $display("");

            trace_on = 1'b1;
            send_clean;
            settle;
            trace_on = 1'b0;

            $display("");
            $display("  frames delivered  : %0d", frames_out);
            $display("  delivered length  : %0d", last_len);
            $display("  frame_len_out     : %0d", frame_len_out);
            $display("  sfd_seen pulses   : %0d", n_sfd);
            $display("  frame_rcvd pulses : %0d", n_rcvd);
            $display("  crc_err pulses    : %0d", n_crcerr);
            $display("");
        end
    endtask

    task t2_1;
        begin
            $display("");
            $display(" TEST 2.1 - reset state");
            do_reset;
            clear_counts;
            ck(m_axis_tvalid   === 1'b0, "tvalid low after reset");
            ck(frame_avail_out === 1'b0, "frame_avail_out low after reset");

        end
    endtask

    task t2_2;
        begin
            $display("");
            $display(" TEST 2.2 - clean 60-octet frame survives all four stages");
            do_reset;
            clear_counts;
            make_body(60, 8'h10);
            send_clean;
            settle;
            ck_eq(frames_out, 1, "exactly one frame delivered");
            check_last_frame("2.2");
            ck_eq(n_rcvd,   1, "frame_rcvd_out pulsed once");
            ck_eq(n_crcerr, 0, "no crc_err_out");
            ck_eq(n_drop,   0, "no frame_drop_out");
            ck_eq(n_sfd,    1, "sfd_seen_out pulsed once");
            ck_eq(n_ok,     1, "frame_ok_out pulsed once");
            ck_eq(frame_len_out, 60, "frame_len_out reports the body length");
        end
    endtask

    task t2_3;
        integer k;
        begin
            $display("");
            $display(" TEST 2.3 - 'abc' zero-padded to 60 (what tx_padding emits)");
            do_reset;
            clear_counts;
            blen = 60;
            body[0] = 8'h61; body[1] = 8'h62; body[2] = 8'h63;
            for (k = 3; k < 60; k = k + 1) body[k] = 8'h00;
            compute_fcs;
            send_clean;
            settle;
            ck_eq(frames_out, 1, "one frame delivered");
            ck_eq(last_len,  60, "60 octets delivered, not 3");
            ck(last_frame[0] === 8'h61, "octet 0 is 'a'");
            ck(last_frame[1] === 8'h62, "octet 1 is 'b'");
            ck(last_frame[2] === 8'h63, "octet 2 is 'c'");
            ck(last_frame[3] === 8'h00, "octet 3 is a pad zero");
            ck(last_frame[59] === 8'h00, "octet 59 is a pad zero");
        end
    endtask

    task t2_4;
        begin
            $display("");
            $display(" TEST 2.4 - one flipped bit erases the frame");
            do_reset;
            clear_counts;
            make_body(60, 8'h20);
            send_frame(7, 1'b1, 30, 1'b0, -1);
            settle;
            ck_eq(frames_out, 0, "NOTHING delivered to the host");
            ck_eq(n_crcerr,   1, "crc_err_out pulsed");
            ck_eq(n_drop,     1, "frame_drop_out pulsed");
            ck_eq(n_rcvd,     0, "frame_rcvd_out did NOT pulse");
            ck_eq(n_ovf,      0, "it was a CRC drop, not an overflow");
            ck(m_axis_tvalid === 1'b0, "tvalid still low");
        end
    endtask

    task t2_5;
        begin
            $display("");
            $display(" TEST 2.5 - a good frame immediately after a bad one");
            do_reset;
            clear_counts;

            make_body(60, 8'h30);
            send_frame(7, 1'b1, 5, 1'b0, -1);
            settle;
            ck_eq(frames_out, 0, "the bad frame delivered nothing");

            make_body(60, 8'h40);
            send_clean;
            settle;
            ck_eq(frames_out, 1, "the good frame arrived");
            check_last_frame("2.5");
            ck_eq(n_drop, 1, "exactly one drop in total");
            ck_eq(n_rcvd, 1, "exactly one commit in total");
        end
    endtask

    task t2_6;
        integer f;
        begin
            $display("");
            $display(" TEST 2.6 - alternating good/bad x5 -> only 3 arrive");
            do_reset;
            clear_counts;
            for (f = 0; f < 5; f = f + 1) begin
                make_body(20, 8'h50 + f[7:0]*8'd20);
                if (f[0]) send_frame(7, 1'b1, 4, 1'b0, -1);
                else      send_clean;
                settle;
            end
            ck_eq(frames_out, 3, "3 of 5 frames delivered");
            ck_eq(n_rcvd,     3, "3 commits");
            ck_eq(n_drop,     2, "2 drops");

            check_last_frame("2.6");
        end
    endtask

    task t2_7;
        begin
            $display("");
            $display(" TEST 2.7 - 3-octet preamble accepted (clause 4.2.4.2.1)");
            do_reset;
            clear_counts;
            make_body(60, 8'h60);
            send_frame(3, 1'b1, -1, 1'b0, -1);
            settle;
            ck_eq(frames_out, 1, "frame delivered with only 3 preamble octets");
            check_last_frame("2.7");
        end
    endtask

    task t2_8;
        begin
            $display("");
            $display(" TEST 2.8 - zero preamble octets, carrier opens on the SFD");
            do_reset;
            clear_counts;
            make_body(60, 8'h70);
            send_frame(0, 1'b1, -1, 1'b0, -1);
            settle;
            ck_eq(frames_out, 1, "frame delivered with no preamble at all");
            check_last_frame("2.8");
        end
    endtask

    task t2_9;
        begin
            $display("");
            $display(" TEST 2.9 - runt with a GOOD CRC is still rejected");
            do_reset;
            clear_counts;
            blen = 2;
            body[0] = 8'hAA; body[1] = 8'hBB;
            compute_fcs;
            send_clean;
            settle;
            ck_eq(frames_out, 0, "NOTHING delivered");
            ck_eq(n_lenerr,   1, "len_err_out pulsed");
            ck_eq(n_crcerr,   1, "crc_err_out pulsed too (len folds into it)");
            ck_eq(n_rcvd,     0, "no commit");
        end
    endtask

    task t2_10;
        begin
            $display("");
            $display(" TEST 2.10 - carrier with preamble but no SFD");
            do_reset;
            clear_counts;
            make_body(20, 8'h80);
            send_frame(10, 1'b0, -1, 1'b0, -1);
            settle;
            ck_eq(frames_out, 0, "nothing delivered");
            ck_eq(n_nosfd,    1, "no_sfd_out pulsed");
            ck_eq(n_sfd,      0, "sfd_seen_out did NOT pulse");
            ck_eq(n_ok,       0, "frame_ok_out did NOT pulse");
            ck_eq(n_crcerr,   0, "rx_fcs never even saw a frame");
        end
    endtask

    task t2_11;
        begin
            $display("");
            $display(" TEST 2.11 - FCS sent HIGH octet first must be rejected");
            do_reset;
            clear_counts;
            make_body(60, 8'h90);
            send_frame(7, 1'b1, -1, 1'b1, -1);
            settle;
            ck_eq(frames_out, 0, "reversed FCS rejected");
            ck_eq(n_crcerr,   1, "crc_err_out pulsed");
            ck_eq(n_rcvd,     0, "no commit");
        end
    endtask

    task t2_12;
        begin
            $display("");
            $display(" TEST 2.12 - RX_ER mid-frame drops an otherwise good frame");
            do_reset;
            clear_counts;
            make_body(60, 8'hA0);
            send_frame(7, 1'b1, -1, 1'b0, 25);
            settle;
            ck_eq(frames_out, 0, "nothing delivered");
            ck_eq(n_phyerr,   1, "phy_err_out pulsed");
            ck_eq(n_crcerr,   1, "crc_err_out pulsed (phy_err folds into it)");
            ck_eq(n_rcvd,     0, "no commit");
        end
    endtask

    task t2_13;
        integer k;
        begin
            $display("");
            $display(" TEST 2.13 - host holds tready low, then drains");
            do_reset;
            clear_counts;
            m_axis_tready = 1'b0;
            make_body(20, 8'hB0);
            send_clean;
            for (k = 0; k < 60; k = k + 1) @(posedge rd_clk);
            ck(m_axis_tvalid === 1'b1,
               "tvalid asserted while tready is low (AXI rule)");
            ck_eq(frames_out, 0, "nothing consumed yet");
            @(negedge rd_clk);
            m_axis_tready = 1'b1;
            settle;
            ck_eq(frames_out, 1, "frame drains once tready rises");
            check_last_frame("2.13");
        end
    endtask

    task t2_14;
        integer k;
        begin
            $display("");
            $display(" TEST 2.14 - choppy consumer, tready every other cycle");
            do_reset;
            clear_counts;
            make_body(40, 8'hC0);

            fork
                begin
                    send_clean;
                    settle;
                end
                begin
                    for (k = 0; k < 400; k = k + 1) begin
                        @(negedge rd_clk);
                        m_axis_tready = ~m_axis_tready;
                    end
                end
            join

            m_axis_tready = 1'b1;
            settle;
            ck_eq(frames_out, 1, "frame delivered through a choppy consumer");
            check_last_frame("2.14");
        end
    endtask

    task t2_15;
        begin
            $display("");
            $display(" TEST 2.15 - two frames back to back, no gap for the host");
            do_reset;
            clear_counts;
            make_body(20, 8'hD0);
            send_clean;
            make_body(20, 8'hE0);
            send_clean;
            settle;
            ck_eq(frames_out, 2, "both frames delivered");
            ck_eq(n_rcvd,     2, "two commits");
            check_last_frame("2.15");
        end
    endtask

    task t2_16;
        begin
            $display("");
            $display(" TEST 2.16 - junk carrier cannot wedge the chain");
            do_reset;
            clear_counts;
            make_body(20, 8'h11);
            send_frame(6, 1'b0, -1, 1'b0, -1);
            settle;
            ck_eq(frames_out, 0, "junk delivered nothing");

            make_body(20, 8'h22);
            send_clean;
            settle;
            ck_eq(frames_out, 1, "the receiver still works");
            check_last_frame("2.16");
        end
    endtask

    task t2_17;
        begin
            $display("");
            $display(" TEST 2.17 - a MINLEN-octet body (the smallest legal frame)");
            do_reset;
            clear_counts;
            make_body(MINLEN, 8'h33);
            send_clean;
            settle;
            ck_eq(frames_out, 1, "smallest legal frame delivered");
            check_last_frame("2.17");
            ck_eq(n_lenerr, 0, "not flagged as a runt");
        end
    endtask

    task t2_18;
        begin
            $display("");
            $display(" TEST 2.18 - oversized frame drops WHOLE, then recovery");
            do_reset;
            clear_counts;
            m_axis_tready = 1'b0;
            make_body(70, 8'h44);
            send_clean;
            settle;
            ck_eq(n_ovf,      1, "overflow_out pulsed");
            ck_eq(n_drop,     1, "frame_drop_out pulsed");
            ck_eq(n_rcvd,     0, "frame_rcvd_out did NOT pulse");
            @(negedge rd_clk);
            m_axis_tready = 1'b1;
            settle;
            ck_eq(frames_out, 0, "NOTHING delivered - not a truncated frame");

            clear_counts;
            make_body(20, 8'h55);
            send_clean;
            settle;
            ck_eq(frames_out, 1, "the chain recovered after the overflow");
            check_last_frame("2.18");
        end
    endtask

    task t2_19;
        begin
            $display("");
            $display(" TEST 2.19 - 20-octet preamble accepted");
            do_reset;
            clear_counts;
            make_body(30, 8'h66);
            send_frame(20, 1'b1, -1, 1'b0, -1);
            settle;
            ck_eq(frames_out, 1, "frame delivered with a 20-octet preamble");
            check_last_frame("2.19");
        end
    endtask

    task t2_20;
        integer k;
        begin
            $display("");
            $display(" TEST 2.20 - 0x55 / 0xD5 inside the payload pass through");
            do_reset;
            clear_counts;
            blen = 20;
            for (k = 0; k < 20; k = k + 1)
                body[k] = (k[0]) ? 8'hD5 : 8'h55;
            compute_fcs;
            send_clean;
            settle;
            ck_eq(frames_out, 1, "frame of alternating 55/D5 delivered");
            check_last_frame("2.20");
        end
    endtask

    task t2_21;
        integer k, bad;
        begin
            $display("");
            $display(" TEST 2.21 - DEPTH-octet frame, ordering and length");
            do_reset;
            clear_counts;

            make_body((1 << ADDR_W), 8'h00);
            send_clean;
            settle;
            ck_eq(frames_out, 1, "one frame delivered");
            ck_eq(last_len, (1 << ADDR_W), "exactly DEPTH octets delivered");
            bad = 0;
            for (k = 0; k < blen; k = k + 1)
                if (last_frame[k] !== body[k]) bad = bad + 1;
            ck_eq(bad, 0, "every octet in the right place");
            ck_eq(frame_len_out, (1 << ADDR_W), "frame_len_out agrees");
            ck_eq(n_ovf, 0, "DEPTH octets did NOT overflow");
        end
    endtask

    initial begin
        $dumpfile("rx_mac_controller_tb.vcd");
        $dumpvars(0, rx_mac_controller_tb);

        pass_n = 0; fail_n = 0;
        rxcyc  = 0; rdcyc  = 0;
        trace_on   = 1'b0;
        frames_out = 0;
        got_n      = 0;
        last_len   = 0;
        ord_err    = 0;

        $display("");
        $display("#############################################################");
        $display("#  rx_mac_controller_tb - the whole RX chain, pins to host  #");
        $display("#############################################################");
        $display("  GMII mode, RX_CLK %0.1f ns, host clock %0.1f ns", RXP, RDP);
        $display("  FIFO DEPTH %0d, MIN_FRAME_LEN %0d", (1<<ADDR_W), MINLEN);

        suite1;

        $display("");
        $display("=====================================================");
        $display(" SUITE 2 BASIC - functional");
        $display("=====================================================");

        t2_1;  t2_2;  t2_3;  t2_4;  t2_5;
        t2_6;  t2_7;  t2_8;  t2_9;  t2_10;
        t2_11; t2_12; t2_13; t2_14; t2_15;
        t2_16; t2_17; t2_18; t2_19; t2_20;
        t2_21;

        $display("");
        $display("=====================================================");
        $display(" RESULT : %0d passed, %0d failed, %0d total",
                 pass_n, fail_n, pass_n + fail_n);
        if (fail_n == 0) $display(" rx_mac_controller_tb : ALL CHECKS PASS");
        else             $display(" rx_mac_controller_tb : FAILURES PRESENT");
        $display("=====================================================");
        $display("");
        $finish;
    end

    initial begin
        #4000000;
        $display("");
        $display(" TIMEOUT - watchdog fired at %0t", $time);
        $display(" RESULT : %0d passed, %0d failed", pass_n, fail_n);
        $finish;
    end

endmodule

`default_nettype wire

