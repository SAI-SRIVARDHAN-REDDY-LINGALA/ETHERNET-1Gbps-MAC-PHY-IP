// rx_fifo_tb - RX FIFO tests.

`timescale 1ns / 1ps
`default_nettype none

module rx_fifo_tb;

    localparam integer DATA_W = 8;
    localparam integer ADDR_W = 4;
    localparam integer DEPTH  = (1 << ADDR_W);

    localparam real WRP = 8.0;
    localparam real RDP = 14.0;

    reg              wr_clk, wr_rst_n;
    reg  [7:0]       data_in;
    reg              valid_in, last_in;
    reg              crc_ok_in, crc_err_in;
    wire             frame_cmt_out, frame_drop_out, overflow_out;

    reg              rd_clk, rd_rst_n;
    wire [7:0]       m_axis_tdata;
    wire             m_axis_tvalid;
    reg              m_axis_tready;
    wire             m_axis_tlast;
    wire             frame_avail_out;

    rx_fifo #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) dut (
        .wr_clk         (wr_clk),
        .wr_rst_n       (wr_rst_n),
        .data_in        (data_in),
        .valid_in       (valid_in),
        .last_in        (last_in),
        .crc_ok_in      (crc_ok_in),
        .crc_err_in     (crc_err_in),
        .frame_cmt_out  (frame_cmt_out),
        .frame_drop_out (frame_drop_out),
        .overflow_out   (overflow_out),
        .rd_clk         (rd_clk),
        .rd_rst_n       (rd_rst_n),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast),
        .frame_avail_out(frame_avail_out)
    );

    initial wr_clk = 1'b0;
    always #(WRP / 2.0) wr_clk = ~wr_clk;

    initial rd_clk = 1'b0;
    always #(RDP / 2.0) rd_clk = ~rd_clk;

    integer pass_n, fail_n, wcyc, rcyc;
    reg     trace_en;

    integer n_oct, n_frm, n_drop, n_ovf, n_cmt;
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

    always @(posedge wr_clk) begin
        wcyc = wcyc + 1;
        if (trace_en)
            $display("  W%3d |  %02h   %b   %b  |  %b   %b  |  %b   %b  | %2d %2d",
                     wcyc, data_in, valid_in, last_in,
                     crc_ok_in, crc_err_in,
                     frame_drop_out, overflow_out,
                     dut.wr_bin, dut.wr_cmt_bin);

        if (wr_rst_n) begin
            if (frame_drop_out) n_drop = n_drop + 1;
            if (overflow_out)   n_ovf  = n_ovf  + 1;
            if (frame_cmt_out)  n_cmt  = n_cmt  + 1;
        end
    end

    always @(posedge rd_clk) begin
        rcyc = rcyc + 1;
        if (trace_en)
            $display("       R%3d |  %02h   %b   %b   %b  | avail %b",
                     rcyc, m_axis_tdata, m_axis_tvalid, m_axis_tready,
                     m_axis_tlast, frame_avail_out);

        if (rd_rst_n && m_axis_tvalid && m_axis_tready) begin
            if (n_oct < 256) begin
                cap [n_oct] = m_axis_tdata;
                capl[n_oct] = m_axis_tlast;
            end
            n_oct = n_oct + 1;
            if (m_axis_tlast) n_frm = n_frm + 1;
        end
    end

    task clear_mon;
        begin
            #0.1;
            n_oct = 0; n_frm = 0; n_drop = 0; n_ovf = 0; n_cmt = 0;
        end
    endtask

    task banner;
        begin
            $display("   Wcyc |  DIN VLD LST |  OK ERR | DRP OVF | wr cmt");
            $display("        Rcyc | TDATA VLD RDY LST | avail");
            $display("  ----------------------------------------------------------");
        end
    endtask

    task do_reset;
        begin
            wr_rst_n      = 1'b0;
            rd_rst_n      = 1'b0;
            data_in       = 8'h00;
            valid_in      = 1'b0;
            last_in       = 1'b0;
            crc_ok_in     = 1'b0;
            crc_err_in    = 1'b0;
            m_axis_tready = 1'b0;
            repeat (4) @(negedge wr_clk);
            repeat (3) @(negedge rd_clk);
            wr_rst_n      = 1'b1;
            rd_rst_n      = 1'b1;
            repeat (4) @(negedge rd_clk);
        end
    endtask

    task wbeat;
        input [7:0] d;
        input       lst;
        begin
            @(negedge wr_clk);
            data_in    <= d;
            valid_in   <= 1'b1;
            last_in    <= lst;
            crc_ok_in  <= 1'b0;
            crc_err_in <= 1'b0;
        end
    endtask

    task verdict;
        input ok;
        begin
            @(negedge wr_clk);
            data_in    <= 8'h00;
            valid_in   <= 1'b0;
            last_in    <= 1'b0;
            crc_ok_in  <= ok;
            crc_err_in <= ~ok;
            @(negedge wr_clk);
            crc_ok_in  <= 1'b0;
            crc_err_in <= 1'b0;
        end
    endtask

    task wquiet;
        begin
            @(negedge wr_clk);
            data_in    <= 8'h00;
            valid_in   <= 1'b0;
            last_in    <= 1'b0;
            crc_ok_in  <= 1'b0;
            crc_err_in <= 1'b0;
        end
    endtask

    task widle;
        input integer n;
        begin
            repeat (n) @(negedge wr_clk);
        end
    endtask

    task ridle;
        input integer n;
        begin
            repeat (n) @(negedge rd_clk);
        end
    endtask

    task push_frame;
        input integer n;
        input [7:0]   base;
        input         ok;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                wbeat(base + k[7:0], (k == n - 1));
            verdict(ok);
        end
    endtask

    integer i, bad;

    initial begin
        $dumpfile("rx_fifo_tb.vcd");
        $dumpvars(0, rx_fifo_tb);

        pass_n = 0; fail_n = 0; wcyc = 0; rcyc = 0; trace_en = 1'b0;
        n_oct = 0; n_frm = 0; n_drop = 0; n_ovf = 0; n_cmt = 0; bad = 0;

        $display("======================================================================");
        $display(" rx_fifo_tb  -  store-and-forward, commit on crc_ok, erase on crc_err");
        $display("======================================================================");

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" SUITE 1 : SIMPLE.  One GOOD frame 'abc', then one BAD frame 'xyz'.");
        $display("----------------------------------------------------------------------");
        do_reset;
        clear_mon;
        m_axis_tready = 1'b1;
        trace_en = 1'b1;
        banner;

        wbeat("a", 1'b0);
        wbeat("b", 1'b0);
        wbeat("c", 1'b1);
        verdict(1'b1);
        widle(10);

        $display("");
        $display("  --- now a frame that FAILS its CRC ---");
        $display("");

        wbeat("x", 1'b0);
        wbeat("y", 1'b0);
        wbeat("z", 1'b1);
        verdict(1'b0);
        widle(10);
        trace_en = 1'b0;
        ridle(6);

        $display("");
        $display("  SIX octets were written. THREE came out: 'abc'.");
        $display("");
        $display("  Read the wr/cmt columns in the trace. On the good frame,");
        $display("  wr_bin climbs 0,1,2,3 and then cmt JUMPS to 3 on the verdict");
        $display("  cycle - that is the COMMIT, and only then does the reader");
        $display("  learn a frame exists. On the bad frame wr_bin climbs 3,4,5,6");
        $display("  and then SNAPS BACK to 3 on the verdict. That is the REWIND.");
        $display("");
        $display("  'x','y','z' are still physically sitting in the RAM. No");
        $display("  pointer can reach them, so they do not exist as far as the");
        $display("  host is concerned, and the next frame overwrites them.");
        $display("");
        $display("  This is why the verdict arriving a cycle late (rx_fcs NOTE");
        $display("  #1) is harmless. A plain FIFO would have leaked 'xyz' to the");
        $display("  host before anyone knew it was corrupt - there is no undo.");
        $display("  Clause 4.2.4.1.2 says an invalid frame shall not be passed");
        $display("  to the client, and THIS is the module that enforces it.");
        $display("");

        check("exactly 3 octets delivered",  n_oct === 3);
        check("and they are 'abc'",
              (cap[0] === "a") && (cap[1] === "b") && (cap[2] === "c"));
        check("tlast on 'c' only",
              (capl[0] === 1'b0) && (capl[1] === 1'b0) && (capl[2] === 1'b1));
        check("one complete frame delivered", n_frm  === 1);
        check("the bad frame was reported",   n_drop === 1);
        check("it was not an overflow",       n_ovf  === 0);

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" SUITE 2 : BASIC.  Every port, both pointers, the overflow path.");
        $display("----------------------------------------------------------------------");

        do_reset;
        check("2.1 tvalid LOW after reset",          m_axis_tvalid   === 1'b0);
        check("2.1 frame_avail_out LOW after reset", frame_avail_out === 1'b0);
        check("2.1 frame_cmt_out  LOW after reset",  frame_cmt_out   === 1'b0);
        check("2.1 frame_drop_out LOW after reset",  frame_drop_out  === 1'b0);
        $display("        tdata/tlast are NOT checked here. mem_q is reset-free");
        $display("        for block-RAM inference, so they are legally x until");
        $display("        the first load. AXI says data is qualified by tvalid,");
        $display("        and tvalid is low. Same rule as tx_fifo.");

        clear_mon;
        m_axis_tready = 1'b1;
        wbeat(8'h11, 1'b0);
        wbeat(8'h22, 1'b0);
        wbeat(8'h33, 1'b1);
        wquiet;
        widle(6);
        ridle(4);
        check("2.2 a frame with NO verdict yet delivers nothing", n_oct === 0);
        check("2.2 frame_avail_out is still LOW",  frame_avail_out === 1'b0);
        $display("        The whole frame is in RAM. wr_frm has not moved, so");
        $display("        the reader has been told nothing. This is the window");
        $display("        awaiting_verdict covers.");

        verdict(1'b1);
        widle(4);
        ridle(8);
        check("2.2 the verdict releases it",            n_oct === 3);
        check("2.2 payload intact",
              (cap[0] === 8'h11) && (cap[1] === 8'h22) && (cap[2] === 8'h33));

        clear_mon;
        push_frame(4, 8'h40, 1'b0);
        widle(4);
        ridle(8);
        check("2.3 a CRC-failed frame delivers NOTHING", n_oct  === 0);
        check("2.3 frame_drop_out pulsed once",          n_drop === 1);
        check("2.3 frame_avail_out stayed LOW",  frame_avail_out === 1'b0);

        clear_mon;
        push_frame(3, 8'hB0, 1'b0);
        widle(3);
        push_frame(3, 8'hC0, 1'b1);
        widle(4);
        ridle(10);
        check("2.4 only the good frame is delivered", n_oct === 3);
        check("2.4 and it is the C0 frame, not B0",
              (cap[0] === 8'hC0) && (cap[1] === 8'hC1) && (cap[2] === 8'hC2));
        check("2.4 one drop reported",               n_drop === 1);
        $display("        The rewind put wr_bin back exactly where the good");
        $display("        frame then started writing. B0,B1,B2 were overwritten");
        $display("        by C0,C1,C2 - the erasure is not even lazy.");

        clear_mon;
        push_frame(2, 8'h10, 1'b1);
        widle(2);
        push_frame(2, 8'h20, 1'b1);
        widle(2);
        push_frame(2, 8'h30, 1'b1);
        widle(4);
        ridle(16);
        check("2.5 three frames, 6 octets", n_oct === 6);
        check("2.5 three tlast beats",      n_frm === 3);
        check("2.5 in order",
              (cap[0] === 8'h10) && (cap[2] === 8'h20) && (cap[4] === 8'h30));
        check("2.5 tlast on every 2nd octet",
              (capl[1] === 1'b1) && (capl[3] === 1'b1) && (capl[5] === 1'b1));

        clear_mon;
        push_frame(2, 8'hA0, 1'b1);
        widle(2);
        push_frame(2, 8'hB0, 1'b0);
        widle(2);
        push_frame(2, 8'hC0, 1'b1);
        widle(2);
        push_frame(2, 8'hD0, 1'b0);
        widle(2);
        push_frame(2, 8'hE0, 1'b1);
        widle(4);
        ridle(20);
        check("2.6 only the 3 good frames arrive", n_frm === 3);
        check("2.6 6 octets, not 10",              n_oct === 6);
        check("2.6 A0, C0, E0 in order",
              (cap[0] === 8'hA0) && (cap[2] === 8'hC0) && (cap[4] === 8'hE0));
        check("2.6 two drops reported",            n_drop === 2);
        check("2.6 three commits reported",        n_cmt  === 3);
        $display("        Five frames in, three out, and the surviving three are");
        $display("        contiguous with correct framing. No state leaks from a");
        $display("        rewound frame into the next one.");

        clear_mon;
        m_axis_tready = 1'b0;
        push_frame(4, 8'h50, 1'b1);
        widle(4);
        ridle(8);
        check("2.7 tvalid is asserted even with tready LOW", m_axis_tvalid === 1'b1);
        check("2.7 nothing handshaked yet",                  n_oct === 0);
        $display("        AXI rule: tvalid must not depend on tready. The FIFO");
        $display("        prefetched octet 0 and is offering it. This is also");
        $display("        first-word fall-through - that octet has already left");
        $display("        the RAM, which is where tx_fifo's DEPTH+1 comes from.");
        m_axis_tready = 1'b1;
        ridle(10);
        check("2.7 releasing tready drains the frame", n_oct === 4);
        check("2.7 payload intact after a stall",
              (cap[0] === 8'h50) && (cap[3] === 8'h53));
        check("2.7 tlast on the 4th octet",            capl[3] === 1'b1);

        clear_mon;
        m_axis_tready = 1'b1;
        push_frame(6, 8'h60, 1'b1);
        widle(4);

        for (i = 0; i < 14; i = i + 1) begin
            @(negedge rd_clk);
            m_axis_tready <= i[0];
        end
        @(negedge rd_clk);
        m_axis_tready <= 1'b1;
        ridle(10);
        check("2.8 a choppy consumer still gets all 6 octets", n_oct === 6);
        bad = 0;
        for (i = 0; i < 6; i = i + 1)
            if (cap[i] !== (8'h60 + i[7:0])) bad = bad + 1;
        check("2.8 zero ordering errors under backpressure", bad === 0);
        check("2.8 exactly one tlast",                       n_frm === 1);
        $display("        No octet is duplicated and none is lost, because the");
        $display("        read side only clears tvalid on a COMPLETED handshake.");

        clear_mon;
        m_axis_tready = 1'b0;
        push_frame(DEPTH + 6, 8'h00, 1'b1);
        widle(6);
        check("2.9 an oversized frame is dropped",  n_drop === 1);
        check("2.9 and overflow_out identifies why", n_ovf  === 1);

        check("2.9 frame_cmt_out did NOT pulse despite a GOOD CRC", n_cmt === 0);
        m_axis_tready = 1'b1;
        ridle(20);
        check("2.9 NOTHING was delivered - not even a truncated frame",
              n_oct === 0);
        $display("        Its CRC was declared GOOD and it is still dropped.");
        $display("        We could not store it, so we cannot deliver it. And we");
        $display("        deliver NOTHING rather than the first 16 octets: a");
        $display("        truncated frame is worse than no frame, because the");
        $display("        host would have to detect the truncation itself.");

        clear_mon;
        m_axis_tready = 1'b1;
        push_frame(3, 8'h90, 1'b1);
        widle(4);
        ridle(10);
        check("2.10 the FIFO works again after an overflow", n_oct === 3);
        check("2.10 payload intact",
              (cap[0] === 8'h90) && (cap[2] === 8'h92));
        check("2.10 no spurious drop",                       n_drop === 0);
        $display("        ovf_sticky clears on the verdict, so one oversized");
        $display("        frame costs exactly one frame.");

        clear_mon;
        m_axis_tready = 1'b0;
        check("2.11 frame_avail_out LOW when empty", frame_avail_out === 1'b0);
        wbeat(8'hF1, 1'b0);
        wbeat(8'hF2, 1'b1);
        wquiet;
        widle(4);
        ridle(3);
        check("2.11 still LOW before the verdict",   frame_avail_out === 1'b0);
        verdict(1'b1);
        widle(4);
        ridle(4);
        check("2.11 HIGH once a frame is committed", frame_avail_out === 1'b1);
        m_axis_tready = 1'b1;
        ridle(10);
        check("2.11 LOW again once drained",         frame_avail_out === 1'b0);
        check("2.11 the frame came out",             n_oct === 2);
        $display("        frame_avail_out is the host's 'is there anything for");
        $display("        me' bit - the RX counterpart of tx_fifo's identically");
        $display("        named pin. It never rises for an uncommitted frame.");

        clear_mon;
        push_frame(1, 8'h7E, 1'b1);
        widle(4);
        ridle(8);
        check("2.12 a 1-octet frame is delivered", n_oct === 1);
        check("2.12 with tlast on it",             capl[0] === 1'b1);
        check("2.12 and it is 0x7E",               cap[0] === 8'h7E);

        clear_mon;
        m_axis_tready = 1'b1;
        push_frame(DEPTH, 8'h20, 1'b1);
        widle(4);
        ridle(2 + 2 * DEPTH);
        check("2.13 a frame of exactly DEPTH octets fits", n_oct === DEPTH);
        check("2.13 no overflow reported",                 n_ovf === 0);
        bad = 0;
        for (i = 0; i < DEPTH; i = i + 1)
            if (cap[i] !== (8'h20 + i[7:0])) bad = bad + 1;
        check("2.13 all DEPTH octets in order",            bad === 0);
        check("2.13 tlast on the last one",   capl[DEPTH-1] === 1'b1);
        $display("        The reader was draining, so slots freed as we wrote.");
        $display("        2.9 filled with nobody draining, which is the real");
        $display("        overflow condition.");

        $display("");
        $display("======================================================================");
        $display(" RESULT : %0d passed, %0d failed, %0d total",
                 pass_n, fail_n, pass_n + fail_n);
        if (fail_n == 0)
            $display(" rx_fifo_tb : ALL CHECKS PASS");
        else
            $display(" rx_fifo_tb : *** FAILURES ***");
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

