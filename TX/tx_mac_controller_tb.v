// tx_mac_controller_advanced_tb - Advanced full TX chain tests.

`timescale 1ns / 1ps
`default_nettype none

module tx_mac_controller_advanced_tb;

    localparam integer MIN_LEN = 60;
    localparam integer RXMAX   = 262144;
    localparam integer FRMAX   = 512;

    reg         wr_clk;
    reg         wr_rst_n;
    reg  [7:0]  s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg         s_axis_tlast;
    wire        frame_drop_out;

    reg         tx_clk;
    reg         tx_rst_n;
    reg         speed_select;

    wire [7:0]  gmii_txd;
    wire        gmii_tx_en;
    wire        gmii_tx_er;

    wire        frame_sent_out;
    wire        underrun_out;
    wire        tx_busy_out;

    tx_mac_controller #(
        .DATA_W        (8),
        .FIFO_ADDR_W   (11),
        .MIN_FRAME_LEN (MIN_LEN),
        .PREAMBLE_LEN  (7),
        .IFG_BIT_TIMES (96),
        .ERR_CYCLES    (2)
    ) dut (
        .wr_clk         (wr_clk),
        .wr_rst_n       (wr_rst_n),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .frame_drop_out (frame_drop_out),

        .tx_clk         (tx_clk),
        .tx_rst_n       (tx_rst_n),
        .speed_select   (speed_select),

        .gmii_txd       (gmii_txd),
        .gmii_tx_en     (gmii_tx_en),
        .gmii_tx_er     (gmii_tx_er),

        .frame_sent_out (frame_sent_out),
        .underrun_out   (underrun_out),
        .tx_busy_out    (tx_busy_out)
    );

    real wr_half;
    real tx_half;

    initial begin wr_clk = 1'b0; forever #(wr_half) wr_clk = ~wr_clk; end
    initial begin tx_clk = 1'b0; forever #(tx_half) tx_clk = ~tx_clk; end

    integer pass_n;
    integer fail_n;

    task check;
        input [119*8:0] name;
        input           cond;
        begin
            if (cond) begin
                pass_n = pass_n + 1;
                $display("PASS : %0s", name);
            end else begin
                fail_n = fail_n + 1;
                $display("FAIL : %0s", name);
            end
        end
    endtask

    reg  [7:0] rx_flat [0:RXMAX-1];
    integer    rx_start [0:FRMAX-1];
    integer    rx_len   [0:FRMAX-1];
    integer    rx_cyc   [0:FRMAX-1];
    integer    rx_gap   [0:FRMAX-1];
    integer    rx_er    [0:FRMAX-1];
    integer    rx_n;
    integer    rx_ptr;

    reg        in_burst;
    integer    en_run;
    integer    idle_run;
    reg        nib_mode;
    reg        nib_ph;
    reg  [3:0] nib_lo;

    integer    sent_cnt;
    integer    und_cnt;
    integer    drop_cnt;

    always @(posedge tx_clk) begin
        if (!tx_rst_n) begin
            in_burst = 1'b0;
            en_run   = 0;
            idle_run = 0;
            nib_ph   = 1'b0;
        end else begin
            if (gmii_tx_en) begin
                if (!in_burst) begin
                    in_burst = 1'b1;
                    nib_ph   = 1'b0;
                    if (rx_n < FRMAX) begin
                        rx_start[rx_n] = rx_ptr;
                        rx_gap[rx_n]   = idle_run;
                        rx_er[rx_n]    = 0;
                    end
                end

                if (nib_mode) begin
                    if (!nib_ph) begin
                        nib_lo = gmii_txd[3:0];
                        nib_ph = 1'b1;
                    end else begin
                        if (rx_ptr < RXMAX) begin
                            rx_flat[rx_ptr] = {gmii_txd[3:0], nib_lo};
                            rx_ptr = rx_ptr + 1;
                        end
                        nib_ph = 1'b0;
                    end
                end else begin
                    if (rx_ptr < RXMAX) begin
                        rx_flat[rx_ptr] = gmii_txd;
                        rx_ptr = rx_ptr + 1;
                    end
                end

                if (gmii_tx_er && (rx_n < FRMAX))
                    rx_er[rx_n] = rx_er[rx_n] + 1;

                en_run   = en_run + 1;
                idle_run = 0;
            end else begin
                if (in_burst) begin
                    if (rx_n < FRMAX) begin
                        rx_cyc[rx_n] = en_run;
                        rx_len[rx_n] = rx_ptr - rx_start[rx_n];
                        rx_n = rx_n + 1;
                    end
                    in_burst = 1'b0;
                end
                en_run   = 0;
                idle_run = idle_run + 1;
            end

            if (frame_sent_out) sent_cnt = sent_cnt + 1;
            if (underrun_out)   und_cnt  = und_cnt  + 1;
        end
    end

    always @(posedge wr_clk) begin
        if (wr_rst_n && frame_drop_out) drop_cnt = drop_cnt + 1;
    end

    integer v_crc_after_eof;
    integer v_init_dv;
    integer v_ifg_start_bad;
    integer v_launch_bad;
    integer v_flush_crc;
    integer v_carrier_ext;
    integer v_pre_notsof;
    integer v_mii_hinib;
    integer n_prefetch;
    integer n_launch;

    always @(posedge tx_clk) begin
        if (tx_rst_n) begin

            if (dut.pay_e && dut.fcs_dv)
                v_crc_after_eof = v_crc_after_eof + 1;

            if (dut.fcs_init && dut.fcs_dv)
                v_init_dv = v_init_dv + 1;

            if (dut.ifg_start && dut.ifg_active)
                v_ifg_start_bad = v_ifg_start_bad + 1;

            if (dut.launch && (dut.ifg_active || dut.phy_frame_done))
                v_launch_bad = v_launch_bad + 1;

            if ((dut.state == 3'd6) && dut.fcs_dv)
                v_flush_crc = v_flush_crc + 1;

            if (gmii_tx_er && !gmii_tx_en)
                v_carrier_ext = v_carrier_ext + 1;

            if ((dut.state == 3'd1) && dut.pad_xfer) begin
                n_prefetch = n_prefetch + 1;
                if (!dut.pad_sof) v_pre_notsof = v_pre_notsof + 1;
            end

            if (dut.launch) n_launch = n_launch + 1;

            if (nib_mode && gmii_tx_en && (gmii_txd[7:4] !== 4'h0))
                v_mii_hinib = v_mii_hinib + 1;
        end
    end

    function [31:0] crc_step;
        input [31:0] c;
        input [7:0]  d;
        reg   [31:0] t;
        integer      i;
        begin
            t = c;
            for (i = 0; i < 8; i = i + 1) begin
                if ((t[0] ^ d[i]) == 1'b1) t = {1'b0, t[31:1]} ^ 32'hEDB88320;
                else                       t = {1'b0, t[31:1]};
            end
            crc_step = t;
        end
    endfunction

    reg  [7:0] pay_q [0:RXMAX-1];
    integer    pay_n;

    integer    snd_base [0:FRMAX-1];
    integer    snd_len  [0:FRMAX-1];
    integer    snd_n;

    reg  [7:0] ex_flat [0:RXMAX-1];
    integer    ex_start [0:FRMAX-1];
    integer    ex_len   [0:FRMAX-1];
    integer    ex_n;
    integer    ex_ptr;

    task q_clr;
        begin
            rx_n   = 0;  rx_ptr = 0;
            ex_n   = 0;  ex_ptr = 0;
            snd_n  = 0;
            pay_n  = 0;
        end
    endtask

    task ex_push;
        input integer base;
        input integer n;
        integer      i, tot;
        reg   [31:0] c, f;
        begin
            if (ex_n < FRMAX) begin
                ex_start[ex_n] = ex_ptr;

                for (i = 0; i < 7; i = i + 1) begin
                    ex_flat[ex_ptr] = 8'h55; ex_ptr = ex_ptr + 1;
                end
                ex_flat[ex_ptr] = 8'hD5; ex_ptr = ex_ptr + 1;

                c   = 32'hFFFF_FFFF;
                tot = 0;
                for (i = 0; i < n; i = i + 1) begin
                    ex_flat[ex_ptr] = pay_q[base+i]; ex_ptr = ex_ptr + 1;
                    c   = crc_step(c, pay_q[base+i]);
                    tot = tot + 1;
                end
                while (tot < MIN_LEN) begin
                    ex_flat[ex_ptr] = 8'h00; ex_ptr = ex_ptr + 1;
                    c   = crc_step(c, 8'h00);
                    tot = tot + 1;
                end

                f = ~c;
                ex_flat[ex_ptr] = f[7:0];   ex_ptr = ex_ptr + 1;
                ex_flat[ex_ptr] = f[15:8];  ex_ptr = ex_ptr + 1;
                ex_flat[ex_ptr] = f[23:16]; ex_ptr = ex_ptr + 1;
                ex_flat[ex_ptr] = f[31:24]; ex_ptr = ex_ptr + 1;

                ex_len[ex_n] = ex_ptr - ex_start[ex_n];
                ex_n = ex_n + 1;
            end
        end
    endtask

    task ex_build_all;
        integer f;
        begin
            for (f = 0; f < snd_n; f = f + 1) ex_push(snd_base[f], snd_len[f]);
        end
    endtask

    task verify_all;
        input [119*8:0] name;
        integer f, i, bad, shown;
        begin
            bad = 0; shown = 0;
            if (rx_n !== ex_n) begin
                $display("       frame count: received %0d, expected %0d",
                         rx_n, ex_n);
                bad = bad + 1;
            end
            for (f = 0; (f < rx_n) && (f < ex_n); f = f + 1) begin
                if (rx_len[f] !== ex_len[f]) begin
                    bad = bad + 1;
                    if (shown < 5) begin
                        $display("       frame %0d length: got %0d, want %0d",
                                 f, rx_len[f], ex_len[f]);
                        shown = shown + 1;
                    end
                end
                for (i = 0; (i < rx_len[f]) && (i < ex_len[f]); i = i + 1) begin
                    if (rx_flat[rx_start[f]+i] !== ex_flat[ex_start[f]+i]) begin
                        bad = bad + 1;
                        if (shown < 5) begin
                            $display("       frame %0d octet %0d: got %02h, want %02h",
                                     f, i, rx_flat[rx_start[f]+i],
                                     ex_flat[ex_start[f]+i]);
                            shown = shown + 1;
                        end
                    end
                end
            end
            check(name, bad === 0);
        end
    endtask

    task verify_gaps;
        input [119*8:0] name;
        input integer   minc;
        integer f, bad, worst;
        begin
            bad = 0; worst = 1000000;

            for (f = 1; f < rx_n; f = f + 1) begin
                if (rx_gap[f] < worst) worst = rx_gap[f];
                if (rx_gap[f] < minc)  bad   = bad + 1;
            end
            if (rx_n > 1)
                $display("       tightest gap over %0d frames = %0d cycles (%0d bit times, min %0d)",
                         rx_n, worst, worst * (minc == 24 ? 4 : 8), minc);
            check(name, bad === 0);
        end
    endtask

    task verify_clean;
        input [119*8:0] name;
        integer f, bad;
        begin
            bad = 0;
            for (f = 0; f < rx_n; f = f + 1) if (rx_er[f] !== 0) bad = bad + 1;
            check(name, bad === 0);
        end
    endtask

    task verify_nibble_cycles;
        input [119*8:0] name;
        integer f, bad;
        begin
            bad = 0;
            for (f = 0; f < rx_n; f = f + 1)
                if (rx_cyc[f] !== (2 * rx_len[f])) bad = bad + 1;
            check(name, bad === 0);
        end
    endtask

    function [31:0] residue_of;
        input integer f;
        integer i;
        reg [31:0] c;
        begin
            c = 32'hFFFF_FFFF;
            for (i = 8; i < rx_len[f]; i = i + 1)
                c = crc_step(c, rx_flat[rx_start[f]+i]);
            residue_of = c;
        end
    endfunction

    task frame_send;
        input integer n;
        input [7:0]   seed;
        integer i;
        begin
            if (snd_n < FRMAX) begin
                snd_base[snd_n] = pay_n;
                snd_len[snd_n]  = n;
                snd_n = snd_n + 1;
            end
            i = 0;
            while (i < n) begin
                @(negedge wr_clk);
                s_axis_tdata  = seed + i[7:0];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (i == (n-1));
                @(posedge wr_clk);
                if (s_axis_tready) begin
                    pay_q[pay_n] = seed + i[7:0];
                    pay_n = pay_n + 1;
                    i     = i + 1;
                end
            end
            @(negedge wr_clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    integer rseed;

    task frame_send_ragged;
        input integer n;
        input [7:0]   seed;
        integer i, hole, h;
        begin
            if (snd_n < FRMAX) begin
                snd_base[snd_n] = pay_n;
                snd_len[snd_n]  = n;
                snd_n = snd_n + 1;
            end
            i = 0;
            while (i < n) begin
                hole = {$random(rseed)} % 4;
                for (h = 0; h < hole; h = h + 1) begin
                    @(negedge wr_clk);
                    s_axis_tvalid = 1'b0;
                    s_axis_tlast  = 1'b0;
                end
                @(negedge wr_clk);
                s_axis_tdata  = seed + i[7:0];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (i == (n-1));
                @(posedge wr_clk);
                if (s_axis_tready) begin
                    pay_q[pay_n] = seed + i[7:0];
                    pay_n = pay_n + 1;
                    i     = i + 1;
                end
            end
            @(negedge wr_clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    task frame_send_unchecked;
        input integer n;
        input [7:0]   seed;
        integer i;
        begin
            i = 0;
            while (i < n) begin
                @(negedge wr_clk);
                s_axis_tdata  = seed + i[7:0];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (i == (n-1));
                @(posedge wr_clk);
                if (s_axis_tready) i = i + 1;
            end
            @(negedge wr_clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    task wait_quiet;
        input integer cyc;
        integer q, guard;
        begin
            q = 0; guard = 0;
            while ((q < cyc) && (guard < 4000000)) begin
                @(posedge tx_clk);
                guard = guard + 1;
                if (gmii_tx_en || tx_busy_out) q = 0;
                else                           q = q + 1;
            end
        end
    endtask

    initial begin
        #200_000_000;
        $display("FATAL: global timeout");
        $finish;
    end

    integer      k;
    integer      f;
    integer      bad;
    reg  [31:0]  res0;
    reg  [31:0]  resk;
    integer      dev_cnt;
    integer      dev_at;
    integer      lastb;
    integer      bitv;
    integer      base_sent;
    integer      base_und;
    integer      base_drop;

    initial begin
        $dumpfile("tx_mac_controller_tb.vcd");
        $dumpvars(0, tx_mac_controller_advanced_tb);

        pass_n = 0; fail_n = 0;
        rx_n = 0; rx_ptr = 0; ex_n = 0; ex_ptr = 0; snd_n = 0; pay_n = 0;
        in_burst = 1'b0; en_run = 0; idle_run = 0; nib_ph = 1'b0; nib_lo = 4'h0;
        sent_cnt = 0; und_cnt = 0; drop_cnt = 0;
        v_crc_after_eof = 0; v_init_dv = 0; v_ifg_start_bad = 0;
        v_launch_bad = 0; v_flush_crc = 0; v_carrier_ext = 0; v_pre_notsof = 0;
        n_prefetch = 0; n_launch = 0; v_mii_hinib = 0; base_drop = 0;
        rseed = 32'h1234_5678;

        wr_half = 5.0;
        tx_half = 4.0;

        wr_rst_n = 1'b0; tx_rst_n = 1'b0;
        speed_select = 1'b1; nib_mode = 1'b0;
        s_axis_tdata = 8'h00; s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;

        $display("==========================================================");
        $display(" tx_mac_controller_advanced_tb");
        $display("==========================================================");

        repeat (8) @(posedge tx_clk);
        @(negedge wr_clk) wr_rst_n = 1'b1;
        @(negedge tx_clk) tx_rst_n = 1'b1;
        repeat (10) @(posedge tx_clk);

        $display("\n-- TC1 : payload length sweep, 1 to 70 octets --");
        q_clr;
        for (k = 1; k <= 70; k = k + 1) frame_send(k, k[7:0]);
        wait_quiet(40);
        ex_build_all;

        check("TC1 all 70 frames reached the wire", rx_n === 70);
        verify_all("TC1 every frame in the sweep is bit-exact");
        verify_gaps("TC1 every gap in the sweep is at least 96 bit times", 12);
        verify_clean("TC1 no TX_ER anywhere in the sweep");

        bad = 0;
        for (f = 0; f < rx_n; f = f + 1)
            if (rx_len[f] < (8 + MIN_LEN + 4)) bad = bad + 1;
        check("TC1 no frame was shorter than 8+60+4 octets on the wire",
              bad === 0);

        bad = 0;
        for (f = 0; f < 59; f = f + 1)
            if (rx_len[f] !== 72) bad = bad + 1;
        check("TC1 payloads 1..59 all padded to exactly 72 wire octets",
              bad === 0);

        bad = 0;
        for (f = 59; f < 70; f = f + 1)
            if (rx_len[f] !== (8 + (f+1) + 4)) bad = bad + 1;
        check("TC1 payloads 60..70 pass through unpadded", bad === 0);

        $display("\n-- TC2 : the interesting lengths --");
        q_clr;
        frame_send(1,    8'hE1);
        frame_send(59,   8'hE2);
        frame_send(60,   8'hE3);
        frame_send(61,   8'hE4);
        frame_send(511,  8'hE5);
        frame_send(512,  8'hE6);
        frame_send(1024, 8'hE7);
        frame_send(1500, 8'hE8);
        frame_send(1518, 8'hE9);
        wait_quiet(40);
        ex_build_all;

        check("TC2 all nine frames reached the wire", rx_n === 9);
        verify_all("TC2 every interesting length is bit-exact");
        verify_gaps("TC2 gaps legal across a 1500x length ratio", 12);
        verify_clean("TC2 no TX_ER on any interesting length");
        check("TC2 the 1-octet frame became 72 wire octets", rx_len[0] === 72);
        check("TC2 the 59-octet frame was padded",           rx_len[1] === 72);
        check("TC2 the 60-octet frame was not padded",       rx_len[2] === 72);
        check("TC2 the 61-octet frame grew by one",          rx_len[3] === 73);
        check("TC2 the 1518-octet frame is 1530 on the wire", rx_len[8] === 1530);

        $display("\n-- TC3 : a lone 1-octet frame (the frame_avail blind spot) --");
        q_clr;
        base_sent = sent_cnt;
        frame_send(1, 8'h5A);
        wait_quiet(60);
        ex_build_all;

        check("TC3 the lone 1-octet frame was transmitted", rx_n === 1);
        verify_all("TC3 the 1-octet frame is bit-exact, padded to 60");
        check("TC3 it was reported sent", (sent_cnt - base_sent) === 1);
        check("TC3 its payload octet survived", rx_flat[8] === 8'h5A);
        check("TC3 octet 9 is the first pad octet", rx_flat[9] === 8'h00);

        $display("\n-- TC4 : 20 frames back to back, every gap measured --");
        q_clr;
        for (k = 0; k < 20; k = k + 1) frame_send(64 + k, 8'h20 + k[7:0]);
        wait_quiet(40);
        ex_build_all;

        check("TC4 all 20 frames reached the wire", rx_n === 20);
        verify_all("TC4 all 20 back-to-back frames are bit-exact");
        verify_gaps("TC4 no gap collapsed under sustained back-to-back load", 12);
        verify_clean("TC4 no TX_ER under sustained load");
        check("TC4 no underruns under sustained load", und_cnt === 0);

        $display("\n-- TC5 : 10 MHz writer, 125 MHz wire (12.5x starvation) --");
        wait_quiet(20);
        wr_half = 50.0;
        repeat (4) @(posedge wr_clk);
        q_clr;
        base_und = und_cnt;
        for (k = 0; k < 4; k = k + 1) frame_send(100, 8'h60 + k[7:0]);
        wait_quiet(40);
        ex_build_all;

        check("TC5 all four starved frames reached the wire", rx_n === 4);
        verify_all("TC5 a 12.5x slower writer changes nothing on the wire");
        verify_clean("TC5 no TX_ER despite the starved writer");
        check("TC5 store-and-forward prevented every underrun",
              (und_cnt - base_und) === 0);
        verify_gaps("TC5 gaps still legal with a slow writer", 12);

        $display("\n-- TC6 : 200 MHz writer, 125 MHz wire (AXI backpressure) --");
        wait_quiet(20);
        wr_half = 2.5;
        repeat (4) @(posedge wr_clk);
        q_clr;
        for (k = 0; k < 6; k = k + 1) frame_send(400, 8'h70 + k[7:0]);
        wait_quiet(60);
        ex_build_all;

        check("TC6 all six frames survived the overrun pressure", rx_n === 6);
        verify_all("TC6 AXI backpressure did not lose or duplicate an octet");
        verify_clean("TC6 no TX_ER under write-side pressure");
        check("TC6 nothing was dropped - the FIFO backpressured instead",
              drop_cnt === 0);

        wait_quiet(20);
        wr_half = 5.0;
        repeat (4) @(posedge wr_clk);

        $display("\n-- TC7 : ragged AXI writer, random bubbles inside frames --");
        q_clr;
        for (k = 0; k < 8; k = k + 1) frame_send_ragged(70 + (k*13), 8'h90 + k[7:0]);
        wait_quiet(40);
        ex_build_all;

        check("TC7 all eight ragged frames reached the wire", rx_n === 8);
        verify_all("TC7 write-side bubbles never appear on the wire");
        verify_clean("TC7 no TX_ER from a stuttering writer");
        verify_gaps("TC7 gaps legal with a stuttering writer", 12);

        $display("\n-- TC8 : 3000-octet frame into a 2048-octet FIFO --");
        q_clr;
        base_sent = sent_cnt;
        frame_send_unchecked(3000, 8'hC0);
        wait_quiet(60);

        check("TC8 the oversized frame was dropped", drop_cnt >= 1);
        check("TC8 the oversized frame never reached the wire", rx_n === 0);
        check("TC8 no frame was reported sent", (sent_cnt - base_sent) === 0);
        check("TC8 the controller returned to idle", tx_busy_out === 1'b0);
        check("TC8 AXI ready recovered after the drop", s_axis_tready === 1'b1);

        q_clr;
        frame_send(300, 8'hD0);
        frame_send(64,  8'hD8);
        wait_quiet(40);
        ex_build_all;

        check("TC8 two frames after the drop reached the wire", rx_n === 2);
        verify_all("TC8 the frames AFTER a drop are bit-exact");
        verify_clean("TC8 no TX_ER after a drop");

        $display("\n-- TC9 : MII nibble mode, IFG = 24 cycles --");
        wait_quiet(20);
        @(negedge tx_clk) begin speed_select = 1'b0; nib_mode = 1'b1; end
        repeat (6) @(posedge tx_clk);
        q_clr;
        for (k = 0; k < 6; k = k + 1) frame_send(50 + (k*40), 8'h30 + k[7:0]);
        wait_quiet(60);
        ex_build_all;

        check("TC9 all six MII frames reached the wire", rx_n === 6);
        verify_all("TC9 every MII frame reassembles bit-exact from nibbles");
        verify_nibble_cycles("TC9 every octet took exactly two TX_CLK cycles");
        verify_gaps("TC9 MII gap is at least 96 bit times (24 cycles)", 24);
        verify_clean("TC9 no TX_ER in nibble mode");
        check("TC9 no underrun despite ready dropping every other cycle",
              und_cnt === 0);

        check("TC9 TXD[7:4] was held at zero for every MII cycle",
              v_mii_hinib === 0);

        $display("\n-- TC10 : speed strap changed while idle, MII -> GMII --");
        wait_quiet(20);
        @(negedge tx_clk) begin speed_select = 1'b1; nib_mode = 1'b0; end
        repeat (6) @(posedge tx_clk);
        q_clr;
        frame_send(80, 8'h40);
        wait_quiet(30);
        ex_build_all;

        check("TC10 the first frame after the strap change is on the wire",
              rx_n === 1);
        verify_all("TC10 GMII resumed correctly after running in MII");
        verify_gaps("TC10 gap follows the new strap", 12);
        check("TC10 one octet per cycle again", rx_cyc[0] === rx_len[0]);

        $display("\n-- TC11 : tx_rst_n asserted in mid-frame --");
        q_clr;
        fork
            frame_send_unchecked(600, 8'h11);
            begin

                @(posedge tx_clk);
                while (!gmii_tx_en) @(posedge tx_clk);
                repeat (40) @(posedge tx_clk);
                @(negedge tx_clk) tx_rst_n = 1'b0;

                #1;
                check("TC11 TX_EN dropped on the reset edge, before any clock edge",
                      gmii_tx_en === 1'b0);
                check("TC11 TX_ER dropped on the reset edge too",
                      gmii_tx_er === 1'b0);
                repeat (8) @(negedge tx_clk);
                tx_rst_n = 1'b1;
            end
        join
        wait_quiet(60);

        check("TC11 TX_EN is still low after the reset is released",
              gmii_tx_en === 1'b0);
        check("TC11 TX_ER is still low after the reset is released",
              gmii_tx_er === 1'b0);
        check("TC11 the FSM returned to ST_IDLE, not a mid-frame state",
              dut.state === 3'd0);
        check("TC11 the controller reports itself not busy", tx_busy_out === 1'b0);
        check("TC11 no Carrier Extend was emitted while the wire was cut",
              v_carrier_ext === 0);
        check("TC11 the lead register was cleared by the reset",
              dut.pay_v === 1'b0);
        $display("       after the single-sided reset the FIFO replayed %0d wire octets",
                 rx_ptr);

        @(negedge wr_clk) wr_rst_n = 1'b0;
        @(negedge tx_clk) tx_rst_n = 1'b0;
        repeat (6) @(posedge tx_clk);
        @(negedge wr_clk) wr_rst_n = 1'b1;
        @(negedge tx_clk) tx_rst_n = 1'b1;
        repeat (10) @(posedge tx_clk);

        q_clr;
        frame_send(200, 8'h12);
        frame_send(64,  8'h13);
        wait_quiet(40);
        ex_build_all;

        check("TC11 two frames after a both-domain reset reached the wire",
              rx_n === 2);
        verify_all("TC11 traffic is bit-exact once both domains are reset together");
        verify_clean("TC11 no TX_ER after recovery");
        verify_gaps("TC11 the gap is legal again after recovery", 12);

        $display("\n-- TC12 : wr_rst_n asserted in mid-frame --");
        q_clr;
        fork
            frame_send_unchecked(800, 8'h21);
            begin
                repeat (200) @(posedge wr_clk);
                @(negedge wr_clk) wr_rst_n = 1'b0;
                repeat (6) @(negedge wr_clk);
                wr_rst_n = 1'b1;
            end
        join
        wait_quiet(80);

        @(negedge wr_clk) wr_rst_n = 1'b0;
        @(negedge tx_clk) tx_rst_n = 1'b0;
        repeat (6) @(posedge tx_clk);
        @(negedge wr_clk) wr_rst_n = 1'b1;
        @(negedge tx_clk) tx_rst_n = 1'b1;
        repeat (10) @(posedge tx_clk);

        q_clr;
        frame_send(150, 8'h22);
        frame_send(60,  8'h23);
        wait_quiet(40);
        ex_build_all;

        check("TC12 two frames after the write-side reset reached the wire",
              rx_n === 2);
        verify_all("TC12 the frames after a mid-frame wr reset are bit-exact");
        verify_clean("TC12 no TX_ER after write-side recovery");

        $display("\n-- TC13 : receiver residue over every frame --");
        q_clr;
        frame_send(1,    8'hF1);
        frame_send(46,   8'hF2);
        frame_send(60,   8'hF3);
        frame_send(137,  8'hF4);
        frame_send(1500, 8'hF5);
        wait_quiet(40);
        ex_build_all;

        check("TC13 all five residue frames reached the wire", rx_n === 5);
        verify_all("TC13 the residue frames are bit-exact");

        res0 = residue_of(0);
        $display("       measured residue = %08h (802.3 expects DEBB20E3)", res0);
        check("TC13 frame 0 produces the 802.3 magic residue",
              res0 === 32'hDEBB20E3);

        bad = 0;
        for (f = 0; f < rx_n; f = f + 1) begin
            resk = residue_of(f);
            if (resk !== 32'hDEBB20E3) bad = bad + 1;
        end
        check("TC13 every frame produces the identical magic residue",
              bad === 0);

        $display("\n-- TC14 : PREAMBLE+SFD serialised LSB-first --");
        dev_cnt = 0;
        dev_at  = -1;
        lastb   = -1;
        for (k = 0; k < 64; k = k + 1) begin
            bitv = (rx_flat[rx_start[0] + (k/8)] >> (k % 8)) & 1;
            if (k > 0) begin
                if (bitv === lastb) begin
                    dev_cnt = dev_cnt + 1;
                    dev_at  = k;
                end
            end
            lastb = bitv;
        end
        check("TC14 the 64-bit preamble alternates except in exactly one place",
              dev_cnt === 1);
        check("TC14 that one place is the FINAL bit, index 63", dev_at === 63);
        check("TC14 the first bit on the wire is a 1",
              ((rx_flat[rx_start[0]] >> 0) & 1) === 1);
        check("TC14 octet 7 is 0xD5, not 0x55", rx_flat[rx_start[0]+7] === 8'hD5);
        check("TC14 the preamble was NOT covered by the FCS (residue held)",
              residue_of(0) === 32'hDEBB20E3);

        $display("\n-- TC15 : forced mid-frame underrun, abort and recovery --");
        q_clr;
        base_und  = und_cnt;
        base_sent = sent_cnt;
        fork
            frame_send_unchecked(200, 8'h31);
            begin

                @(posedge tx_clk);
                while (dut.state !== 3'd2) @(posedge tx_clk);
                repeat (20) @(posedge tx_clk);
                @(negedge tx_clk) force dut.phy_valid = 1'b0;
                @(negedge tx_clk) release dut.phy_valid;
            end
        join
        wait_quiet(80);

        check("TC15 the underrun was reported", (und_cnt - base_und) === 1);
        check("TC15 the aborted frame produced TX_ER cycles",
              (rx_n >= 1) && (rx_er[0] > 0));
        check("TC15 the aborted frame was NOT reported as sent",
              (sent_cnt - base_sent) === 0);
        check("TC15 TX_ER was released again", gmii_tx_er === 1'b0);
        check("TC15 the controller escaped ST_ABRT and ST_FLSH",
              tx_busy_out === 1'b0);
        check("TC15 no Carrier Extend was emitted during the abort",
              v_carrier_ext === 0);

        q_clr;
        base_und = und_cnt;
        frame_send(120, 8'h32);
        frame_send(64,  8'h33);
        wait_quiet(40);
        ex_build_all;

        check("TC15 two frames after the abort reached the wire", rx_n === 2);
        verify_all("TC15 the frames AFTER an abort are bit-exact");
        verify_clean("TC15 no TX_ER after the abort recovered");
        verify_gaps("TC15 the abort path generated a legal IFG of its own", 12);
        check("TC15 no further underruns after recovery",
              (und_cnt - base_und) === 0);

        $display("\n-- TC16 : randomised soak, 40 frames --");
        q_clr;
        base_und  = und_cnt;
        base_drop = drop_cnt;
        for (k = 0; k < 40; k = k + 1) begin
            if ((k % 3) == 0)
                frame_send_ragged(1 + ({$random(rseed)} % 600), k[7:0]);
            else
                frame_send(1 + ({$random(rseed)} % 600), k[7:0]);
        end
        wait_quiet(60);
        ex_build_all;

        check("TC16 all 40 soak frames reached the wire", rx_n === 40);
        verify_all("TC16 every soak frame is bit-exact");
        verify_gaps("TC16 every soak gap is at least 96 bit times", 12);
        verify_clean("TC16 no TX_ER anywhere in the soak");
        check("TC16 zero underruns across the soak", (und_cnt - base_und) === 0);
        check("TC16 no frame was dropped in the soak - every one fitted",
              drop_cnt === base_drop);

        bad = 0;
        for (f = 0; f < rx_n; f = f + 1)
            if (residue_of(f) !== 32'hDEBB20E3) bad = bad + 1;
        check("TC16 every soak frame passes the receiver residue check",
              bad === 0);

        $display("\n-- TC17 : continuous invariant watchers --");
        check("TC17 the CRC tap was never open while the EOF octet was held",
              v_crc_after_eof === 0);
        check("TC17 fcs init and data_valid were never asserted together",
              v_init_dv === 0);
        check("TC17 ifg_start was never asserted during an active gap",
              v_ifg_start_bad === 0);
        check("TC17 no launch ever happened in a gap or a frame_done cycle",
              v_launch_bad === 0);
        check("TC17 no discarded octet ever reached the CRC",
              v_flush_crc === 0);
        check("TC17 TX_ER was never high with TX_EN low (no Carrier Extend)",
              v_carrier_ext === 0);
        check("TC17 every ST_PRE prefetch was octet 0 of a frame",
              v_pre_notsof === 0);
        check("TC17 exactly one prefetch per launch, over the whole run",
              n_prefetch === n_launch);
        $display("       launches = %0d, prefetches = %0d", n_launch, n_prefetch);
        check("TC17 the controller is idle at the end of the run",
              tx_busy_out === 1'b0);
        check("TC17 AXI ready is high at the end of the run",
              s_axis_tready === 1'b1);

        $display("\n==========================================================");
        $display(" tx_mac_controller_advanced_tb : %0d PASS, %0d FAIL",
                 pass_n, fail_n);
        if (fail_n == 0) $display(" RESULT: ALL CHECKS PASSED");
        else             $display(" RESULT: %0d CHECK(S) FAILED", fail_n);
        $display("==========================================================");
        $finish;
    end

endmodule


`default_nettype wire
