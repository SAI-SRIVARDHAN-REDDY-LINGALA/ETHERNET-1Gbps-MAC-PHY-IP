// tx_gmii_mii_advanced_tb - Advanced GMII/MII transmit tests.

`timescale 1ns / 1ps
`default_nettype none

module tx_gmii_mii_advanced_tb;

    localparam real CLKP_GMII = 8.0;
    localparam real CLKP_MII  = 40.0;
    localparam real CLKP_SLOW = 400.0;

    reg tx_clk, clk_mii, clk_slow;
    initial tx_clk   = 1'b0;
    initial clk_mii  = 1'b0;
    initial clk_slow = 1'b0;
    always #(CLKP_GMII / 2.0) tx_clk   = ~tx_clk;
    always #(CLKP_MII  / 2.0) clk_mii  = ~clk_mii;
    always #(CLKP_SLOW / 2.0) clk_slow = ~clk_slow;

    reg        rst_n;
    reg        speed_select;
    reg  [7:0] data_in;
    reg        valid_in;
    reg        last_in;
    reg        err_in;
    wire       ready_out;
    wire [7:0] gmii_txd;
    wire       gmii_tx_en;
    wire       gmii_tx_er;
    wire       frame_done_out;
    wire       underrun_out;

    tx_gmii_mii #(.ERR_CYCLES(2)) dut (
        .tx_clk(tx_clk), .rst_n(rst_n), .speed_select(speed_select),
        .data_in(data_in), .valid_in(valid_in), .last_in(last_in),
        .err_in(err_in), .ready_in(ready_out),
        .gmii_txd(gmii_txd), .gmii_tx_en(gmii_tx_en), .gmii_tx_er(gmii_tx_er),
        .frame_done_out(frame_done_out), .underrun_out(underrun_out)
    );

    wire e1_tx_en, e1_tx_er, e3_tx_en, e3_tx_er;
    wire [7:0] e1_txd, e3_txd;
    wire e1_rdy, e3_rdy, e1_done, e3_done, e1_under, e3_under;

    tx_gmii_mii #(.ERR_CYCLES(1)) dut_e1 (
        .tx_clk(tx_clk), .rst_n(rst_n), .speed_select(speed_select),
        .data_in(data_in), .valid_in(valid_in), .last_in(last_in),
        .err_in(err_in), .ready_in(e1_rdy),
        .gmii_txd(e1_txd), .gmii_tx_en(e1_tx_en), .gmii_tx_er(e1_tx_er),
        .frame_done_out(e1_done), .underrun_out(e1_under)
    );

    tx_gmii_mii #(.ERR_CYCLES(3)) dut_e3 (
        .tx_clk(tx_clk), .rst_n(rst_n), .speed_select(speed_select),
        .data_in(data_in), .valid_in(valid_in), .last_in(last_in),
        .err_in(err_in), .ready_in(e3_rdy),
        .gmii_txd(e3_txd), .gmii_tx_en(e3_tx_en), .gmii_tx_er(e3_tx_er),
        .frame_done_out(e3_done), .underrun_out(e3_under)
    );

    reg        rst_m, rst_s;
    reg  [7:0] data_m, data_s;
    reg        valid_m, valid_s, last_m, last_s;
    wire       rdy_m, rdy_s;
    wire [7:0] txd_m, txd_s;
    wire       en_m, er_m, done_m, under_m;
    wire       en_s, er_s, done_s, under_s;

    tx_gmii_mii #(.ERR_CYCLES(2)) dut_mii (
        .tx_clk(clk_mii), .rst_n(rst_m), .speed_select(1'b0),
        .data_in(data_m), .valid_in(valid_m), .last_in(last_m),
        .err_in(1'b0), .ready_in(rdy_m),
        .gmii_txd(txd_m), .gmii_tx_en(en_m), .gmii_tx_er(er_m),
        .frame_done_out(done_m), .underrun_out(under_m)
    );

    tx_gmii_mii #(.ERR_CYCLES(2)) dut_slow (
        .tx_clk(clk_slow), .rst_n(rst_s), .speed_select(1'b0),
        .data_in(data_s), .valid_in(valid_s), .last_in(last_s),
        .err_in(1'b0), .ready_in(rdy_s),
        .gmii_txd(txd_s), .gmii_tx_en(en_s), .gmii_tx_er(er_s),
        .frame_done_out(done_s), .underrun_out(under_s)
    );

    integer pass_count, fail_count;

    task check;
        input [95*8:0] name;
        input          cond;
        begin
            if (cond) begin
                $display("  PASS : %0s", name);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL : %0s", name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    localparam integer CAPMAX = 4096;

    integer   cyc;
    integer   en_cycles;
    integer   er_cycles;
    integer   er_run, er_run_max;
    integer   rdy_run, rdy_run_max;
    integer   done_pulses, under_pulses;
    integer   en_runs;
    integer   xfers;
    integer   cap_n;
    integer   last_en_cyc, done_cyc;
    reg       en_d;

    integer   inv_carrier_ext;
    integer   inv_under_idle;
    integer   inv_done_with_en;
    integer   inv_mii_hinib;

    reg [7:0] cap [0:CAPMAX-1];

    always @(posedge tx_clk) begin
        cyc = cyc + 1;

        if (gmii_tx_er && !gmii_tx_en) inv_carrier_ext  = inv_carrier_ext  + 1;
        if (underrun_out && !gmii_tx_en) inv_under_idle = inv_under_idle + 1;
        if (frame_done_out && gmii_tx_en) inv_done_with_en = inv_done_with_en + 1;
        if (!speed_select && gmii_tx_en && (gmii_txd[7:4] != 4'h0))
            inv_mii_hinib = inv_mii_hinib + 1;

        if (valid_in && ready_out) xfers = xfers + 1;

        if (gmii_tx_en) begin
            en_cycles   = en_cycles + 1;
            last_en_cyc = cyc;
            if (!en_d) en_runs = en_runs + 1;
            if (cap_n < CAPMAX) begin
                cap[cap_n] = gmii_txd;
                cap_n      = cap_n + 1;
            end
        end

        if (gmii_tx_er) begin
            er_cycles = er_cycles + 1;
            er_run    = er_run + 1;
            if (er_run > er_run_max) er_run_max = er_run;
        end else begin
            er_run = 0;
        end

        if (gmii_tx_en && ready_out) begin
            rdy_run = rdy_run + 1;
            if (rdy_run > rdy_run_max) rdy_run_max = rdy_run;
        end else begin
            rdy_run = 0;
        end

        if (frame_done_out) begin
            done_pulses = done_pulses + 1;
            done_cyc    = cyc;
        end
        if (underrun_out) under_pulses = under_pulses + 1;

        en_d = gmii_tx_en;
    end

    integer e1_run, e1_run_max, e3_run, e3_run_max;
    integer e1_ce, e3_ce;

    always @(posedge tx_clk) begin
        if (e1_tx_er) begin
            e1_run = e1_run + 1;
            if (e1_run > e1_run_max) e1_run_max = e1_run;
        end else e1_run = 0;
        if (e3_tx_er) begin
            e3_run = e3_run + 1;
            if (e3_run > e3_run_max) e3_run_max = e3_run;
        end else e3_run = 0;
        if (e1_tx_er && !e1_tx_en) e1_ce = e1_ce + 1;
        if (e3_tx_er && !e3_tx_en) e3_ce = e3_ce + 1;
    end

    integer m_cycles, s_cycles;
    real    m_rise, m_fall, s_rise, s_fall;
    reg     m_frame_done, s_frame_done;

    always @(posedge clk_mii)  if (en_m) m_cycles = m_cycles + 1;
    always @(posedge clk_slow) if (en_s) s_cycles = s_cycles + 1;
    always @(posedge en_m) m_rise = $realtime;
    always @(negedge en_m) m_fall = $realtime;
    always @(posedge en_s) s_rise = $realtime;
    always @(negedge en_s) s_fall = $realtime;

    task clear_mon;
        integer k;
        begin
            en_cycles   = 0;
            er_cycles   = 0;
            er_run      = 0;
            er_run_max  = 0;
            rdy_run     = 0;
            rdy_run_max = 0;
            done_pulses = 0;
            under_pulses= 0;
            en_runs     = 0;
            xfers       = 0;
            cap_n       = 0;
            last_en_cyc = 0;
            done_cyc    = 0;
            for (k = 0; k < 16; k = k + 1) cap[k] = 8'h00;
        end
    endtask

    task clear_err_mon;
        begin
            e1_run = 0; e1_run_max = 0;
            e3_run = 0; e3_run_max = 0;
        end
    endtask

    task do_reset;
        begin
            @(negedge tx_clk);
            rst_n    <= 1'b0;
            valid_in <= 1'b0;
            last_in  <= 1'b0;
            err_in   <= 1'b0;
            data_in  <= 8'h00;
            repeat (2) @(negedge tx_clk);
            rst_n <= 1'b1;
            @(negedge tx_clk);
            clear_mon;
            clear_err_mon;
        end
    endtask

    task send_frame;
        input integer n;
        input [7:0]   base;
        integer i;
        begin
            i = 0;
            while (i < n) begin
                @(negedge tx_clk);
                data_in  <= base + i[7:0];
                valid_in <= 1'b1;
                last_in  <= (i == n - 1) ? 1'b1 : 1'b0;
                err_in   <= 1'b0;
                @(posedge tx_clk);
                if (ready_out) i = i + 1;
            end
            @(negedge tx_clk);
            valid_in <= 1'b0;
            last_in  <= 1'b0;
        end
    endtask

    task send_frame_err;
        input integer n;
        input [7:0]   base;
        input integer err_at;
        integer i;
        begin
            i = 0;
            while (i < n) begin
                @(negedge tx_clk);
                data_in  <= base + i[7:0];
                valid_in <= 1'b1;
                last_in  <= (i == n - 1) ? 1'b1 : 1'b0;
                err_in   <= (i == err_at) ? 1'b1 : 1'b0;
                @(posedge tx_clk);
                if (ready_out) i = i + 1;
            end
            @(negedge tx_clk);
            valid_in <= 1'b0;
            last_in  <= 1'b0;
            err_in   <= 1'b0;
        end
    endtask

    task send_frame_gappy;
        input integer n;
        input [7:0]   base;
        integer i;
        begin
            i = 0;
            while (i < n) begin
                @(negedge tx_clk);
                data_in  <= base + i[7:0];
                valid_in <= 1'b1;
                last_in  <= (i == n - 1) ? 1'b1 : 1'b0;
                err_in   <= 1'b0;
                @(posedge tx_clk);
                if (ready_out) begin
                    i = i + 1;
                    @(negedge tx_clk);
                    valid_in <= 1'b0;
                    last_in  <= 1'b0;
                    data_in  <= 8'hFF;
                    @(posedge tx_clk);
                end
            end
            @(negedge tx_clk);
            valid_in <= 1'b0;
            last_in  <= 1'b0;
        end
    endtask

    task send_partial;
        input integer k;
        input [7:0]   base;
        integer i;
        begin
            i = 0;
            while (i < k) begin
                @(negedge tx_clk);
                data_in  <= base + i[7:0];
                valid_in <= 1'b1;
                last_in  <= 1'b0;
                err_in   <= 1'b0;
                @(posedge tx_clk);
                if (ready_out) i = i + 1;
            end
            @(negedge tx_clk);
            valid_in <= 1'b0;
            last_in  <= 1'b0;
        end
    endtask

    task idle_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(negedge tx_clk);
        end
    endtask

    integer verify_bad, verify_first_bad;

    task verify_octets;
        input integer n;
        input [7:0]   base;
        input         mode;
        integer i;
        reg [7:0] got, exp;
        begin
            verify_bad       = 0;
            verify_first_bad = -1;
            if (mode) begin
                if (cap_n != n) verify_bad = verify_bad + 1;
                for (i = 0; (i < n) && (i < CAPMAX); i = i + 1) begin
                    got = cap[i];
                    exp = base + i[7:0];
                    if (got !== exp) begin
                        verify_bad = verify_bad + 1;
                        if (verify_first_bad < 0) verify_first_bad = i;
                    end
                end
            end else begin
                if (cap_n != 2*n) verify_bad = verify_bad + 1;
                for (i = 0; (i < n) && (2*i+1 < CAPMAX); i = i + 1) begin

                    got = {cap[2*i+1][3:0], cap[2*i][3:0]};
                    exp = base + i[7:0];
                    if (got !== exp) begin
                        verify_bad = verify_bad + 1;
                        if (verify_first_bad < 0) verify_first_bad = i;
                    end
                end
            end
        end
    endtask

    task send_m;
        input integer n;
        integer i;
        begin
            i = 0;
            while (i < n) begin
                @(negedge clk_mii);
                data_m  <= 8'h40 + i[7:0];
                valid_m <= 1'b1;
                last_m  <= (i == n - 1) ? 1'b1 : 1'b0;
                @(posedge clk_mii);
                if (rdy_m) i = i + 1;
            end
            @(negedge clk_mii);
            valid_m <= 1'b0;
            last_m  <= 1'b0;
        end
    endtask

    task send_s;
        input integer n;
        integer i;
        begin
            i = 0;
            while (i < n) begin
                @(negedge clk_slow);
                data_s  <= 8'h40 + i[7:0];
                valid_s <= 1'b1;
                last_s  <= (i == n - 1) ? 1'b1 : 1'b0;
                @(posedge clk_slow);
                if (rdy_s) i = i + 1;
            end
            @(negedge clk_slow);
            valid_s <= 1'b0;
            last_s  <= 1'b0;
        end
    endtask

    initial begin
        rst_m = 1'b0; data_m = 8'h00; valid_m = 1'b0; last_m = 1'b0;
        m_cycles = 0; m_frame_done = 1'b0;
        m_rise = 0.0; m_fall = 0.0;
        repeat (3) @(negedge clk_mii);
        rst_m = 1'b1;
        @(negedge clk_mii);
        send_m(8);
        repeat (6) @(negedge clk_mii);
        m_frame_done = 1'b1;
    end

    initial begin
        rst_s = 1'b0; data_s = 8'h00; valid_s = 1'b0; last_s = 1'b0;
        s_cycles = 0; s_frame_done = 1'b0;
        s_rise = 0.0; s_fall = 0.0;
        repeat (3) @(negedge clk_slow);
        rst_s = 1'b1;
        @(negedge clk_slow);
        send_s(8);
        repeat (6) @(negedge clk_slow);
        s_frame_done = 1'b1;
    end

    integer i, j, k;
    integer f_count, f_len, exp_cycles, tot_cycles, bad_frames;
    integer seed;
    reg     mode_pick;
    integer ff_deviation;

    initial begin
        $dumpfile("tx_gmii_mii_tb.vcd");
        $dumpvars(0, tx_gmii_mii_advanced_tb);

        pass_count       = 0;
        fail_count       = 0;
        cyc              = 0;
        en_d             = 1'b0;
        inv_carrier_ext  = 0;
        inv_under_idle   = 0;
        inv_done_with_en = 0;
        inv_mii_hinib    = 0;
        e1_ce            = 0;
        e3_ce            = 0;
        seed             = 32'h6D11_2235;
        clear_mon;
        clear_err_mon;

        rst_n        = 1'b1;
        speed_select = 1'b1;
        data_in      = 8'h00;
        valid_in     = 1'b0;
        last_in      = 1'b0;
        err_in       = 1'b0;

        $display("=========================================================");
        $display(" tx_gmii_mii_advanced_tb -  tx_gmii_mii full verification");
        $display("=========================================================");

        $display("\n[TC1] Async reset mid-octet (MII high-nibble cycle)");
        speed_select = 1'b0;
        do_reset;

        @(negedge tx_clk);
        data_in  <= 8'h96;
        valid_in <= 1'b1;
        last_in  <= 1'b0;
        @(posedge tx_clk);
        @(negedge tx_clk);

        rst_n <= 1'b0;
        #1;
        check("TC1 async reset drops TX_EN immediately",  gmii_tx_en == 1'b0);
        check("TC1 async reset drops TX_ER immediately",  gmii_tx_er == 1'b0);
        check("TC1 async reset clears TXD",               gmii_txd   == 8'h00);
        @(negedge tx_clk);
        rst_n    <= 1'b1;
        valid_in <= 1'b0;
        last_in  <= 1'b0;
        @(negedge tx_clk);
        clear_mon;

        send_frame(4, 8'h31);
        idle_cycles(8);
        verify_octets(4, 8'h31, 1'b0);
        check("TC1 clean MII frame after reset (8 cycles)", en_cycles == 8);
        check("TC1 octets correct after reset",             verify_bad == 0);
        check("TC1 exactly one TX_EN pulse after reset",    en_runs    == 1);

        $display("\n[TC2] GMII minimum legal frame - 64 octets");
        speed_select = 1'b1;
        do_reset;
        send_frame(64, 8'h00);
        idle_cycles(8);
        verify_octets(64, 8'h00, 1'b1);
        $display("       64 octets -> %0d in-frame cycles, %0d pin words captured",
                 en_cycles, cap_n);
        check("TC2 GMII 64 octets == 64 cycles",  en_cycles   == 64);
        check("TC2 all 64 octets bit-exact",      verify_bad  == 0);
        check("TC2 one TX_EN pulse",              en_runs     == 1);
        check("TC2 one done pulse",               done_pulses == 1);
        check("TC2 no underrun",                  under_pulses == 0);

        $display("\n[TC3] GMII maximum legal frame - 1518 octets");
        do_reset;
        send_frame(1518, 8'h00);
        idle_cycles(8);
        verify_octets(1518, 8'h00, 1'b1);
        $display("       1518 octets -> %0d in-frame cycles", en_cycles);
        check("TC3 GMII 1518 octets == 1518 cycles", en_cycles  == 1518);
        check("TC3 all 1518 octets bit-exact",       verify_bad == 0);
        check("TC3 one TX_EN pulse over a max frame", en_runs   == 1);

        $display("\n[TC4] MII minimum legal frame - 64 octets");
        speed_select = 1'b0;
        do_reset;
        send_frame(64, 8'h00);
        idle_cycles(8);
        verify_octets(64, 8'h00, 1'b0);
        $display("       64 octets -> %0d nibble cycles (expect 128)", en_cycles);
        check("TC4 MII 64 octets == 128 nibble cycles", en_cycles  == 128);
        check("TC4 all 64 octets reassemble bit-exact", verify_bad == 0);
        check("TC4 one TX_EN pulse",                    en_runs    == 1);

        $display("\n[TC5] MII maximum legal frame - 1518 octets");
        do_reset;
        send_frame(1518, 8'h00);
        idle_cycles(8);
        verify_octets(1518, 8'h00, 1'b0);
        $display("       1518 octets -> %0d nibble cycles (expect 3036)", en_cycles);
        if (verify_bad != 0)
            $display("       first mismatching octet index: %0d", verify_first_bad);
        check("TC5 MII 1518 octets == 3036 nibble cycles", en_cycles  == 3036);
        check("TC5 all 1518 octets reassemble bit-exact",  verify_bad == 0);
        check("TC5 one TX_EN pulse over a max frame",      en_runs    == 1);

        $display("\n[TC6] Nibble-shift attack: valid_in dropped on every ST_HI");
        do_reset;
        send_frame_gappy(10, 8'h11);
        idle_cycles(8);
        verify_octets(10, 8'h11, 1'b0);
        ff_deviation = 0;
        for (i = 0; i < cap_n; i = i + 1)
            if (cap[i] == 8'h0F) ff_deviation = ff_deviation + 1;
        $display("       %0d nibble cycles, %0d octets bad, %0d garbage nibbles leaked",
                 en_cycles, verify_bad, ff_deviation);
        check("TC6 still 20 nibble cycles for 10 octets", en_cycles    == 20);
        check("TC6 no nibble shift - octets bit-exact",   verify_bad   == 0);
        check("TC6 garbled data_in never reached TXD",    ff_deviation == 0);
        check("TC6 no underrun declared (ST_HI is not a request)",
                                                          under_pulses == 0);
        check("TC6 frame completed normally",             done_pulses  == 1);

        $display("\n[TC7] ready_out throttle shape");
        speed_select = 1'b0;
        do_reset;
        send_frame(12, 8'h60);
        idle_cycles(6);
        $display("       MII : longest in-frame ready run = %0d (expect 1)",
                 rdy_run_max);
        check("TC7 MII ready_out never high 2 cycles running", rdy_run_max == 1);
        check("TC7 MII accepted exactly 12 octets",            xfers      == 12);

        speed_select = 1'b1;
        do_reset;
        send_frame(12, 8'h60);
        idle_cycles(6);
        $display("       GMII: longest in-frame ready run = %0d (expect 11)",
                 rdy_run_max);
        check("TC7 GMII ready_out continuous in-frame",  rdy_run_max == 11);
        check("TC7 GMII accepted exactly 12 octets",     xfers       == 12);

        $display("\n[TC8] GMII underrun -> TX_ER abort");
        speed_select = 1'b1;
        do_reset;
        send_partial(6, 8'h70);
        idle_cycles(10);
        $display("       in-frame cycles = %0d, TX_ER run = %0d, underrun pulses = %0d",
                 en_cycles, er_run_max, under_pulses);
        check("TC8 exactly one underrun reported",           under_pulses == 1);
        check("TC8 TX_ER held for ERR_CYCLES = 2 cycles",    er_run_max   == 2);
        check("TC8 TX_EN stayed high through the abort",     en_cycles    == 6 + 2);
        check("TC8 no frame_done_out on an aborted frame",   done_pulses  == 0);
        check("TC8 TX_EN low again after the abort",          gmii_tx_en  == 1'b0);
        $display("       -> the PHY emits an invalid symbol, so the far end's");
        $display("          FCS check rejects the frame unambiguously");

        $display("\n[TC9] MII underrun at an octet boundary");
        speed_select = 1'b0;
        do_reset;
        send_partial(5, 8'h80);
        idle_cycles(12);
        $display("       in-frame cycles = %0d (expect 5x2 + 2 abort = 12)",
                 en_cycles);
        check("TC9 exactly one underrun reported",        under_pulses == 1);
        check("TC9 TX_ER held 2 cycles",                  er_run_max   == 2);
        check("TC9 abort landed on an octet boundary",    en_cycles    == 12);
        check("TC9 no done pulse for an aborted frame",   done_pulses  == 0);

        $display("\n[TC10] ERR_CYCLES sweep - 1 / 2 / 3");
        $display("       ERR_CYCLES=1 -> %0d cycles", e1_run_max);
        $display("       ERR_CYCLES=2 -> %0d cycles", er_run_max);
        $display("       ERR_CYCLES=3 -> %0d cycles", e3_run_max);
        check("TC10 ERR_CYCLES=1 gives a 1-cycle TX_ER assert", e1_run_max == 1);
        check("TC10 ERR_CYCLES=2 gives a 2-cycle TX_ER assert", er_run_max == 2);
        check("TC10 ERR_CYCLES=3 gives a 3-cycle TX_ER assert", e3_run_max == 3);
        check("TC10 ERR_CYCLES=1 never signals Carrier Extend", e1_ce == 0);
        check("TC10 ERR_CYCLES=3 never signals Carrier Extend", e3_ce == 0);

        $display("\n[TC11] Drain swallows the aborted tail - no ghost frame");
        speed_select = 1'b1;
        do_reset;
        send_partial(4, 8'h90);
        idle_cycles(8);

        clear_mon;
        send_frame(7, 8'hA0);
        idle_cycles(8);
        $display("       tail: %0d octets accepted, %0d in-frame cycles emitted",
                 xfers, en_cycles);
        check("TC11 drain accepted the tail",               xfers      == 7);
        check("TC11 drain emitted nothing on the wire",     en_cycles  == 0);
        check("TC11 no TX_EN pulse for the discarded tail", en_runs    == 0);
        check("TC11 no done pulse for the discarded tail",  done_pulses == 0);

        clear_mon;
        send_frame(9, 8'hB0);
        idle_cycles(8);
        verify_octets(9, 8'hB0, 1'b1);
        $display("       next frame: %0d cycles, %0d bad octets", en_cycles, verify_bad);
        check("TC11 next frame transmits cleanly",   en_cycles   == 9);
        check("TC11 next frame is bit-exact",        verify_bad  == 0);
        check("TC11 next frame gets its done pulse", done_pulses == 1);

        $display("\n[TC12] Wedged upstream: drain with no last_in ever");
        do_reset;
        send_partial(3, 8'hC0);
        idle_cycles(8);
        clear_mon;

        for (i = 0; i < 30; i = i + 1) begin
            @(negedge tx_clk);
            data_in  <= 8'hD0 + i[7:0];
            valid_in <= 1'b1;
            last_in  <= 1'b0;
            @(posedge tx_clk);
        end
        @(negedge tx_clk);
        valid_in <= 1'b0;
        idle_cycles(8);
        $display("       30 octets with no last_in -> %0d in-frame cycles",
                 en_cycles);
        check("TC12 wire stays idle while wedged",  en_cycles == 0);
        check("TC12 TX_EN low",                     gmii_tx_en == 1'b0);
        check("TC12 TX_ER low (no Carrier Extend)", gmii_tx_er == 1'b0);

        do_reset;
        send_frame(5, 8'hE0);
        idle_cycles(8);
        verify_octets(5, 8'hE0, 1'b1);
        check("TC12 reset recovers from the wedge",  en_cycles  == 5);
        check("TC12 post-recovery frame bit-exact",  verify_bad == 0);

        $display("\n[TC13] speed_select flipped mid-frame is ignored");
        speed_select = 1'b0;
        do_reset;

        i = 0;
        while (i < 2) begin
            @(negedge tx_clk);
            data_in  <= 8'h41 + i[7:0];
            valid_in <= 1'b1;
            last_in  <= 1'b0;
            @(posedge tx_clk);
            if (ready_out) i = i + 1;
        end

        speed_select = 1'b1;
        $display(" speed_select flipped 0 -> 1 after octet 2");
        while (i < 6) begin
            @(negedge tx_clk);
            data_in  <= 8'h41 + i[7:0];
            valid_in <= 1'b1;
            last_in  <= (i == 5) ? 1'b1 : 1'b0;
            @(posedge tx_clk);
            if (ready_out) i = i + 1;
        end
        @(negedge tx_clk);
        valid_in <= 1'b0;
        last_in  <= 1'b0;
        idle_cycles(8);
        verify_octets(6, 8'h41, 1'b0);
        $display("       %0d nibble cycles (expect 12 - still MII)", en_cycles);
        check("TC13 in-flight frame stayed nibble-wide",   en_cycles  == 12);
        check("TC13 in-flight frame still bit-exact",      verify_bad == 0);
        check("TC13 no underrun from the mode flip",       under_pulses == 0);
        check("TC13 single clean TX_EN pulse",             en_runs    == 1);

        $display("\n[TC14] speed_select change between frames is honoured");

        clear_mon;
        send_frame(6, 8'h51);
        idle_cycles(8);
        verify_octets(6, 8'h51, 1'b1);
        $display("       %0d cycles (expect 6 - now GMII)", en_cycles);
        check("TC14 next frame switched to octet mode", en_cycles  == 6);
        check("TC14 GMII frame bit-exact",              verify_bad == 0);

        $display("\n[TC15] err_in spans both nibbles of an MII octet");
        speed_select = 1'b0;
        do_reset;
        send_frame_err(6, 8'h21, 2);
        idle_cycles(8);
        verify_octets(6, 8'h21, 1'b0);
        $display("       TX_ER high for %0d cycles, longest run %0d",
                 er_cycles, er_run_max);
        check("TC15 TX_ER high for exactly 2 cycles",   er_cycles  == 2);
        check("TC15 both cycles were contiguous",       er_run_max == 2);
        check("TC15 frame data still bit-exact",        verify_bad == 0);
        check("TC15 error propagation is not an abort", done_pulses == 1);
        check("TC15 no underrun declared",              under_pulses == 0);

        $display("\n[TC16] Six back-to-back frames, zero idle");
        speed_select = 1'b1;
        do_reset;
        tot_cycles = 0;
        for (i = 0; i < 6; i = i + 1) begin
            send_frame(3 + i, 8'h10 * (i[7:0] + 1));
            tot_cycles = tot_cycles + 3 + i;
        end
        idle_cycles(8);
        $display("       expect %0d cycles / 6 runs / 6 done, got %0d / %0d / %0d",
                 tot_cycles, en_cycles, en_runs, done_pulses);
        check("TC16 total in-frame cycles correct", en_cycles   == tot_cycles);
        check("TC16 six separate TX_EN pulses",     en_runs     == 6);
        check("TC16 six done pulses",               done_pulses == 6);
        check("TC16 no underrun across all six",    under_pulses == 0);
        $display("       -> ST_EOF guarantees a clean TX_EN gap between frames");
        $display("          even with the upstream never idling");

        $display("\n[TC17] Single-octet frames back to back");
        do_reset;
        for (i = 0; i < 5; i = i + 1) send_frame(1, 8'hF0 + i[7:0]);
        idle_cycles(8);
        $display("       %0d cycles / %0d runs / %0d done", en_cycles, en_runs, done_pulses);
        check("TC17 GMII: 5 single-octet frames = 5 cycles", en_cycles   == 5);
        check("TC17 five distinct TX_EN pulses",             en_runs     == 5);
        check("TC17 five done pulses",                       done_pulses == 5);

        speed_select = 1'b0;
        do_reset;
        for (i = 0; i < 5; i = i + 1) send_frame(1, 8'hF0 + i[7:0]);
        idle_cycles(8);
        check("TC17 MII: 5 single-octet frames = 10 cycles", en_cycles   == 10);
        check("TC17 MII five distinct TX_EN pulses",         en_runs     == 5);

        $display("\n[TC18] Idle-time noise on data/last/err never raises TX_EN");
        speed_select = 1'b1;
        do_reset;
        for (i = 0; i < 40; i = i + 1) begin
            @(negedge tx_clk);
            data_in  <= $random(seed);
            valid_in <= 1'b0;
            last_in  <= $random(seed);
            err_in   <= $random(seed);
        end
        @(negedge tx_clk);
        last_in <= 1'b0;
        err_in  <= 1'b0;
        idle_cycles(4);
        check("TC18 TX_EN never rose during idle noise", en_cycles == 0);
        check("TC18 TX_ER never rose during idle noise", er_cycles == 0);
        check("TC18 no done pulse",                      done_pulses  == 0);
        check("TC18 no underrun",                        under_pulses == 0);

        $display("\n[TC19] frame_done_out timing for the tx_ifg handshake");
        do_reset;
        send_frame(8, 8'h33);
        idle_cycles(8);
        $display("       last in-frame cycle = %0d, done pulse = %0d",
                 last_en_cyc, done_cyc);
        check("TC19 done lands the cycle after the last in-frame cycle",
              done_cyc == last_en_cyc + 1);
        check("TC19 TX_EN was already low in the done cycle",
              inv_done_with_en == 0);
        $display("       -> wiring frame_done_out to tx_ifg.ifg_start gives:");
        $display("            1 cycle (this pulse) + 24 cycles (ifg_active, MII)");
        $display("          = 25 cycles = 100 bit times >= the 96 of clause 4.4.2");

        $display("\n[TC20] MII 100 Mb/s timing (dut_mii @ 25 MHz)");
        wait (m_frame_done);
        $display("       8 octets -> %0d nibble cycles, TX_EN high %0.1f ns",
                 m_cycles, m_fall - m_rise);
        check("TC20 100 Mb/s MII: 8 octets == 16 nibble cycles", m_cycles == 16);
        check("TC20 100 Mb/s MII: 16 cycles == 640 ns",
              ((m_fall - m_rise) > 639.9) && ((m_fall - m_rise) < 640.1));

        $display("\n[TC21] MII 10 Mb/s timing (dut_slow @ 2.5 MHz)");
        wait (s_frame_done);
        $display("       8 octets -> %0d nibble cycles, TX_EN high %0.1f ns",
                 s_cycles, s_fall - s_rise);
        check("TC21 10 Mb/s MII: 8 octets == 16 nibble cycles", s_cycles == 16);
        check("TC21 10 Mb/s MII: 16 cycles == 6400 ns",
              ((s_fall - s_rise) > 6399.9) && ((s_fall - s_rise) < 6400.1));
        check("TC21 same CYCLE count at 10 and 100 Mb/s", m_cycles == s_cycles);
        $display("       -> 10x the clock period, 10x the duration, SAME cycles");

        $display("\n[TC22] GMII 1000 Mb/s timing (dut @ 125 MHz)");
        speed_select = 1'b1;
        do_reset;
        send_frame(8, 8'h44);
        idle_cycles(6);
        $display("       8 octets -> %0d octet cycles", en_cycles);
        check("TC22 GMII: 8 octets == 8 octet cycles", en_cycles == 8);
        check("TC22 GMII is half the cycles of MII for the same frame",
              en_cycles * 2 == m_cycles);

        $display("\n[TC23] Randomised soak - 40 frames");
        do_reset;
        bad_frames = 0;
        f_count    = 0;
        for (j = 0; j < 40; j = j + 1) begin
            f_len     = 1 + ({$random(seed)} % 80);
            mode_pick = $random(seed);

            speed_select = mode_pick;
            @(negedge tx_clk);
            clear_mon;

            send_frame(f_len, 8'h07 * (j[7:0] + 1));
            idle_cycles(4 + ({$random(seed)} % 6));

            exp_cycles = mode_pick ? f_len : 2 * f_len;
            verify_octets(f_len, 8'h07 * (j[7:0] + 1), mode_pick);

            if ((en_cycles   != exp_cycles) ||
                (verify_bad  != 0)          ||
                (en_runs     != 1)          ||
                (done_pulses != 1)          ||
                (under_pulses != 0)) begin
                bad_frames = bad_frames + 1;
                $display("       frame %0d BAD: mode=%0d len=%0d cycles=%0d(exp %0d) bad=%0d runs=%0d done=%0d under=%0d",
                         j, mode_pick, f_len, en_cycles, exp_cycles,
                         verify_bad, en_runs, done_pulses, under_pulses);
            end
            f_count = f_count + 1;
        end
        $display("       %0d frames transmitted, %0d bad", f_count, bad_frames);
        check("TC23 40 randomised frames all transmitted", f_count    == 40);
        check("TC23 zero bad frames in the soak",           bad_frames == 0);

        $display("\n[TC24] Standing invariants over every cycle of every test");
        idle_cycles(6);
        $display("       total cycles observed on dut : %0d", cyc);
        check("TC24 TX_ER never high while TX_EN low (Table 35-1)",
              inv_carrier_ext == 0);
        check("TC24 underrun never reported while TX_EN low",
              inv_under_idle == 0);
        check("TC24 frame_done_out never overlapped TX_EN",
              inv_done_with_en == 0);
        check("TC24 TXD[7:4] always driven 0 in MII mode",
              inv_mii_hinib == 0);

        $display("\n=========================================================");
        $display(" RESULT : %0d passed, %0d failed, %0d total",
                 pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display(" tx_gmii_mii_advanced_tb : ALL CHECKS PASS");
        else
            $display(" tx_gmii_mii_advanced_tb : FAILURES PRESENT");
        $display("=========================================================");
        $finish;
    end

    initial begin
        #4000000;
        $display("\n*** GLOBAL WATCHDOG - simulation did not finish ***");
        $finish;
    end

endmodule


`default_nettype wire
