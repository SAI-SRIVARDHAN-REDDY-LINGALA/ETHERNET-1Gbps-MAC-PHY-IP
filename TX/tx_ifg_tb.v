// tx_ifg_advanced_tb - Advanced IFG tests.

`timescale 1ns / 1ps

module tx_ifg_advanced_tb;

    localparam real CLKP      = 8.0;
    localparam real CLKP_SLOW = 400.0;

    localparam integer EXP_MII   = 24;
    localparam integer EXP_GMII  = 12;
    localparam integer EXP_XGMII = 3;

    reg clk;
    reg clk_slow;

    always #(CLKP/2.0)      clk      = ~clk;
    always #(CLKP_SLOW/2.0) clk_slow = ~clk_slow;

    reg  rst_n;
    reg  speed_select;
    reg  ifg_start;
    wire ifg_active;
    wire ifg_done;

    tx_ifg dut (
        .clk          (clk         ),
        .rst_n        (rst_n       ),
        .speed_select (speed_select),
        .ifg_start    (ifg_start   ),
        .ifg_active   (ifg_active  ),
        .ifg_done     (ifg_done    )
    );

    reg  rst_n_s;
    reg  start_s;
    wire active_s;
    wire done_s;

    tx_ifg dut_slow (
        .clk          (clk_slow),
        .rst_n        (rst_n_s ),
        .speed_select (1'b0    ),
        .ifg_start    (start_s ),
        .ifg_active   (active_s),
        .ifg_done     (done_s  )
    );

    reg  start_x;
    wire active_x;
    wire done_x;

    tx_ifg #(
        .IFG_BIT_TIMES (96),
        .OCTET_BITS    (32)
    ) dut_x (
        .clk          (clk     ),
        .rst_n        (rst_n   ),
        .speed_select (1'b1    ),
        .ifg_start    (start_x ),
        .ifg_active   (active_x),
        .ifg_done     (done_x  )
    );

    integer errors;
    integer checks;

    task check;
        input [95*8:0] name;
        input          cond;
        begin
            checks = checks + 1;
            if (cond) $display("  [PASS] %0s", name);
            else begin
                $display("  [FAIL] %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    integer run_len;
    integer gap_n;
    integer gap_len [0:255];
    integer done_n;
    integer done_run;
    integer done_run_max;
    integer bad_overlap;
    integer bad_spontaneous;
    reg     act_d;
    reg     start_d;

    always @(posedge clk) begin
        if (rst_n) begin

            if (ifg_active && !act_d && !start_d)
                bad_spontaneous = bad_spontaneous + 1;

            if (ifg_done && ifg_active)
                bad_overlap = bad_overlap + 1;

            if (ifg_active) begin
                run_len = run_len + 1;
            end else if (run_len != 0) begin
                if (gap_n < 256) gap_len[gap_n] = run_len;
                gap_n   = gap_n + 1;
                run_len = 0;
            end

            if (ifg_done) begin
                done_n   = done_n + 1;
                done_run = done_run + 1;
                if (done_run > done_run_max) done_run_max = done_run;
            end else begin
                done_run = 0;
            end

            act_d   = ifg_active;
            start_d = ifg_start;
        end
    end

    real t_rise, t_fall;
    always @(posedge ifg_active) t_rise = $realtime;
    always @(negedge ifg_active) t_fall = $realtime;

    integer s_cycles;
    integer s_done_n;
    real    s_rise, s_fall;

    always @(posedge clk_slow) begin
        if (rst_n_s) begin
            if (active_s) s_cycles = s_cycles + 1;
            if (done_s)   s_done_n = s_done_n + 1;
        end
    end
    always @(posedge active_s) s_rise = $realtime;
    always @(negedge active_s) s_fall = $realtime;

    integer x_cycles;
    integer x_done_n;

    always @(posedge clk) begin
        if (rst_n) begin
            if (active_x) x_cycles = x_cycles + 1;
            if (done_x)   x_done_n = x_done_n + 1;
        end
    end

    task clear_mon;
        begin
            run_len         = 0;
            gap_n           = 0;
            done_n          = 0;
            done_run        = 0;
            done_run_max    = 0;
            bad_overlap     = 0;
            bad_spontaneous = 0;
        end
    endtask

    task do_reset;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            repeat (2) @(negedge clk);
            rst_n = 1'b1;

            repeat (3) @(negedge clk);
            act_d   = 1'b0;
            start_d = 1'b0;
            clear_mon;
            @(negedge clk);
        end
    endtask

    task pulse_start;
        input integer n;
        integer k;
        begin
            @(negedge clk);
            ifg_start = 1'b1;
            for (k = 0; k < n; k = k + 1) @(negedge clk);
            ifg_start = 1'b0;
        end
    endtask

    task wait_gaps;
        input integer n;
        begin
            while (done_n < n) @(negedge clk);
        end
    endtask

    task idle_cycles;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(negedge clk);
        end
    endtask

    integer i;
    integer seed;
    integer soak_bad;
    integer snap_done;
    reg     act_at_reset;

    initial begin
        $dumpfile("tx_ifg_tb.vcd");
        $dumpvars(0, tx_ifg_advanced_tb);

        clk          = 1'b0;
        clk_slow     = 1'b0;
        rst_n        = 1'b0;
        rst_n_s      = 1'b0;
        speed_select = 1'b1;
        ifg_start    = 1'b0;
        start_s      = 1'b0;
        start_x      = 1'b0;
        errors       = 0;
        checks       = 0;
        s_cycles     = 0;
        s_done_n     = 0;
        x_cycles     = 0;
        x_done_n     = 0;
        seed         = 32'h1EEE_0803;
        soak_bad     = 0;
        act_at_reset = 1'b0;
        act_d        = 1'b0;
        start_d      = 1'b0;
        clear_mon;

        $display("================================================================");
        $display(" tx_ifg_advanced_tb");
        $display(" IEEE Std 802.3-2022, clause 4.4.2 : interFrameGap = 96 bit times");
        $display("   GMII (35.2)     8 bits/cycle -> %0d cycles  [PRIMARY/nominal]", EXP_GMII);
        $display("   MII  (22.2.3)   4 bits/cycle -> %0d cycles  [other-mode sanity]", EXP_MII);
        $display("   Wide-octet     32 bits/cycle -> %0d cycles  [parametric check]", EXP_XGMII);
        $display("================================================================");

        do_reset;

        $display("\n[TC1] nominal GMII gap, single start pulse (GTX_CLK = 125 MHz)");
        speed_select = 1'b1;
        pulse_start(1);
        wait_gaps(1);
        idle_cycles(2);

        $display("  measured : %0d cycles = %0d bit times = %0.1f ns @125MHz",
                 gap_len[0], gap_len[0]*8, t_fall - t_rise);
        check("TC1 gap == 12 cycles", gap_len[0] == EXP_GMII);
        check("TC1 gap == 96 bit times on an octet bus", gap_len[0]*8 == 96);
        check("TC1 gap == 96.0 ns at 125 MHz GTX_CLK", (t_fall - t_rise) == 96.0);
        check("TC1 exactly one gap occurred", gap_n == 1);

        $display("  -- known failure modes this must NOT match --");
        $display("     off-by-one (load N-1)     -> 11 cycles = 88 bit times (92%%)");
        $display("     wrong width (nibble math) -> 24 cycles = 192 bit times (200%%)");
        check("TC1 gap is NOT 11 cycles (off-by-one)", gap_len[0] != 11);
        check("TC1 gap is NOT 24 cycles (nibble-width math on an octet bus)",
              gap_len[0] != EXP_MII);

        $display("\n[TC2] derived cycle counts inside the DUT");
        $display("  IFG_BIT_TIMES=%0d NIBBLE_BITS=%0d OCTET_BITS=%0d",
                 dut.IFG_BIT_TIMES, dut.NIBBLE_BITS, dut.OCTET_BITS);
        $display("  IFG_CYCLES_NIBBLE=%0d  IFG_CYCLES_OCTET=%0d",
                 dut.IFG_CYCLES_NIBBLE, dut.IFG_CYCLES_OCTET);
        check("TC2 IFG_BIT_TIMES == 96 (clause 4.4.2 minimum)",
              dut.IFG_BIT_TIMES == 96);
        check("TC2 IFG_CYCLES_NIBBLE == 96/4 == 24", dut.IFG_CYCLES_NIBBLE == 24);
        check("TC2 IFG_CYCLES_OCTET  == 96/8 == 12", dut.IFG_CYCLES_OCTET  == 12);

        $display("\n[TC3] ifg_done pulse shape");
        $display("  done assertions = %0d, widest run = %0d cycle(s)",
                 done_n, done_run_max);
        check("TC3 ifg_done asserted exactly once per gap", done_n == 1);
        check("TC3 ifg_done exactly 1 cycle wide", done_run_max == 1);
        check("TC3 ifg_done low again afterwards", ifg_done === 1'b0);
        check("TC3 ifg_active low again afterwards", ifg_active === 1'b0);

        $display("\n[TC4] ifg_start held high for 6 cycles, dropped mid-gap");
        do_reset;
        pulse_start(6);
        wait_gaps(1);
        idle_cycles(3);
        $display("  measured : %0d cycles, gaps = %0d", gap_len[0], gap_n);
        check("TC4 held-high start did not extend the gap", gap_len[0] == EXP_GMII);
        check("TC4 held-high start did not spawn a second gap", gap_n == 1);
        check("TC4 still exactly one ifg_done", done_n == 1);

        $display("\n[TC5] ifg_start re-pulsed at cycle 6 of an active gap");
        do_reset;
        pulse_start(1);
        while (run_len < 6) @(negedge clk);
        ifg_start = 1'b1;
        @(negedge clk);
        ifg_start = 1'b0;
        wait_gaps(1);
        idle_cycles(3);
        $display("  measured : %0d cycles, gaps = %0d", gap_len[0], gap_n);
        check("TC5 mid-gap retrigger did not restart the counter",
              gap_len[0] == EXP_GMII);
        check("TC5 mid-gap retrigger did not add a gap", gap_n == 1);

        $display("\n[TC6] ifg_start tied high -> continuous back-to-back gaps");
        do_reset;
        @(negedge clk);
        ifg_start = 1'b1;
        wait_gaps(4);
        ifg_start = 1'b0;
        idle_cycles(3);
        $display("  gaps measured : %0d %0d %0d %0d (done_n=%0d)",
                 gap_len[0], gap_len[1], gap_len[2], gap_len[3], done_n);
        soak_bad = 0;
        for (i = 0; i < 4; i = i + 1)
            if (gap_len[i] != EXP_GMII) soak_bad = soak_bad + 1;
        check("TC6 four consecutive gaps, all 12 cycles", soak_bad == 0);
        check("TC6 exactly four ifg_done pulses", done_n == 4);
        check("TC6 no ifg_done ever overlapped ifg_active", bad_overlap == 0);

        $display("\n[TC7] speed_select = 0 (nibble/MII datapath) on the 125 MHz clock");
        $display("  NOTE: width-math check only. 24 cycles @125MHz = 192 ns here,");
        $display("  which is NOT compared against the 960 ns 802.3 figure - that");
        $display("  only holds at MII's real 25 MHz TX_CLK (see TC11).");
        speed_select = 1'b0;
        do_reset;
        pulse_start(1);
        wait_gaps(1);
        idle_cycles(2);
        $display("  measured : %0d cycles = %0d bit times = %0.1f ns (informational)",
                 gap_len[0], gap_len[0]*4, t_fall - t_rise);
        check("TC7 nibble-width gap == 24 cycles", gap_len[0] == EXP_MII);
        check("TC7 nibble-width gap == 96 bit times on a nibble bus",
              gap_len[0]*4 == 96);
        check("TC7 nibble-width gap is NOT 12 (mode really did change)",
              gap_len[0] != EXP_GMII);
        speed_select = 1'b1;

        $display("\n[TC8] speed_select flipped mid-gap, 0 -> 1 (MII gap running)");
        speed_select = 1'b0;
        do_reset;
        pulse_start(1);
        while (run_len < 5) @(negedge clk);
        speed_select = 1'b1;
        wait_gaps(1);
        idle_cycles(2);
        $display("  measured : %0d cycles (must stay 24)", gap_len[0]);
        check("TC8a MII gap survived a mid-gap flip to GMII",
              gap_len[0] == EXP_MII);

        $display("[TC8] speed_select flipped mid-gap, 1 -> 0 (GMII gap running)");
        speed_select = 1'b1;
        do_reset;
        pulse_start(1);
        while (run_len < 4) @(negedge clk);
        speed_select = 1'b0;
        wait_gaps(1);
        idle_cycles(2);
        $display("  measured : %0d cycles (must stay 12)", gap_len[0]);
        check("TC8b GMII gap survived a mid-gap flip to MII",
              gap_len[0] == EXP_GMII);
        speed_select = 1'b1;

        $display("\n[TC9] async reset asserted mid-gap, off the clock edge");
        speed_select = 1'b1;
        do_reset;
        pulse_start(1);
        while (run_len < 6) @(negedge clk);
        snap_done = done_n;
        #(CLKP/4.0);
        rst_n = 1'b0;
        #1;
        act_at_reset = ifg_active;
        $display("  ifg_active %0d ns after an off-edge reset : %0b",
                 1, act_at_reset);
        check("TC9 ifg_active cleared between clock edges (reset is async)",
              act_at_reset === 1'b0);
        check("TC9 ifg_done also low during reset", ifg_done === 1'b0);
        check("TC9 the aborted gap produced no ifg_done", done_n == snap_done);

        repeat (2) @(negedge clk);
        rst_n   = 1'b1;
        repeat (3) @(negedge clk);
        act_d   = 1'b0;
        start_d = 1'b0;
        clear_mon;
        @(negedge clk);
        pulse_start(1);
        wait_gaps(1);
        idle_cycles(2);
        $display("  post-reset gap : %0d cycles", gap_len[0]);
        check("TC9 full-length gap after reset recovery", gap_len[0] == EXP_GMII);
        check("TC9 exactly one gap after recovery", gap_n == 1);

        $display("\n[TC10] reset released with ifg_start already high");
        $display("  expect the FIRST gap to use the synchronizer's safe reset");
        $display("  default (%0d cycles), not the true speed_select=1 value (%0d),",
                 EXP_MII, EXP_GMII);
        $display("  because the sync has not yet propagated speed_select=1.");
        speed_select = 1'b1;
        @(negedge clk);
        rst_n     = 1'b0;
        ifg_start = 1'b1;
        repeat (2) @(negedge clk);
        rst_n   = 1'b1;
        act_d   = 1'b0;
        start_d = 1'b0;
        clear_mon;
        @(negedge clk);
        @(negedge clk);
        ifg_start = 1'b0;
        wait_gaps(1);
        idle_cycles(2);
        $display("  first post-reset gap : %0d cycles (expected %0d, the sync's",
                 gap_len[0], EXP_MII);
        $display("  safe reset-default value, because ifg_start raced the sync)");
        check("TC10a first gap after reset uses the sync's safe reset default",
              gap_len[0] == EXP_MII);
        check("TC10a no partial or double gap", gap_n == 1);

        idle_cycles(3);
        pulse_start(1);
        wait_gaps(2);
        idle_cycles(2);
        $display("  next gap once settled : %0d cycles (expected %0d, true GMII)",
                 gap_len[1], EXP_GMII);
        check("TC10b once settled, gap correctly reflects speed_select = 1 (GMII)",
              gap_len[1] == EXP_GMII);

        $display("\n[TC11] 10 Mb/s MII : same DUT, 2.5 MHz TX_CLK");
        @(negedge clk_slow);
        rst_n_s = 1'b0;
        repeat (2) @(negedge clk_slow);
        rst_n_s  = 1'b1;
        s_cycles = 0;
        s_done_n = 0;
        @(negedge clk_slow);
        @(negedge clk_slow); start_s = 1'b1;
        @(negedge clk_slow); start_s = 1'b0;
        while (s_done_n == 0) @(negedge clk_slow);
        @(negedge clk_slow);
        $display("  measured : %0d cycles, %0.1f ns  (= %0.2f us)",
                 s_cycles, s_fall - s_rise, (s_fall - s_rise)/1000.0);
        $display("  bit time at 10 Mb/s = 100 ns, so 96 bit times = 9600 ns");
        check("TC11 10 Mb/s gap is the SAME 24 cycles", s_cycles == EXP_MII);
        check("TC11 10 Mb/s gap == 9600.0 ns == 9.6 us",
              (s_fall - s_rise) == 9600.0);
        check("TC11 exactly one ifg_done at 10 Mb/s", s_done_n == 1);

        $display("\n[TC12] start pulse aligned to the terminal cycle (count==1)");
        do_reset;
        pulse_start(1);
        while (run_len < 11) @(negedge clk);
        ifg_start = 1'b1;
        @(negedge clk);
        ifg_start = 1'b0;
        idle_cycles(10);
        $display("  gaps = %0d, done_n = %0d, ifg_active = %0b",
                 gap_n, done_n, ifg_active);
        check("TC12 terminal-cycle start did not extend the gap",
              gap_len[0] == EXP_GMII);
        check("TC12 terminal-cycle start did not start a second gap",
              gap_n == 1);
        check("TC12 module is idle afterwards", ifg_active === 1'b0);

        $display("\n[TC13] launch and completion latency");
        do_reset;
        @(negedge clk);
        ifg_start = 1'b1;
        @(negedge clk);
        ifg_start = 1'b0;
        check("TC13 ifg_active high 1 cycle after start was sampled",
              ifg_active === 1'b1);
        i = 0;
        while (done_n == 0) begin
            @(negedge clk);
            i = i + 1;
        end

        $display("  ifg_active high for : %0d cycles", gap_len[0]);
        $display("  ifg_done observed   : %0d cycles after launch", i);
        check("TC13 ifg_active spans exactly 12 cycles", gap_len[0] == EXP_GMII);
        check("TC13 registered ifg_done arrives on cycle 13 (12 + 1)",
              i == EXP_GMII + 1);
        check("TC13 waiting on ifg_done still satisfies 96 bit times",
              (i * 8) >= 96);
        check("TC13 gating on !ifg_active satisfies 96 bit times exactly",
              (gap_len[0] * 8) == 96);
        check("TC13 ifg_active already low when done fires", bad_overlap == 0);
        idle_cycles(2);

        $display("\n[TC14] third instance, OCTET_BITS = 32 (wide-octet path)");
        x_cycles = 0;
        x_done_n = 0;
        @(negedge clk); start_x = 1'b1;
        @(negedge clk); start_x = 1'b0;
        while (x_done_n == 0) @(negedge clk);
        @(negedge clk);
        $display("  measured : %0d cycles = %0d bit times",
                 x_cycles, x_cycles*32);
        check("TC14 32-bit octet-path gap == 3 cycles", x_cycles == EXP_XGMII);
        check("TC14 32-bit octet-path gap == 96 bit times", x_cycles*32 == 96);
        check("TC14 exactly one ifg_done", x_done_n == 1);

        $display("\n[TC15] randomised soak : 40 gaps, random hold and retrigger");
        do_reset;
        for (i = 0; i < 40; i = i + 1) begin
            idle_cycles(({$random(seed)} % 6) + 1);
            pulse_start(({$random(seed)} % 4) + 1);

            if (({$random(seed)} % 2) == 0) begin
                while (run_len < (({$random(seed)} % 10) + 1)) @(negedge clk);
                ifg_start = 1'b1;
                @(negedge clk);
                ifg_start = 1'b0;
            end
            wait_gaps(i + 1);
        end
        idle_cycles(3);
        soak_bad = 0;
        for (i = 0; i < 40; i = i + 1)
            if (gap_len[i] != EXP_GMII) begin
                soak_bad = soak_bad + 1;
                $display("    gap %0d measured %0d cycles", i, gap_len[i]);
            end
        $display("  gaps completed = %0d, wrong-length gaps = %0d",
                 gap_n, soak_bad);
        check("TC15 all 40 soak gaps completed", gap_n == 40);
        check("TC15 every soak gap was exactly 12 cycles", soak_bad == 0);
        check("TC15 one ifg_done per gap, no more", done_n == 40);
        check("TC15 ifg_done never wider than 1 cycle", done_run_max == 1);

        $display("\n[TC16] global invariants");
        $display("  spontaneous ifg_active rises : %0d", bad_spontaneous);
        $display("  done/active overlaps         : %0d", bad_overlap);
        check("TC16 ifg_active never rose without a start request",
              bad_spontaneous == 0);
        check("TC16 ifg_done never overlapped ifg_active", bad_overlap == 0);

        $display("\n[TC17] speed_select synchronizer settle-time determinism");
        speed_select = 1'b1;
        do_reset;
        speed_select = 1'b0;
        ifg_start    = 1'b1;
        @(negedge clk);
        ifg_start    = 1'b0;
        wait_gaps(1);
        idle_cycles(2);
        $display("  gap right after the flip : %0d cycles (must be %0d - the",
                 gap_len[0], EXP_GMII);
        $display("  synchronizer had not yet propagated the flip when ifg_start loaded)");
        check("TC17a gap immediately after a same-edge flip used the OLD value",
              gap_len[0] == EXP_GMII);

        pulse_start(1);
        wait_gaps(2);
        idle_cycles(2);
        $display("  gap after the sync has settled : %0d cycles (must be %0d)",
                 gap_len[1], EXP_MII);
        check("TC17b gap after settling used the NEW value", gap_len[1] == EXP_MII);
        speed_select = 1'b1;

        $display("\n================================================================");
        $display(" checks run : %0d", checks);
        if (errors == 0)
            $display(" RESULT: ALL %0d ADVANCED CHECKS PASSED", checks);
        else
            $display(" RESULT: %0d of %0d CHECK(S) FAILED", errors, checks);
        $display("================================================================");
        $finish;
    end

    initial begin
        #500000;
        $display("\n [FAIL] GLOBAL TIMEOUT - bench did not finish");
        $finish;
    end

endmodule

