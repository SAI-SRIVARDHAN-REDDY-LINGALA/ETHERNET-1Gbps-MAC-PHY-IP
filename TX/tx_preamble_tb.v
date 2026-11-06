// tx_preamble_advanced_tb - Advanced preamble tests.

`timescale 1ns / 1ps

module tx_preamble_advanced_tb;

    reg        tx_clk;
    reg        rst_n;
    reg        start_in;
    reg        ready_in;
    wire [7:0] data_out;
    wire       valid_out;
    wire       sfd_done_out;

    localparam CLKP = 100;
    always #(CLKP/2) tx_clk = ~tx_clk;

    tx_preamble dut (
        .tx_clk       (tx_clk      ),
        .rst_n        (rst_n       ),
        .start_in     (start_in    ),
        .ready_out     (ready_in    ),
        .data_out     (data_out    ),
        .valid_out    (valid_out   ),
        .sfd_done_out (sfd_done_out)
    );

    integer errors;
    integer tests;
    integer cap_n;
    reg [7:0] cap [0:255];
    integer sfd_n;
    reg     sfd_seen;
    integer sfd_run;
    integer sfd_run_max;
    integer launch_time;
    integer cycle;
    integer first_octet_cycle;

    task check;
        input [64*8-1:0] name;
        input            cond;
        begin
            tests = tests + 1;
            if (cond) $display("    [PASS] %0s", name);
            else begin
                $display("    [FAIL] %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    task clear_sb;
        begin
            cap_n             = 0;
            sfd_n             = 0;
            sfd_seen          = 1'b0;
            first_octet_cycle = -1;
        end
    endtask

    always @(posedge tx_clk) begin
        cycle = cycle + 1;
        if (rst_n) begin
            if (valid_out && ready_in) begin
                if (cap_n < 256) cap[cap_n] = data_out;
                if (first_octet_cycle < 0) first_octet_cycle = cycle;
                cap_n = cap_n + 1;
            end
            if (sfd_done_out) begin
                sfd_n    = sfd_n + 1;
                sfd_seen = 1'b1;
                sfd_run  = sfd_run + 1;
                if (sfd_run > sfd_run_max) sfd_run_max = sfd_run;
            end else begin
                sfd_run = 0;
            end
        end else begin
            sfd_run = 0;
        end
    end

    task pulse_start;
        begin
            @(negedge tx_clk); start_in = 1'b1;
            @(negedge tx_clk); start_in = 1'b0;
        end
    endtask

    task wait_sfd;
        input integer max_cycles;
        integer g;
        begin
            g = 0;
            while (!sfd_seen && g < max_cycles) begin
                @(negedge tx_clk);
                g = g + 1;
            end
            if (!sfd_seen) begin
                $display("    [FAIL] TIMEOUT waiting for sfd_done_out");
                errors = errors + 1;
            end
        end
    endtask

    task wait_octets;
        input integer n;
        integer g;
        begin
            g = 0;
            while (cap_n < n && g < 1000) begin
                @(negedge tx_clk);
                g = g + 1;
            end
        end
    endtask

    task expect_group;
        input [64*8-1:0] name;
        input integer    base;
        integer j;
        reg              ok;
        begin
            ok = 1'b1;
            for (j = 0; j < 7; j = j + 1)
                if (cap[base+j] !== 8'h55) ok = 1'b0;
            if (cap[base+7] !== 8'hD5) ok = 1'b0;
            check(name, ok);
            if (!ok) begin
                $display("      dump: %02h %02h %02h %02h %02h %02h %02h %02h",
                         cap[base+0], cap[base+1], cap[base+2], cap[base+3],
                         cap[base+4], cap[base+5], cap[base+6], cap[base+7]);
            end
        end
    endtask

    task do_reset;
        begin
            @(negedge tx_clk); rst_n = 1'b0;
            repeat (3) @(negedge tx_clk);
            rst_n = 1'b1;
            @(negedge tx_clk);
        end
    endtask

    reg [63:0]    wire_bits;
    reg [8*8-1:0] bitstr;

    integer i, j, k, b, p, dev, devpos, stall;
    integer seed;
    reg     exp_bit;
    reg     ok;
    integer groups;

    initial begin
        $dumpfile("tx_preamble_tb.vcd");
        $dumpvars(0, tx_preamble_advanced_tb);

        tx_clk      = 1'b0;
        rst_n       = 1'b0;
        start_in    = 1'b0;
        ready_in    = 1'b0;
        errors      = 0;
        tests       = 0;
        cycle       = 0;
        sfd_run     = 0;
        sfd_run_max = 0;
        seed        = 32'h1234_5678;
        clear_sb;

        $display("=================================================================");
        $display(" tx_preamble_advanced_tb : tx_preamble corner-case sweep");
        $display(" IEEE 802.3-2022  3.2.1 / 3.2.2 / 3.3");
        $display("=================================================================");

        do_reset;
        ready_in = 1'b1;

        $display("\n[TC1] nominal burst, downstream always ready");
        clear_sb;
        pulse_start;
        wait_sfd(50);
        check("TC1 octet count == 8", cap_n == 8);
        expect_group("TC1 sequence = 7x0x55 + 0xD5", 0);
        check("TC1 exactly one sfd_done_out pulse", sfd_n == 1);
        check("TC1 valid_out low at end", valid_out === 1'b0);

        $display("\n[TC2] 1-cycle stall injected at every octet boundary");
        for (i = 0; i < 8; i = i + 1) begin
            clear_sb;
            $display("  -- ready_in dropped for 1 cycle after %0d octet(s) taken --", i);
            if (i == 0) begin

                @(negedge tx_clk); ready_in = 1'b0;
                pulse_start;
                @(negedge tx_clk); ready_in = 1'b1;
            end else begin
                pulse_start;
                wait_octets(i);

                ready_in = 1'b0;
                @(negedge tx_clk); ready_in = 1'b1;
            end
            wait_sfd(80);
            if (cap_n != 8) begin
                $display("    [FAIL] stall@%0d : octet count %0d, expected 8", i, cap_n);
                errors = errors + 1;
                tests  = tests + 1;
            end else begin
                expect_group("TC2 sequence intact after stall", 0);
            end
            if (sfd_n != 1) begin
                $display("    [FAIL] stall@%0d : sfd pulses %0d, expected 1", i, sfd_n);
                errors = errors + 1;
                tests  = tests + 1;
            end
        end

        $display("\n[TC3] long stall (25 cycles) in mid-preamble");
        clear_sb;
        pulse_start;
        wait_octets(4);
        ready_in = 1'b0;

        repeat (25) begin
            @(negedge tx_clk);
            if (valid_out !== 1'b1 || data_out !== 8'h55) begin
                $display("    [FAIL] bus not held during stall: v=%b d=%02h",
                         valid_out, data_out);
                errors = errors + 1;
            end
        end
        check("TC3 no octets leaked during 25-cycle stall", cap_n == 4);
        @(negedge tx_clk); ready_in = 1'b1;
        wait_sfd(80);
        check("TC3 octet count == 8", cap_n == 8);
        expect_group("TC3 sequence intact after long stall", 0);

        $display("\n[TC4] ready_in low across the launch, released after 10 cycles");
        clear_sb;
        @(negedge tx_clk); ready_in = 1'b0;
        pulse_start;
        repeat (10) @(negedge tx_clk);
        check("TC4 nothing accepted while never-ready", cap_n == 0);
        check("TC4 valid_out asserted and waiting", valid_out === 1'b1);
        check("TC4 first octet held as 0x55", data_out === 8'h55);
        @(negedge tx_clk); ready_in = 1'b1;
        wait_sfd(80);
        check("TC4 octet count == 8 (nothing lost)", cap_n == 8);
        expect_group("TC4 sequence intact", 0);

        $display("\n[TC5] back-to-back bursts");
        clear_sb;
        for (i = 0; i < 3; i = i + 1) begin
            sfd_seen = 1'b0;
            pulse_start;
            wait_sfd(60);
        end
        check("TC5 3 bursts -> 24 octets", cap_n == 24);
        check("TC5 3 sfd_done_out pulses", sfd_n == 3);
        expect_group("TC5 burst 1 intact",  0);
        expect_group("TC5 burst 2 intact",  8);
        expect_group("TC5 burst 3 intact", 16);

        $display("\n[TC6] start_in held high -> continuous generation");
        clear_sb;
        @(negedge tx_clk); start_in = 1'b1;
        repeat (30) @(negedge tx_clk);
        start_in = 1'b0;

        repeat (12) @(negedge tx_clk);
        groups = cap_n / 8;
        $display("    captured %0d octets = %0d complete burst(s)", cap_n, groups);
        check("TC6 octet count is a whole number of bursts", (cap_n % 8) == 0);
        check("TC6 at least 3 bursts generated", groups >= 3);
        check("TC6 sfd pulses == burst count", sfd_n == groups);
        ok = 1'b1;
        for (i = 0; i < cap_n; i = i + 1)
            if (cap[i] !== ((i % 8 == 7) ? 8'hD5 : 8'h55)) ok = 1'b0;
        check("TC6 every burst is 7x0x55 + 0xD5", ok);

        $display("\n[TC7] async reset mid-burst, then recovery");
        clear_sb;
        pulse_start;
        wait_octets(3);
        rst_n = 1'b0;
        @(negedge tx_clk);
        check("TC7 valid_out cleared by reset",    valid_out    === 1'b0);
        check("TC7 no spurious sfd_done_out",      sfd_done_out === 1'b0);
        check("TC7 data_out cleared by reset",     data_out     === 8'h00);
        check("TC7 partial burst was truncated",   cap_n == 3);
        check("TC7 no sfd pulse for aborted burst", sfd_n == 0);
        repeat (2) @(negedge tx_clk);
        rst_n = 1'b1;
        @(negedge tx_clk);
        clear_sb;
        pulse_start;
        wait_sfd(60);
        check("TC7 clean burst after reset: 8 octets", cap_n == 8);
        expect_group("TC7 post-reset sequence intact", 0);

        $display("\n[TC8] spurious start_in mid-burst must be ignored");
        clear_sb;
        pulse_start;
        wait_octets(3);
        @(negedge tx_clk); start_in = 1'b1;
        @(negedge tx_clk);
        @(negedge tx_clk); start_in = 1'b0;
        wait_sfd(80);
        check("TC8 still exactly 8 octets", cap_n == 8);
        check("TC8 still exactly 1 sfd pulse", sfd_n == 1);
        expect_group("TC8 sequence unperturbed", 0);

        $display("\n[TC9] sfd_done_out pulse width");
        $display("    worst consecutive-high run observed so far = %0d", sfd_run_max);
        check("TC9 sfd_done_out never wider than 1 cycle", sfd_run_max == 1);

        $display("\n[TC10] BIT-LEVEL wire order (802.3 clause 3.3, LSB first)");
        clear_sb;
        pulse_start;
        wait_sfd(60);
        check("TC10 clean 8-octet burst captured", cap_n == 8);

        for (i = 0; i < 8; i = i + 1)
            for (b = 0; b < 8; b = b + 1)
                wire_bits[i*8 + b] = cap[i][b];

        for (b = 0; b < 8; b = b + 1)
            bitstr[(7-b)*8 +: 8] = wire_bits[56+b] ? "1" : "0";
        $display("    SFD as transmitted (first bit leftmost) : %0s", bitstr);
        $display("    802.3 clause 3.2.2 requires             : 10101011");
        check("TC10 SFD wire pattern == 10101011", bitstr === "10101011");

        dev = 0;
        for (p = 0; p < 56; p = p + 1) begin
            exp_bit = (p % 2 == 0) ? 1'b1 : 1'b0;
            if (wire_bits[p] !== exp_bit) dev = dev + 1;
        end
        check("TC10 all 56 preamble bits strictly alternate", dev == 0);

        dev    = 0;
        devpos = -1;
        for (p = 0; p < 64; p = p + 1) begin
            exp_bit = (p % 2 == 0) ? 1'b1 : 1'b0;
            if (wire_bits[p] !== exp_bit) begin
                dev    = dev + 1;
                devpos = p;
            end
        end
        $display("    deviations from alternation across 64 bits : %0d (at index %0d)",
                 dev, devpos);
        check("TC10 exactly one deviation in the 64-bit sequence", dev == 1);
        check("TC10 the break is the LAST bit (index 63), not the first",
              devpos == 63);
        $display("    -> confirms the playlist's \"first bit changes\" claim is wrong");

        $display("\n[TC11] randomised backpressure, 20 consecutive bursts");
        clear_sb;
        for (i = 0; i < 20; i = i + 1) begin
            sfd_seen = 1'b0;
            pulse_start;
            j = 0;
            while (!sfd_seen && j < 300) begin
                @(negedge tx_clk);
                ready_in = (($random(seed) % 100) < 60) ? 1'b1 : 1'b0;
                j = j + 1;
            end
            if (!sfd_seen) begin
                $display("    [FAIL] burst %0d never completed", i);
                errors = errors + 1;
            end
            @(negedge tx_clk); ready_in = 1'b1;
        end
        check("TC11 20 bursts -> 160 octets", cap_n == 160);
        check("TC11 20 sfd_done_out pulses",  sfd_n == 20);
        ok = 1'b1;
        for (i = 0; i < cap_n; i = i + 1)
            if (cap[i] !== ((i % 8 == 7) ? 8'hD5 : 8'h55)) ok = 1'b0;
        check("TC11 no octet lost or duplicated under random handshake", ok);

        $display("\n[TC12] reset released while start_in is already high");
        @(negedge tx_clk); rst_n = 1'b0; start_in = 1'b1; ready_in = 1'b1;
        repeat (3) @(negedge tx_clk);
        clear_sb;
        rst_n = 1'b1;
        @(negedge tx_clk);
        @(negedge tx_clk); start_in = 1'b0;
        wait_sfd(60);
        check("TC12 burst launched cleanly out of reset", cap_n == 8);
        expect_group("TC12 sequence intact", 0);
        check("TC12 exactly 1 sfd pulse", sfd_n == 1);

        $display("\n[TC13] launch-to-first-octet latency");
        clear_sb;
        @(negedge tx_clk); start_in = 1'b1; launch_time = cycle + 1;
        @(negedge tx_clk); start_in = 1'b0;
        wait_sfd(60);
        $display("    start_in sampled on cycle %0d, first octet on cycle %0d",
                 launch_time, first_octet_cycle);
        check("TC13 latency is exactly 1 cycle",
              (first_octet_cycle - launch_time) == 1);

        $display("\n[TC14] minimum configuration: PREAMBLE_COUNT = 1");
        run_min_config;

        $display("\n=================================================================");
        $display(" checks run : %0d", tests);
        if (errors == 0)
            $display(" RESULT     : ALL ADVANCED CHECKS PASSED");
        else
            $display(" RESULT     : %0d CHECK(S) FAILED", errors);
        $display("=================================================================");
        $finish;
    end

    reg        p1_start;
    reg        p1_ready;
    wire [7:0] p1_data;
    wire       p1_valid;
    wire       p1_sfd;

    integer   p1_n;
    reg [7:0] p1_cap [0:7];
    integer   p1_sfd_n;

    tx_preamble #(.PREAMBLE_COUNT(1)) dut_p1 (
        .tx_clk       (tx_clk  ),
        .rst_n        (rst_n   ),
        .start_in     (p1_start),
        .ready_out     (p1_ready),
        .data_out     (p1_data ),
        .valid_out    (p1_valid),
        .sfd_done_out (p1_sfd  )
    );

    initial begin
        p1_start = 1'b0;
        p1_ready = 1'b0;
        p1_n     = 0;
        p1_sfd_n = 0;
    end

    always @(posedge tx_clk) begin
        if (rst_n) begin
            if (p1_valid && p1_ready) begin
                if (p1_n < 8) p1_cap[p1_n] = p1_data;
                p1_n = p1_n + 1;
            end
            if (p1_sfd) p1_sfd_n = p1_sfd_n + 1;
        end
    end

    task run_min_config;
        integer g;
        begin
            p1_n     = 0;
            p1_sfd_n = 0;
            @(negedge tx_clk); p1_ready = 1'b1; p1_start = 1'b1;
            @(negedge tx_clk); p1_start = 1'b0;
            g = 0;
            while (p1_sfd_n == 0 && g < 40) begin
                @(negedge tx_clk);
                g = g + 1;
            end
            check("TC14 PREAMBLE_COUNT=1 -> 2 octets total", p1_n == 2);
            check("TC14 octet 0 == 0x55", p1_cap[0] === 8'h55);
            check("TC14 octet 1 == 0xD5", p1_cap[1] === 8'hD5);
            check("TC14 exactly 1 sfd pulse", p1_sfd_n == 1);
            @(negedge tx_clk); p1_ready = 1'b0;
        end
    endtask

    initial begin
        #400000;
        $display("\n [FAIL] GLOBAL TIMEOUT - testbench hung");
        $display(" errors so far: %0d", errors);
        $finish;
    end

endmodule

