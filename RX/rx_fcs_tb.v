// rx_fcs_tb - RX FCS tests.

`timescale 1ns / 1ps
`default_nettype none

module rx_fcs_tb;

    localparam real CLKP = 8.0;

    reg         rx_clk;
    reg         rst_n;
    reg  [7:0]  data_in;
    reg         valid_in;
    reg         last_in;
    reg         rx_err_in;

    wire [7:0]  data_out;
    wire        valid_out;
    wire        last_out;
    wire        crc_ok_out;
    wire        crc_err_out;
    wire        len_err_out;
    wire        phy_err_out;
    wire [10:0] frame_len_out;

    rx_fcs #(.MIN_FRAME_LEN(3), .MAX_FRAME_LEN(1514)) dut (
        .rx_clk       (rx_clk),
        .rst_n        (rst_n),
        .data_in      (data_in),
        .valid_in     (valid_in),
        .last_in      (last_in),
        .rx_err_in    (rx_err_in),
        .data_out     (data_out),
        .valid_out    (valid_out),
        .last_out     (last_out),
        .crc_ok_out   (crc_ok_out),
        .crc_err_out  (crc_err_out),
        .len_err_out  (len_err_out),
        .phy_err_out  (phy_err_out),
        .frame_len_out(frame_len_out)
    );

    initial rx_clk = 1'b0;
    always #(CLKP / 2.0) rx_clk = ~rx_clk;

    reg  [31:0] ref_crc;
    reg  [7:0]  ref_d;
    wire [31:0] ref_next;
    crc32_parallel u_ref (.data_in(ref_d), .crc_in(ref_crc), .crc_out(ref_next));

    integer pass_n, fail_n, cyc;
    reg     trace_en;

    integer n_oct, n_ok, n_err, n_len, n_phy, n_last, gaps;
    reg     in_frm;
    reg [7:0] cap [0:2047];

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
            $display("  %4d |  %02h   %b   %b  |  %02h   %b   %b  |  %b    %b    %b   | %08h",
                     cyc, data_in, valid_in, last_in,
                     data_out, valid_out, last_out,
                     crc_ok_out, crc_err_out, len_err_out, dut.crc_reg);

        if (rst_n) begin
            if (valid_out) begin
                if (n_oct < 2048) cap[n_oct] = data_out;
                n_oct = n_oct + 1;
            end
            if (last_out)    n_last = n_last + 1;
            if (crc_ok_out)  n_ok   = n_ok   + 1;
            if (crc_err_out) n_err  = n_err  + 1;
            if (len_err_out) n_len  = n_len  + 1;
            if (phy_err_out) n_phy  = n_phy  + 1;

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
            n_oct = 0; n_ok = 0; n_err = 0; n_len = 0;
            n_phy = 0; n_last = 0; gaps = 0; in_frm = 1'b0;
        end
    endtask

    task banner;
        begin
            $display("   cyc | DIN VLD LST | DOUT VLD LST | OK  ERR  LEN | crc_reg");
            $display("  ----------------------------------------------------------------");
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

    reg [7:0]  frm [0:2047];
    integer    flen;
    reg [31:0] fcs;

    task compute_fcs;
        integer k;
        begin
            ref_crc = 32'hFFFF_FFFF;
            for (k = 0; k < flen; k = k + 1) begin
                ref_d = frm[k];
                #1;
                ref_crc = ref_next;
                #1;
            end
            fcs = ~ref_crc;
        end
    endtask

    task send_frame;
        input       corrupt;
        input [7:0] er_mask;
        integer k;
        reg [7:0] b;
        begin
            for (k = 0; k < flen; k = k + 1) begin
                b = frm[k];
                if (corrupt && (k == 1)) b = b ^ 8'h01;
                beat(b, 1'b0, 1'b0);
            end
            beat(fcs[7:0],   1'b0, 1'b0);
            beat(fcs[15:8],  1'b0, 1'b0);
            beat(fcs[23:16], 1'b0, 1'b0);
            beat(fcs[31:24], 1'b1, er_mask[0]);
            quiet;
        end
    endtask

    integer i, bad;

    initial begin
        $dumpfile("rx_fcs_tb.vcd");
        $dumpvars(0, rx_fcs_tb);

        pass_n = 0; fail_n = 0; cyc = 0; trace_en = 1'b0;
        n_oct = 0; n_ok = 0; n_err = 0; n_len = 0;
        n_phy = 0; n_last = 0; gaps = 0; in_frm = 1'b0; bad = 0;
        ref_crc = 32'hFFFF_FFFF; ref_d = 8'h00;

        $display("======================================================================");
        $display(" rx_fcs_tb  -  CRC-32 verify by RESIDUE, and FCS strip");
        $display("======================================================================");

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" SUITE 0 : proving the residue constant 0xDEBB20E3");
        $display("----------------------------------------------------------------------");

        ref_crc = 32'hFFFF_FFFF;
        ref_d = "1"; #1; ref_crc = ref_next; #1;
        ref_d = "2"; #1; ref_crc = ref_next; #1;
        ref_d = "3"; #1; ref_crc = ref_next; #1;
        ref_d = "4"; #1; ref_crc = ref_next; #1;
        ref_d = "5"; #1; ref_crc = ref_next; #1;
        ref_d = "6"; #1; ref_crc = ref_next; #1;
        ref_d = "7"; #1; ref_crc = ref_next; #1;
        ref_d = "8"; #1; ref_crc = ref_next; #1;
        ref_d = "9"; #1; ref_crc = ref_next; #1;
        $display("  CRC-32('123456789') = %08h   (universal KAT: CBF43926)", ~ref_crc);
        check("the CRC engine is a standard CRC-32", (~ref_crc) === 32'hCBF43926);

        frm[0] = "a"; frm[1] = "b"; frm[2] = "c"; flen = 3;
        compute_fcs;
        $display("");
        $display("  payload 'abc'  FCS=%08h  wire order: %02h %02h %02h %02h",
                 fcs, fcs[7:0], fcs[15:8], fcs[23:16], fcs[31:24]);

        ref_crc = 32'hFFFF_FFFF;
        ref_d = "a"; #1; ref_crc = ref_next; #1;
        ref_d = "b"; #1; ref_crc = ref_next; #1;
        ref_d = "c"; #1; ref_crc = ref_next; #1;
        ref_d = fcs[7:0];   #1; ref_crc = ref_next; #1;
        ref_d = fcs[15:8];  #1; ref_crc = ref_next; #1;
        ref_d = fcs[23:16]; #1; ref_crc = ref_next; #1;
        ref_d = fcs[31:24]; #1; ref_crc = ref_next; #1;
        $display("  payload+FCS through the same engine -> crc_reg = %08h", ref_crc);
        check("residue for a 3-octet payload is DEBB20E3", ref_crc === 32'hDEBB20E3);

        frm[0] = 8'hDE; flen = 1;
        compute_fcs;
        ref_crc = 32'hFFFF_FFFF;
        ref_d = 8'hDE;      #1; ref_crc = ref_next; #1;
        ref_d = fcs[7:0];   #1; ref_crc = ref_next; #1;
        ref_d = fcs[15:8];  #1; ref_crc = ref_next; #1;
        ref_d = fcs[23:16]; #1; ref_crc = ref_next; #1;
        ref_d = fcs[31:24]; #1; ref_crc = ref_next; #1;
        $display("  a 1-octet payload (different FCS) -> crc_reg = %08h", ref_crc);
        check("residue for a 1-octet payload is DEBB20E3", ref_crc === 32'hDEBB20E3);
        $display("");
        $display("  The residue does NOT depend on the payload. That is why the");
        $display("  receiver needs no comparator and no byte-order logic: feed");
        $display("  payload AND FCS through one engine, test one constant.");

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" SUITE 1 : SIMPLE.  'abc' + its real FCS.  Every cycle shown.");
        $display("----------------------------------------------------------------------");
        do_reset;
        clear_mon;
        frm[0] = "a"; frm[1] = "b"; frm[2] = "c"; flen = 3;
        compute_fcs;
        $display("  sending: 61 62 63 %02h %02h %02h %02h   (7 octets in)",
                 fcs[7:0], fcs[15:8], fcs[23:16], fcs[31:24]);
        $display("");
        trace_en = 1'b1;
        banner;
        send_frame(1'b0, 8'h00);
        idle_for(4);
        trace_en = 1'b0;

        $display("");
        $display("  SEVEN octets went in, THREE came out. The 4-deep delay line");
        $display("  never published the FCS: when last_in arrived, those 4 octets");
        $display("  were still inside it, and they were simply dropped.");
        $display("");
        $display("  Watch crc_reg in the last column. It churns through every");
        $display("  octet - payload AND FCS - and lands on DEBB20E3. One equality");
        $display("  test against that constant is the entire CRC check.");
        $display("");
        $display("  OK fires one cycle AFTER the last DOUT. It has to: the final");
        $display("  FCS octet only enters the CRC on the edge last_in arrives, so");
        $display("  the residue is not settled until the next cycle. This is why");
        $display("  rx_fifo must be store-and-forward - it has to hold the whole");
        $display("  frame and wait for a verdict that arrives late (NOTE #1).");
        $display("");

        check("exactly 3 octets published (FCS stripped)", n_oct === 3);
        check("the payload is 'abc'",
              (cap[0] === "a") && (cap[1] === "b") && (cap[2] === "c"));
        check("crc_ok_out fired exactly once",   n_ok  === 1);
        check("crc_err_out never fired",         n_err === 0);
        check("len_err_out never fired",         n_len === 0);
        check("frame_len_out reports 3",         frame_len_out === 11'd3);
        check("output was contiguous",           gaps === 0);

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" SUITE 2 : BASIC.  Every port and every failure mode.");
        $display("----------------------------------------------------------------------");

        do_reset;
        check("2.1 valid_out LOW after reset",   valid_out   === 1'b0);
        check("2.1 crc_ok_out LOW after reset",  crc_ok_out  === 1'b0);
        check("2.1 crc_err_out LOW after reset", crc_err_out === 1'b0);

        clear_mon;
        frm[0]=8'hFF; frm[1]=8'hFF; frm[2]=8'hFF;
        frm[3]=8'hFF; frm[4]=8'hFF; frm[5]=8'hFF;
        frm[6]=8'h00; frm[7]=8'h11; frm[8]=8'h22;
        frm[9]=8'h33; frm[10]=8'h44; frm[11]=8'h55;
        frm[12]=8'h08; frm[13]=8'h00;
        for (i = 14; i < 60; i = i + 1) frm[i] = i[7:0];
        flen = 60;
        compute_fcs;
        send_frame(1'b0, 8'h00);
        idle_for(4);
        check("2.2 a 60-octet frame passes CRC",  n_ok === 1);
        check("2.2 60 octets published",          n_oct === 60);
        check("2.2 frame_len_out reports 60",     frame_len_out === 11'd60);
        bad = 0;
        for (i = 0; i < 60; i = i + 1)
            if (cap[i] !== frm[i]) bad = bad + 1;
        check("2.2 payload is bit-exact",         bad === 0);
        check("2.2 no gaps over 60 octets",       gaps === 0);

        clear_mon;
        send_frame(1'b1, 8'h00);
        idle_for(4);
        check("2.3 a single flipped bit is DETECTED", n_err === 1);
        check("2.3 crc_ok_out did NOT fire",          n_ok  === 0);
        check("2.3 len_err stayed low (length was fine)", n_len === 0);
        $display("        One bit flipped in a 64-octet frame. CRC-32 catches");
        $display("        every 1, 2 and 3-bit error and every burst up to 32");
        $display("        bits. This is the check that makes Ethernet reliable.");

        clear_mon;
        frm[0] = "a"; frm[1] = "b"; frm[2] = "c"; flen = 3;
        compute_fcs;
        beat("a", 1'b0, 1'b0);
        beat("b", 1'b0, 1'b0);
        beat("c", 1'b0, 1'b0);
        beat(fcs[7:0] ^ 8'h80, 1'b0, 1'b0);
        beat(fcs[15:8],  1'b0, 1'b0);
        beat(fcs[23:16], 1'b0, 1'b0);
        beat(fcs[31:24], 1'b1, 1'b0);
        quiet;
        idle_for(4);
        check("2.4 a damaged FCS is detected", n_err === 1);
        check("2.4 crc_ok_out did NOT fire",   n_ok  === 0);
        $display("        A bad FCS is indistinguishable from bad payload - both");
        $display("        just break the residue. That is correct: either way the");
        $display("        frame cannot be trusted.");

        clear_mon;
        beat("a", 1'b0, 1'b0);
        beat("b", 1'b0, 1'b0);
        beat("c", 1'b0, 1'b0);
        beat(fcs[31:24], 1'b0, 1'b0);
        beat(fcs[23:16], 1'b0, 1'b0);
        beat(fcs[15:8],  1'b0, 1'b0);
        beat(fcs[7:0],   1'b1, 1'b0);
        quiet;
        idle_for(4);
        check("2.5 FCS in the WRONG byte order is rejected", n_err === 1);
        $display("        This is the single most valuable check in this bench.");
        $display("        It proves the receiver only accepts LOW-OCTET-FIRST,");
        $display("        which is what tx_mac_controller's ST_FCS emits. If TX");
        $display("        and RX disagreed here, every frame would fail and the");
        $display("        cause would be very hard to find. 2.2 passing and 2.5");
        $display("        failing together pin the byte order down exactly.");

        clear_mon;
        frm[0] = 8'h01; frm[1] = 8'h02; flen = 2;
        compute_fcs;
        send_frame(1'b0, 8'h00);
        idle_for(4);
        check("2.6 a runt raises len_err_out",   n_len === 1);
        check("2.6 a runt raises crc_err_out",   n_err === 1);
        check("2.6 a runt NEVER raises crc_ok",  n_ok  === 0);
        $display("        Its CRC was actually VALID - the bench computed it");
        $display("        correctly. It is rejected purely on length. A collision");
        $display("        fragment can carry a good CRC by chance, so clause");
        $display("        4.4.2's minFrameSize is a separate, independent gate.");

        clear_mon;
        beat(8'hAA, 1'b0, 1'b0);
        beat(8'hBB, 1'b1, 1'b0);
        quiet;
        idle_for(4);
        check("2.7 a 2-octet carrier publishes nothing", n_oct === 0);
        check("2.7 and is reported as an error",         n_err === 1);
        check("2.7 len_err_out flags it",                n_len === 1);
        $display("        Fewer than 4 octets cannot even fill the delay line.");
        $display("        Nothing is published, so no half-frame can escape.");

        clear_mon;
        frm[0] = "a"; frm[1] = "b"; frm[2] = "c"; flen = 3;
        compute_fcs;
        send_frame(1'b0, 8'h01);
        idle_for(4);
        check("2.8 a PHY error kills an otherwise PERFECT frame", n_err === 1);
        check("2.8 crc_ok_out did NOT fire",                      n_ok  === 0);
        check("2.8 phy_err_out identifies the cause",             n_phy === 1);
        check("2.8 len_err_out stayed low",                       n_len === 0);
        $display("        The CRC was valid and the length was fine. The PHY said");
        $display("        it decoded garbage, so the frame dies anyway. Note");
        $display("        phy_err_out is separate from crc_err_out: downstream");
        $display("        only tests crc_ok_out, but a human debugging the link");
        $display("        needs to know whether it was the cable or a bit flip.");

        clear_mon;
        frm[0] = 8'h11; frm[1] = 8'h22; frm[2] = 8'h33; flen = 3;
        compute_fcs;
        send_frame(1'b0, 8'h00);
        idle_for(3);
        frm[0] = 8'h44; frm[1] = 8'h55; frm[2] = 8'h66; flen = 3;
        compute_fcs;
        send_frame(1'b0, 8'h00);
        idle_for(4);
        check("2.9 two frames both pass",     n_ok  === 2);
        check("2.9 6 octets published",       n_oct === 6);
        check("2.9 no errors",                n_err === 0);
        check("2.9 payloads in order",
              (cap[0] === 8'h11) && (cap[2] === 8'h33) &&
              (cap[3] === 8'h44) && (cap[5] === 8'h66));
        $display("        crc_reg is re-seeded to FFFFFFFF in ST_DONE, so a bad");
        $display("        frame cannot poison the next one. 2.10 proves that.");

        clear_mon;
        frm[0] = 8'h77; frm[1] = 8'h88; frm[2] = 8'h99; flen = 3;
        compute_fcs;
        send_frame(1'b1, 8'h00);
        idle_for(3);
        frm[0] = 8'hA1; frm[1] = 8'hA2; frm[2] = 8'hA3; flen = 3;
        compute_fcs;
        send_frame(1'b0, 8'h00);
        idle_for(4);
        check("2.10 the bad frame errored",             n_err === 1);
        check("2.10 the following good frame PASSED",   n_ok  === 1);
        $display("        This is the check that proves no state leaks. A");
        $display("        receiver that stayed broken after one bad frame would");
        $display("        be far worse than one that never worked at all.");

        clear_mon;
        beat(8'h01, 1'b0, 1'b0);
        beat(8'h02, 1'b0, 1'b0);
        beat(8'h03, 1'b0, 1'b0);
        beat(8'h04, 1'b1, 1'b0);
        quiet;
        idle_for(4);
        check("2.11 a 4-octet frame publishes nothing", n_oct === 0);
        check("2.11 and is rejected",                   n_ok  === 0);
        $display("        4 octets is an FCS with a zero-length body. The delay");
        $display("        line fills exactly and never shifts anything out.");

        $display("");
        $display("======================================================================");
        $display(" RESULT : %0d passed, %0d failed, %0d total",
                 pass_n, fail_n, pass_n + fail_n);
        if (fail_n == 0)
            $display(" rx_fcs_tb : ALL CHECKS PASS");
        else
            $display(" rx_fcs_tb : *** FAILURES ***");
        $display("======================================================================");
        $finish;
    end

    initial begin
        #400000;
        $display("");
        $display(" *** TIMEOUT - the bench hung ***");
        $finish;
    end

endmodule

`default_nettype wire

