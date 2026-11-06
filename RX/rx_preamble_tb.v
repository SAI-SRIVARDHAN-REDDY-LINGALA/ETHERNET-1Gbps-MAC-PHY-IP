// rx_preamble_tb - RX preamble/SFD strip tests.

`timescale 1ns / 1ps
`default_nettype none

module rx_preamble_tb;

    localparam real CLKP = 8.0;

    reg        rx_clk;
    reg        rst_n;
    reg  [7:0] data_in;
    reg        valid_in;
    reg        last_in;
    reg        rx_err_in;

    wire [7:0] data_out;
    wire       valid_out;
    wire       last_out;
    wire       rx_err_out;
    wire       sfd_seen_out;
    wire       frame_ok_out;
    wire       no_sfd_out;

    rx_preamble dut (
        .rx_clk      (rx_clk),
        .rst_n       (rst_n),
        .data_in     (data_in),
        .valid_in    (valid_in),
        .last_in     (last_in),
        .rx_err_in   (rx_err_in),
        .data_out    (data_out),
        .valid_out   (valid_out),
        .last_out    (last_out),
        .rx_err_out  (rx_err_out),
        .sfd_seen_out(sfd_seen_out),
        .frame_ok_out(frame_ok_out),
        .no_sfd_out  (no_sfd_out)
    );

    initial rx_clk = 1'b0;
    always #(CLKP / 2.0) rx_clk = ~rx_clk;

    integer pass_n, fail_n, cyc;
    reg     trace_en;

    integer n_oct, n_frm, n_sfd, n_ok, n_nosfd, n_err, gaps;
    reg     in_frm;
    reg [7:0] cap  [0:255];
    reg       capl [0:255];

    task check;
        input [720:0] name;
        input         ok;
        begin
            if (ok) begin
                pass_n = pass_n + 1;
                $display("  PASS : %0s", name);
            end else begin
                fail_n = fail_n + 1;
                $display("  FAIL : %0s", name);
            end
        end
    endtask

    always @(posedge rx_clk) begin
        cyc = cyc + 1;
        if (trace_en)
            $display("  %4d |  %02h   %b   %b  |  %02h   %b    %b    %b  |  %b    %b    %b",
                     cyc, data_in, valid_in, last_in,
                     data_out, valid_out, last_out, rx_err_out,
                     sfd_seen_out, frame_ok_out, no_sfd_out);

        if (rst_n) begin
            if (valid_out) begin
                if (n_oct < 256) begin
                    cap [n_oct] = data_out;
                    capl[n_oct] = last_out;
                end
                n_oct = n_oct + 1;
                if (last_out)   n_frm = n_frm + 1;
                if (rx_err_out) n_err = n_err + 1;
            end
            if (sfd_seen_out) n_sfd   = n_sfd   + 1;
            if (frame_ok_out) n_ok    = n_ok    + 1;
            if (no_sfd_out)   n_nosfd = n_nosfd + 1;

            if (valid_out && last_out) in_frm = 1'b0;
            else if (valid_out)        in_frm = 1'b1;
            else if (in_frm)           gaps   = gaps + 1;
        end else begin
            in_frm = 1'b0;
        end
    end

    task clear_mon;
        begin
            #0.1;
            n_oct = 0; n_frm = 0; n_sfd = 0; n_ok = 0;
            n_nosfd = 0; n_err = 0; gaps = 0; in_frm = 1'b0;
        end
    endtask

    task banner;
        begin
            $display("   cyc | DIN VLD LST |  DOUT VLD  LST  ERR | SFD  OK  NOSFD");
            $display("  --------------------------------------------------------------");
        end
    endtask

    task do_reset;
        begin
            rst_n     = 1'b0;
            data_in   = 8'h00;
            valid_in  = 1'b0;
            last_in   = 1'b0;
            rx_err_in = 1'b0;
            repeat (3) @(negedge rx_clk);
            rst_n     = 1'b1;
            @(negedge rx_clk);
        end
    endtask

    task beat;
        input [7:0] d;
        input       lst;
        input       er;
        begin
            @(negedge rx_clk);
            data_in   <= d;
            valid_in  <= 1'b1;
            last_in   <= lst;
            rx_err_in <= er;
        end
    endtask

    task quiet;
        begin
            @(negedge rx_clk);
            data_in   <= 8'h00;
            valid_in  <= 1'b0;
            last_in   <= 1'b0;
            rx_err_in <= 1'b0;
        end
    endtask

    task idle_for;
        input integer n;
        begin
            repeat (n) @(negedge rx_clk);
        end
    endtask

    task lead_in;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) beat(8'h55, 1'b0, 1'b0);
            beat(8'hD5, 1'b0, 1'b0);
        end
    endtask

    integer i, bad;

    initial begin
        $dumpfile("rx_preamble_tb.vcd");
        $dumpvars(0, rx_preamble_tb);

        pass_n = 0; fail_n = 0; cyc = 0; trace_en = 1'b0;
        n_oct = 0; n_frm = 0; n_sfd = 0; n_ok = 0;
        n_nosfd = 0; n_err = 0; gaps = 0; in_frm = 1'b0; bad = 0;

        $display("======================================================================");
        $display(" rx_preamble_tb  -  strips PREAMBLE + SFD, hands over the bare frame");
        $display("======================================================================");

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" SUITE 1 : SIMPLE.  7x55, D5, then 'abc'.  Every cycle shown.");
        $display("----------------------------------------------------------------------");
        do_reset;
        clear_mon;
        trace_en = 1'b1;
        banner;

        lead_in(7);
        beat("a", 1'b0, 1'b0);
        beat("b", 1'b0, 1'b0);
        beat("c", 1'b1, 1'b0);
        quiet;
        idle_for(3);
        trace_en = 1'b0;

        $display("");
        $display("  Eleven octets went IN: 55 55 55 55 55 55 55 D5 61 62 63.");
        $display("  Three came OUT: 61 62 63 ('abc'). The eight lead-in octets");
        $display("  produced NO valid_out at all - that is the stripping.");
        $display("");
        $display("  Watch SFD in the trace: it pulses on the cycle the D5 is");
        $display("  consumed, and DOUT is still quiet that cycle. The first");
        $display("  published octet is 'a', the one AFTER the SFD. Preamble and");
        $display("  SFD are not part of the frame (clause 4.2.5), so rx_fcs must");
        $display("  never see them - if it did, every CRC would fail.");
        $display("");
        $display("  OK pulses with LST on the final octet: 'this carrier really");
        $display("  did contain an SFD-delimited frame'. NOSFD stays low.");
        $display("");

        check("exactly 3 octets published",        n_oct === 3);
        check("the 8 lead-in octets were stripped", n_oct === 3);
        check("payload is 'abc'",
              (cap[0] === "a") && (cap[1] === "b") && (cap[2] === "c"));
        check("last_out on 'c' only",
              (capl[0] === 1'b0) && (capl[1] === 1'b0) && (capl[2] === 1'b1));
        check("sfd_seen_out pulsed exactly once",  n_sfd   === 1);
        check("frame_ok_out pulsed exactly once",  n_ok    === 1);
        check("no_sfd_out never fired",            n_nosfd === 0);
        check("no error on a clean frame",         n_err   === 0);
        check("output is contiguous - no bubbles", gaps    === 0);

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" SUITE 2 : BASIC.  Every port, and the robustness rules.");
        $display("----------------------------------------------------------------------");

        do_reset;
        check("2.1 valid_out LOW after reset",    valid_out    === 1'b0);
        check("2.1 last_out LOW after reset",     last_out     === 1'b0);
        check("2.1 sfd_seen_out LOW after reset", sfd_seen_out === 1'b0);
        check("2.1 frame_ok_out LOW after reset", frame_ok_out === 1'b0);
        check("2.1 no_sfd_out LOW after reset",   no_sfd_out   === 1'b0);

        clear_mon;
        lead_in(3);
        beat(8'hAA, 1'b0, 1'b0);
        beat(8'hBB, 1'b1, 1'b0);
        quiet;
        idle_for(3);
        check("2.2 SHORT preamble (3 octets) is ACCEPTED", n_oct === 2);
        check("2.2 payload intact",
              (cap[0] === 8'hAA) && (cap[1] === 8'hBB));
        check("2.2 frame_ok_out fired",                    n_ok === 1);
        $display("        This is the most important robustness rule in the RX");
        $display("        path. Repeaters and PHYs eat preamble octets for clock");
        $display("        recovery, so a frame sent with 7 can arrive with 3.");
        $display("        Clause 4.2.4.2.1 REQUIRES us to accept it. A receiver");
        $display("        that counts to seven drops real traffic.");

        clear_mon;
        beat(8'hD5, 1'b0, 1'b0);
        beat(8'h11, 1'b0, 1'b0);
        beat(8'h22, 1'b1, 1'b0);
        quiet;
        idle_for(3);
        check("2.3 ZERO preamble octets still works",  n_oct === 2);
        check("2.3 payload intact",
              (cap[0] === 8'h11) && (cap[1] === 8'h22));
        check("2.3 sfd_seen_out fired",                n_sfd === 1);
        $display("        The SFD is the only delimiter that matters. That is");
        $display("        precisely what it is FOR - the preamble is just clock");
        $display("        recovery filler, the SFD is the frame boundary.");

        clear_mon;
        lead_in(20);
        beat(8'h77, 1'b1, 1'b0);
        quiet;
        idle_for(3);
        check("2.4 LONG preamble (20 octets) is accepted", n_oct === 1);
        check("2.4 the single payload octet is 0x77",      cap[0] === 8'h77);

        clear_mon;
        beat(8'h55, 1'b0, 1'b0);
        beat(8'h55, 1'b0, 1'b0);
        beat(8'h55, 1'b1, 1'b0);
        quiet;
        idle_for(3);
        check("2.5 no SFD => NOTHING is published",  n_oct   === 0);
        check("2.5 no_sfd_out reports it",           n_nosfd === 1);
        check("2.5 frame_ok_out did NOT fire",       n_ok    === 0);
        check("2.5 no phantom last_out",             n_frm   === 0);
        $display("        A carrier that never delimits a frame produces zero");
        $display("        output. Downstream never learns it happened, which is");
        $display("        correct - there was no frame to process.");

        clear_mon;
        beat(8'hFF, 1'b0, 1'b0);
        beat(8'hEE, 1'b0, 1'b0);
        beat(8'hDD, 1'b1, 1'b0);
        quiet;
        idle_for(3);
        check("2.6 junk carrier publishes nothing",  n_oct   === 0);
        check("2.6 no_sfd_out reports it",           n_nosfd === 1);
        check("2.6 no SFD pulse on garbage",         n_sfd   === 0);

        clear_mon;
        beat(8'h55, 1'b0, 1'b0);
        beat(8'h55, 1'b0, 1'b0);
        beat(8'h5A, 1'b0, 1'b0);
        beat(8'hD5, 1'b0, 1'b0);
        beat(8'h99, 1'b1, 1'b0);
        quiet;
        idle_for(3);
        check("2.7 corrupted preamble kills the carrier", n_oct === 0);
        check("2.7 a later D5 does not rescue it",        n_sfd === 0);
        $display("        Once the lead-in is corrupt we cannot trust where the");
        $display("        frame starts, so ST_DUMP swallows the rest. Accepting");
        $display("        a late D5 would mean guessing at the frame boundary.");

        clear_mon;
        lead_in(7);
        beat(8'h01, 1'b0, 1'b0);
        beat(8'h02, 1'b1, 1'b1);
        quiet;
        idle_for(3);
        check("2.8 both octets still delivered",  n_oct === 2);
        check("2.8 rx_err_out passed through",    n_err === 1);
        check("2.8 frame_ok_out still fires",     n_ok  === 1);
        $display("        frame_ok_out means 'properly delimited', NOT 'good'.");
        $display("        A frame can be well-formed AND damaged - rx_fifo is");
        $display("        what decides to drop it, using err and the CRC.");

        clear_mon;
        lead_in(7);
        beat(8'hA1, 1'b1, 1'b0);
        quiet;
        idle_for(2);
        lead_in(7);
        beat(8'hB1, 1'b1, 1'b0);
        quiet;
        idle_for(3);
        check("2.9 two frames, 2 octets",     n_oct === 2);
        check("2.9 two SFD pulses",           n_sfd === 2);
        check("2.9 two frame_ok pulses",      n_ok  === 2);
        check("2.9 payloads A1 then B1",
              (cap[0] === 8'hA1) && (cap[1] === 8'hB1));
        check("2.9 no state leaked between frames", n_nosfd === 0);

        clear_mon;
        beat(8'hFF, 1'b1, 1'b0);
        quiet;
        idle_for(2);
        lead_in(7);
        beat("X", 1'b1, 1'b0);
        quiet;
        idle_for(3);
        check("2.10 the good frame after junk is received", n_oct === 1);
        check("2.10 and it is 'X'",                         cap[0] === "X");
        check("2.10 junk was reported once",                n_nosfd === 1);
        $display("        ST_DUMP always returns to ST_IDLE on last_in, so one");
        $display("        bad carrier cannot deafen the receiver.");

        clear_mon;
        lead_in(7);
        for (i = 0; i < 60; i = i + 1)
            beat(i[7:0], (i == 59), 1'b0);
        quiet;
        idle_for(3);
        check("2.11 all 60 octets published", n_oct === 60);
        bad = 0;
        for (i = 0; i < 60; i = i + 1)
            if (cap[i] !== i[7:0]) bad = bad + 1;
        check("2.11 ordering held, zero mismatches", bad === 0);
        check("2.11 last_out only on octet 59",
              (capl[59] === 1'b1) && (n_frm === 1));
        check("2.11 60 contiguous cycles, no bubbles", gaps === 0);
        $display("        This is exactly the shape rx_fcs consumes: gapless");
        $display("        octets, last_out on the end, preamble already gone.");

        clear_mon;
        lead_in(7);
        beat(8'h42, 1'b1, 1'b0);
        quiet;
        idle_for(3);
        check("2.12 a 1-octet frame body works", n_oct === 1);
        check("2.12 that octet carries last_out", capl[0] === 1'b1);
        check("2.12 frame_ok fired",              n_ok === 1);

        $display("");
        $display("======================================================================");
        $display(" RESULT : %0d passed, %0d failed, %0d total",
                 pass_n, fail_n, pass_n + fail_n);
        if (fail_n == 0)
            $display(" rx_preamble_tb : ALL CHECKS PASS");
        else
            $display(" rx_preamble_tb : *** FAILURES ***");
        $display("======================================================================");
        $finish;
    end

    initial begin
        #200000;
        $display("");
        $display(" *** TIMEOUT - the bench hung ***");
        $finish;
    end

endmodule

`default_nettype wire

