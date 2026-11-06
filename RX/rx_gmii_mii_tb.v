// rx_gmii_mii_tb - RX pin sampler tests.

`timescale 1ns / 1ps
`default_nettype none

module rx_gmii_mii_tb;

    localparam real CLKP = 8.0;

    reg        rx_clk;
    reg        rst_n;
    reg        speed_select;
    reg  [7:0] gmii_rxd;
    reg        gmii_rx_dv;
    reg        gmii_rx_er;

    wire [7:0] data_out;
    wire       valid_out;
    wire       last_out;
    wire       rx_err_out;
    wire       frame_done_out;

    rx_gmii_mii dut (
        .rx_clk        (rx_clk),
        .rst_n         (rst_n),
        .speed_select  (speed_select),
        .gmii_rxd      (gmii_rxd),
        .gmii_rx_dv    (gmii_rx_dv),
        .gmii_rx_er    (gmii_rx_er),
        .data_out      (data_out),
        .valid_out     (valid_out),
        .last_out      (last_out),
        .rx_err_out    (rx_err_out),
        .frame_done_out(frame_done_out)
    );

    initial rx_clk = 1'b0;
    always #(CLKP / 2.0) rx_clk = ~rx_clk;

    integer pass_n, fail_n;
    integer cyc;
    reg     trace_en;

    integer n_oct, n_frm, n_err, n_done;
    reg [7:0] cap  [0:255];
    reg       capl [0:255];

    reg     in_frm;
    integer gaps;

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
            $display("  %4d |  %b   %02h   %b  |  %02h    %b     %b     %b     %b",
                     cyc, gmii_rx_dv, gmii_rxd, gmii_rx_er,
                     data_out, valid_out, last_out, rx_err_out, frame_done_out);

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
            if (frame_done_out) n_done = n_done + 1;

            if (valid_out && last_out)      in_frm = 1'b0;
            else if (valid_out)             in_frm = 1'b1;
            else if (in_frm)                gaps   = gaps + 1;
        end else begin
            in_frm = 1'b0;
        end
    end

    task clear_mon;
        begin
            #0.1;
            n_oct  = 0;
            n_frm  = 0;
            n_err  = 0;
            n_done = 0;
            gaps   = 0;
            in_frm = 1'b0;
        end
    endtask

    task banner;
        begin
            $display("   cyc | DV  RXD  ER |  DOUT  VLD   LST   ERR  DONE");
            $display("  ------------------------------------------------------");
        end
    endtask

    task do_reset;
        begin
            rst_n        = 1'b0;
            gmii_rxd     = 8'h00;
            gmii_rx_dv   = 1'b0;
            gmii_rx_er   = 1'b0;
            repeat (3) @(negedge rx_clk);
            rst_n        = 1'b1;
            @(negedge rx_clk);
        end
    endtask

    task gmii_beat;
        input [7:0] d;
        input       er;
        begin
            @(negedge rx_clk);
            gmii_rxd   <= d;
            gmii_rx_dv <= 1'b1;
            gmii_rx_er <= er;
        end
    endtask

    task carrier_off;
        begin
            @(negedge rx_clk);
            gmii_rxd   <= 8'h00;
            gmii_rx_dv <= 1'b0;
            gmii_rx_er <= 1'b0;
        end
    endtask

    task mii_octet;
        input [7:0] d;
        input       er;
        begin
            @(negedge rx_clk);
            gmii_rxd   <= {4'h0, d[3:0]};
            gmii_rx_dv <= 1'b1;
            gmii_rx_er <= er;
            @(negedge rx_clk);
            gmii_rxd   <= {4'h0, d[7:4]};
            gmii_rx_dv <= 1'b1;
            gmii_rx_er <= 1'b0;
        end
    endtask

    task idle_for;
        input integer n;
        begin
            repeat (n) @(negedge rx_clk);
        end
    endtask

    integer i;
    integer bad;

    initial begin
        $dumpfile("rx_gmii_mii_tb.vcd");
        $dumpvars(0, rx_gmii_mii_tb);

        pass_n   = 0;
        fail_n   = 0;
        cyc      = 0;
        trace_en = 1'b0;
        n_oct    = 0;
        n_frm    = 0;
        n_err    = 0;
        n_done   = 0;
        bad      = 0;
        gaps     = 0;
        in_frm   = 1'b0;
        speed_select = 1'b1;

        $display("======================================================================");
        $display(" rx_gmii_mii_tb  -  the pin-level receiver");
        $display("   rx_clk %0.1f ns (%0.0f MHz), sourced by the PHY", CLKP, 1000.0 / CLKP);
        $display("======================================================================");

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" SUITE 1 : SIMPLE.  GMII, 4 octets DE AD BE EF, every cycle shown.");
        $display("----------------------------------------------------------------------");
        do_reset;
        clear_mon;
        trace_en = 1'b1;
        banner;

        gmii_beat(8'hDE, 1'b0);
        gmii_beat(8'hAD, 1'b0);
        gmii_beat(8'hBE, 1'b0);
        gmii_beat(8'hEF, 1'b0);
        carrier_off;
        idle_for(4);
        trace_en = 1'b0;

        $display("");
        $display("  Read the trace: RX_DV rises with DE already on the pins.");
        $display("  DOUT trails the pins by TWO cycles - one for the output");
        $display("  register, one for the hold-back register that makes");
        $display("  last_out possible (DESIGN NOTE #2).");
        $display("");
        $display("  Nothing on the pins ever said EF was the last octet. The");
        $display("  carrier simply stopped, and RX_DV falling is the ONLY");
        $display("  end-of-frame marker GMII gives us. That is the whole reason");
        $display("  the hold-back register exists: an octet cannot be published");
        $display("  until we know whether another one follows it.");
        $display("");
        $display("  Now check VLD in the trace: it is high on FOUR CONSECUTIVE");
        $display("  cycles, no gaps. That matters more than it looks. The first");
        $display("  version of this module let RX_DV falling jump straight to");
        $display("  ST_END, which left a dead cycle between the 3rd and 4th");
        $display("  octet - and it still passed every payload and count check.");
        $display("  rx_fcs computes CRC over CONSECUTIVE valid cycles, so that");
        $display("  bubble would have corrupted every frame. See DESIGN NOTE #5.");
        $display("");

        check("4 octets received",                     n_oct  === 4);
        check("exactly 1 frame delimited",             n_frm  === 1);
        check("frame_done_out pulsed once",            n_done === 1);
        check("no error reported on a clean frame",    n_err  === 0);
        check("NO BUBBLES - valid_out contiguous for the whole frame",
              gaps === 0);
        bad = 0;
        if (cap[0] !== 8'hDE) bad = bad + 1;
        if (cap[1] !== 8'hAD) bad = bad + 1;
        if (cap[2] !== 8'hBE) bad = bad + 1;
        if (cap[3] !== 8'hEF) bad = bad + 1;
        check("data is bit-exact and IN ORDER: DE AD BE EF", bad === 0);
        check("last_out marked ONLY the 4th octet",
              (capl[0] === 1'b0) && (capl[1] === 1'b0) &&
              (capl[2] === 1'b0) && (capl[3] === 1'b1));

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" SUITE 2 : BASIC.  Functional checks on every port.");
        $display("----------------------------------------------------------------------");

        do_reset;
        check("2.1 valid_out LOW after reset",       valid_out      === 1'b0);
        check("2.1 last_out LOW after reset",        last_out       === 1'b0);
        check("2.1 rx_err_out LOW after reset",      rx_err_out     === 1'b0);
        check("2.1 frame_done_out LOW after reset",  frame_done_out === 1'b0);

        clear_mon;
        gmii_beat(8'h7E, 1'b0);
        carrier_off;
        idle_for(4);
        check("2.2 a 1-octet frame yields exactly 1 octet", n_oct === 1);
        check("2.2 that octet is 0x7E",                     cap[0] === 8'h7E);
        check("2.2 and it carries last_out",                capl[0] === 1'b1);
        check("2.2 one frame_done_out",                     n_done === 1);
        $display("        A 1-octet frame is the corner case for the hold-back");
        $display("        register: the octet is held, never republished, and");
        $display("        flushed by ST_END as both first AND last.");

        clear_mon;
        gmii_beat(8'h11, 1'b0);
        gmii_beat(8'h22, 1'b1);
        gmii_beat(8'h33, 1'b0);
        gmii_beat(8'h44, 1'b0);
        carrier_off;
        idle_for(4);
        check("2.3 all 4 octets still delivered",    n_oct === 4);
        check("2.3 rx_err_out asserted exactly ONCE", n_err === 1);
        check("2.3 ...on the last_out octet",
              (capl[3] === 1'b1) && (n_frm === 1));
        check("2.3 no bubbles even on a damaged frame", gaps === 0);
        $display("        RX_ER was high for ONE octet in the middle. The error");
        $display("        is latched and reported once, at the end, so nothing");
        $display("        downstream needs a per-octet error bit (NOTE #3).");

        clear_mon;
        gmii_beat(8'hAA, 1'b1);
        gmii_beat(8'hBB, 1'b0);
        carrier_off;
        idle_for(4);
        check("2.4 error on octet 0 is still caught", n_err === 1);
        check("2.4 both octets delivered",            n_oct === 2);

        clear_mon;
        gmii_beat(8'h01, 1'b0);
        gmii_beat(8'h02, 1'b0);
        carrier_off;
        idle_for(3);
        gmii_beat(8'h03, 1'b0);
        gmii_beat(8'h04, 1'b0);
        carrier_off;
        idle_for(4);
        check("2.5 two frames, 4 octets total",      n_oct  === 4);
        check("2.5 two frame delimiters",            n_frm  === 2);
        check("2.5 two frame_done_out pulses",       n_done === 2);
        check("2.5 no error leaked between frames",  n_err  === 0);
        check("2.5 boundaries in the right place",
              (capl[0] === 1'b0) && (capl[1] === 1'b1) &&
              (capl[2] === 1'b0) && (capl[3] === 1'b1));
        $display("        err_sticky is cleared in ST_IDLE and again in ST_END,");
        $display("        so a damaged frame cannot poison the next one.");

        $display("");
        $display("  -- switching to MII (speed_select=0). Strap changes only");
        $display("     while the receiver is idle, per the strap contract. --");
        @(negedge rx_clk) speed_select = 1'b0;
        clear_mon;
        trace_en = 1'b1;
        banner;
        mii_octet(8'h55, 1'b0);
        mii_octet(8'hD5, 1'b0);
        mii_octet(8'h3C, 1'b0);
        carrier_off;
        idle_for(4);
        trace_en = 1'b0;
        $display("");
        check("2.6 MII: 3 octets from 6 nibbles",   n_oct === 3);
        check("2.6 MII: 0x55 reassembled",          cap[0] === 8'h55);
        check("2.6 MII: 0xD5 reassembled",          cap[1] === 8'hD5);
        check("2.6 MII: 0x3C reassembled",          cap[2] === 8'h3C);
        check("2.6 MII: last on the 3rd octet",     capl[2] === 1'b1);
        check("2.6 MII: one frame",                 n_frm === 1);
        $display("        MII deliberately DOES have gaps: an octet takes two");
        $display("        nibble cycles, so valid_out is high every other cycle.");
        $display("        That is why the contiguity check is GMII-only - in MII");
        $display("        the gap is the mode working, not a bubble.");
        $display("        LOW nibble first (clause 22.2.3). Note 0x3C arrives as");
        $display("        C then 3 - if the order were swapped this would come");
        $display("        out 0xC3 and the CRC downstream would fail every time.");

        clear_mon;
        @(negedge rx_clk);
        gmii_rxd   <= 8'h0A;
        gmii_rx_dv <= 1'b1;
        gmii_rx_er <= 1'b0;
        @(negedge rx_clk);
        gmii_rxd   <= 8'h0B;
        gmii_rx_dv <= 1'b1;
        @(negedge rx_clk);
        gmii_rxd   <= 8'h0C;
        gmii_rx_dv <= 1'b1;
        carrier_off;
        idle_for(4);
        check("2.7 MII odd nibble count flags an error", n_err === 1);
        check("2.7 the complete octet still came out",   n_oct === 1);
        check("2.7 it is 0xBA (low A, high B)",          cap[0] === 8'hBA);
        $display("        Three nibbles cannot make two octets. The dangling");
        $display("        nibble is discarded and the frame marked bad, so the");
        $display("        truncation cannot masquerade as a valid short frame.");

        @(negedge rx_clk) speed_select = 1'b1;

        clear_mon;
        gmii_beat(8'h99, 1'b0);
        carrier_off;
        idle_for(4);
        check("2.8 a 1-cycle carrier still yields its octet", n_oct === 1);
        check("2.8 with last_out set",                        capl[0] === 1'b1);

        clear_mon;
        gmii_beat(8'h5A, 1'b0);
        gmii_beat(8'h5B, 1'b0);
        @(negedge rx_clk) rst_n = 1'b0;
        @(negedge rx_clk);
        gmii_rx_dv = 1'b0;
        gmii_rxd   = 8'h00;
        @(negedge rx_clk) rst_n = 1'b1;
        idle_for(4);
        check("2.9 reset mid-frame parks valid_out",   valid_out === 1'b0);
        check("2.9 no frame delimiter was emitted",    n_frm === 0);
        $display("        A frame interrupted by reset is abandoned silently.");
        $display("        No last_out means nothing downstream ever commits it.");

        do_reset;
        clear_mon;
        for (i = 0; i < 64; i = i + 1)
            gmii_beat(i[7:0], 1'b0);
        carrier_off;
        idle_for(4);
        check("2.10 all 64 octets received",  n_oct === 64);
        bad = 0;
        for (i = 0; i < 64; i = i + 1)
            if (cap[i] !== i[7:0]) bad = bad + 1;
        check("2.10 ordering held over 64 octets, zero mismatches", bad === 0);
        check("2.10 exactly one last_out in 64 octets",             n_frm === 1);
        check("2.10 and it is on octet 63",                         capl[63] === 1'b1);
        check("2.10 all 64 octets contiguous, not one bubble",      gaps === 0);
        $display("        64 gapless cycles. This is the shape rx_fcs needs:");
        $display("        one octet per cycle, no holes, last_out on the end.");

        $display("");
        $display("======================================================================");
        $display(" RESULT : %0d passed, %0d failed, %0d total",
                 pass_n, fail_n, pass_n + fail_n);
        if (fail_n == 0)
            $display(" rx_gmii_mii_tb : ALL CHECKS PASS");
        else
            $display(" rx_gmii_mii_tb : *** FAILURES ***");
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

