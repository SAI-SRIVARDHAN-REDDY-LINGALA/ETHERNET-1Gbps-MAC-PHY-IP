// tx_fifo_advanced_tb - Advanced TX FIFO tests.

`timescale 1ns / 1ps
`default_nettype none

module tx_fifo_advanced_tb;

    localparam integer DW      = 8;

    localparam integer AW_S    = 6;
    localparam integer AW_L    = 11;
    localparam integer DEPTH_S = (1 << AW_S);

    localparam integer CAP_S   = 4096;
    localparam integer CAP_L   = 4096;
    localparam integer CAP_A   = 1024;

    localparam real P_A = 10.00;
    localparam real P_B =  8.00;
    localparam real P_C = 30.00;
    localparam real P_D =  5.00;
    localparam real P_E = 40.00;
    localparam real P_F = 10.03;

    reg clk_a, clk_b, clk_c, clk_d, clk_e, clk_f;

    initial begin
        clk_a = 1'b0; clk_b = 1'b0; clk_c = 1'b0;
        clk_d = 1'b0; clk_e = 1'b0; clk_f = 1'b0;
    end

    always #(P_A / 2.0) clk_a = ~clk_a;
    always #(P_B / 2.0) clk_b = ~clk_b;
    always #(P_C / 2.0) clk_c = ~clk_c;
    always #(P_D / 2.0) clk_d = ~clk_d;
    always #(P_E / 2.0) clk_e = ~clk_e;
    always #(P_F / 2.0) clk_f = ~clk_f;

    reg rst_n;

    reg clr;

    reg  [DW-1:0] a_tdata;
    reg           a_tvalid;
    reg           a_tlast;
    wire          a_tready;
    wire          a_drop;
    wire [DW-1:0] a_dout;
    wire          a_valid;
    reg           a_ready;
    wire          a_last;
    wire          a_avail;

    tx_fifo #(.DATA_W(DW), .ADDR_W(AW_S)) dut (
        .wr_clk(clk_a), .wr_rst_n(rst_n),
        .s_axis_tdata(a_tdata), .s_axis_tvalid(a_tvalid),
        .s_axis_tready(a_tready), .s_axis_tlast(a_tlast),
        .frame_drop_out(a_drop),
        .rd_clk(clk_b), .rd_rst_n(rst_n),
        .data_out(a_dout), .valid_out(a_valid), .ready_out(a_ready),
        .last_out(a_last), .frame_avail_out(a_avail)
    );

    reg  [DW-1:0] b_tdata;
    reg           b_tvalid;
    reg           b_tlast;
    wire          b_tready;
    wire          b_drop;
    wire [DW-1:0] b_dout;
    wire          b_valid;
    wire          b_ready;
    wire          b_last;
    wire          b_avail;

    tx_fifo #(.DATA_W(DW), .ADDR_W(AW_L)) dut_big (
        .wr_clk(clk_a), .wr_rst_n(rst_n),
        .s_axis_tdata(b_tdata), .s_axis_tvalid(b_tvalid),
        .s_axis_tready(b_tready), .s_axis_tlast(b_tlast),
        .frame_drop_out(b_drop),
        .rd_clk(clk_b), .rd_rst_n(rst_n),
        .data_out(b_dout), .valid_out(b_valid), .ready_out(b_ready),
        .last_out(b_last), .frame_avail_out(b_avail)
    );

    reg           gmii_run;
    reg           gmii_en;
    wire          g_ready;
    wire          g_valid = gmii_run && b_valid;
    assign        b_ready = gmii_run && g_ready;

    always @(posedge clk_b or negedge rst_n) begin
        if (!rst_n) begin
            gmii_run <= 1'b0;
        end else if (!gmii_run) begin
            if (gmii_en && b_avail) gmii_run <= 1'b1;
        end else begin
            if (b_valid && g_ready && b_last) gmii_run <= 1'b0;
        end
    end

    wire [7:0] g_txd;
    wire       g_tx_en;
    wire       g_tx_er;
    wire       g_done;
    wire       g_underrun;

    tx_gmii_mii #(.ERR_CYCLES(2)) u_gmii (
        .tx_clk         (clk_b),
        .rst_n          (rst_n),
        .speed_select   (1'b1),
        .data_in        (b_dout),
        .valid_in       (g_valid),
        .last_in        (b_last),
        .err_in         (1'b0),
        .ready_in       (g_ready),
        .gmii_txd       (g_txd),
        .gmii_tx_en     (g_tx_en),
        .gmii_tx_er     (g_tx_er),
        .frame_done_out (g_done),
        .underrun_out   (g_underrun)
    );

    reg  [DW-1:0] c_tdata;
    reg           c_tvalid;
    reg           c_tlast;
    wire          c_tready;
    wire          c_drop;
    wire [DW-1:0] c_dout;
    wire          c_valid;
    reg           c_ready;
    wire          c_last;
    wire          c_avail;

    tx_fifo #(.DATA_W(DW), .ADDR_W(AW_S)) dut_fw (
        .wr_clk(clk_d), .wr_rst_n(rst_n),
        .s_axis_tdata(c_tdata), .s_axis_tvalid(c_tvalid),
        .s_axis_tready(c_tready), .s_axis_tlast(c_tlast),
        .frame_drop_out(c_drop),
        .rd_clk(clk_e), .rd_rst_n(rst_n),
        .data_out(c_dout), .valid_out(c_valid), .ready_out(c_ready),
        .last_out(c_last), .frame_avail_out(c_avail)
    );

    reg  [DW-1:0] d_tdata;
    reg           d_tvalid;
    reg           d_tlast;
    wire          d_tready;
    wire          d_drop;
    wire [DW-1:0] d_dout;
    wire          d_valid;
    reg           d_ready;
    wire          d_last;
    wire          d_avail;

    tx_fifo #(.DATA_W(DW), .ADDR_W(AW_S)) dut_sw (
        .wr_clk(clk_c), .wr_rst_n(rst_n),
        .s_axis_tdata(d_tdata), .s_axis_tvalid(d_tvalid),
        .s_axis_tready(d_tready), .s_axis_tlast(d_tlast),
        .frame_drop_out(d_drop),
        .rd_clk(clk_b), .rd_rst_n(rst_n),
        .data_out(d_dout), .valid_out(d_valid), .ready_out(d_ready),
        .last_out(d_last), .frame_avail_out(d_avail)
    );

    reg  [DW-1:0] e_tdata;
    reg           e_tvalid;
    reg           e_tlast;
    wire          e_tready;
    wire          e_drop;
    wire [DW-1:0] e_dout;
    wire          e_valid;
    reg           e_ready;
    wire          e_last;
    wire          e_avail;

    tx_fifo #(.DATA_W(DW), .ADDR_W(AW_S)) dut_nc (
        .wr_clk(clk_f), .wr_rst_n(rst_n),
        .s_axis_tdata(e_tdata), .s_axis_tvalid(e_tvalid),
        .s_axis_tready(e_tready), .s_axis_tlast(e_tlast),
        .frame_drop_out(e_drop),
        .rd_clk(clk_a), .rd_rst_n(rst_n),
        .data_out(e_dout), .valid_out(e_valid), .ready_out(e_ready),
        .last_out(e_last), .frame_avail_out(e_avail)
    );

    integer pass_n;
    integer fail_n;

    task check(input [99*8:0] nm, input cond);
        begin
            if (cond) begin
                pass_n = pass_n + 1;
                $display("  PASS : %0s", nm);
            end else begin
                fail_n = fail_n + 1;
                $display("  FAIL : %0s", nm);
            end
        end
    endtask

    reg  [DW-1:0] a_cap  [0:CAP_S-1];
    reg           a_capl [0:CAP_S-1];
    integer a_n, a_frames, a_vcyc, a_facyc;

    always @(posedge clk_b) begin
        if (clr) begin
            a_n <= 0; a_frames <= 0; a_vcyc <= 0; a_facyc <= 0;
        end else if (rst_n) begin
            if (a_valid && a_ready) begin
                if (a_n < CAP_S) begin
                    a_cap[a_n]  <= a_dout;
                    a_capl[a_n] <= a_last;
                end
                a_n <= a_n + 1;
                if (a_last) a_frames <= a_frames + 1;
            end
            if (a_valid) a_vcyc  <= a_vcyc  + 1;
            if (a_avail) a_facyc <= a_facyc + 1;
        end
    end

    integer a_beats, a_drops, a_nordy;

    always @(posedge clk_a) begin
        if (clr) begin
            a_beats <= 0; a_drops <= 0; a_nordy <= 0;
        end else if (rst_n) begin
            if (a_tvalid && a_tready) a_beats <= a_beats + 1;
            if (a_drop)               a_drops <= a_drops + 1;
            if (!a_tready)            a_nordy <= a_nordy + 1;
        end
    end

    reg  [DW-1:0] b_cap [0:CAP_L-1];
    integer b_n, b_frames;

    always @(posedge clk_b) begin
        if (clr) begin
            b_n <= 0; b_frames <= 0;
        end else if (rst_n) begin
            if (b_valid && b_ready) begin
                if (b_n < CAP_L) b_cap[b_n] <= b_dout;
                b_n <= b_n + 1;
                if (b_last) b_frames <= b_frames + 1;
            end
        end
    end

    integer b_beats, b_drops;

    always @(posedge clk_a) begin
        if (clr) begin
            b_beats <= 0; b_drops <= 0;
        end else if (rst_n) begin
            if (b_tvalid && b_tready) b_beats <= b_beats + 1;
            if (b_drop)               b_drops <= b_drops + 1;
        end
    end

    reg  [DW-1:0] g_cap [0:CAP_L-1];
    integer g_n, g_encyc, g_pulses, g_unders, g_dones;
    integer g_run, g_run_min, g_run_max;
    reg     g_en_d;

    always @(posedge clk_b) begin
        if (clr) begin
            g_n <= 0; g_encyc <= 0; g_pulses <= 0; g_unders <= 0; g_dones <= 0;
            g_run <= 0; g_run_max <= 0; g_run_min <= 999999; g_en_d <= 1'b0;
        end else if (!rst_n) begin
            g_en_d <= 1'b0;
            g_run  <= 0;
        end else begin
            if (g_tx_en) begin
                if (g_n < CAP_L) g_cap[g_n] <= g_txd;
                g_n     <= g_n + 1;
                g_encyc <= g_encyc + 1;
                g_run   <= g_run + 1;
            end else begin
                if (g_en_d) begin
                    if (g_run > g_run_max) g_run_max <= g_run;
                    if (g_run < g_run_min) g_run_min <= g_run;
                end
                g_run <= 0;
            end
            if (g_tx_en && !g_en_d) g_pulses <= g_pulses + 1;
            if (g_underrun)         g_unders <= g_unders + 1;
            if (g_done)             g_dones  <= g_dones  + 1;
            g_en_d <= g_tx_en;
        end
    end

    reg  [DW-1:0] c_cap [0:CAP_A-1];
    integer c_n, c_frames, c_drops, c_nordy;

    always @(posedge clk_e) begin
        if (clr) begin
            c_n <= 0; c_frames <= 0;
        end else if (rst_n && c_valid && c_ready) begin
            if (c_n < CAP_A) c_cap[c_n] <= c_dout;
            c_n <= c_n + 1;
            if (c_last) c_frames <= c_frames + 1;
        end
    end

    always @(posedge clk_d) begin
        if (clr) begin
            c_drops <= 0; c_nordy <= 0;
        end else if (rst_n) begin
            if (c_drop)    c_drops <= c_drops + 1;
            if (!c_tready) c_nordy <= c_nordy + 1;
        end
    end

    reg  [DW-1:0] d_cap [0:CAP_A-1];
    integer d_n, d_frames, d_drops;

    always @(posedge clk_b) begin
        if (clr) begin
            d_n <= 0; d_frames <= 0;
        end else if (rst_n && d_valid && d_ready) begin
            if (d_n < CAP_A) d_cap[d_n] <= d_dout;
            d_n <= d_n + 1;
            if (d_last) d_frames <= d_frames + 1;
        end
    end

    always @(posedge clk_c) begin
        if (clr)                   d_drops <= 0;
        else if (rst_n && d_drop)  d_drops <= d_drops + 1;
    end

    reg  [DW-1:0] e_cap [0:CAP_A-1];
    integer e_n, e_frames, e_drops;

    always @(posedge clk_a) begin
        if (clr) begin
            e_n <= 0; e_frames <= 0;
        end else if (rst_n && e_valid && e_ready) begin
            if (e_n < CAP_A) e_cap[e_n] <= e_dout;
            e_n <= e_n + 1;
            if (e_last) e_frames <= e_frames + 1;
        end
    end

    always @(posedge clk_f) begin
        if (clr)                   e_drops <= 0;
        else if (rst_n && e_drop)  e_drops <= e_drops + 1;
    end

    function integer hamming;
        input [AW_S:0] x;
        input [AW_S:0] y;
        integer i;
        integer n;
        reg [AW_S:0] z;
        begin
            z = x ^ y;
            n = 0;
            for (i = 0; i <= AW_S; i = i + 1)
                if (z[i]) n = n + 1;
            hamming = n;
        end
    endfunction

    reg [AW_S:0] pw_a, pr_a, pw_c, pr_c, pw_d, pr_d, pw_e, pr_e;

    integer ge_wa, gv_wa, gm_wa;
    integer ge_ra, gv_ra, gm_ra;
    integer ge_wc, gv_wc, gm_wc;
    integer ge_rc, gv_rc, gm_rc;
    integer ge_wd, gv_wd, gm_wd;
    integer ge_rd, gv_rd, gm_rd;
    integer ge_we, gv_we, gm_we;
    integer ge_re, gv_re, gm_re;

    integer hd_wa, hd_ra, hd_wc, hd_rc, hd_wd, hd_rd, hd_we, hd_re;

    always @(posedge clk_a) begin
        if (!rst_n) pw_a <= {(AW_S+1){1'b0}};
        else begin
            hd_wa = hamming(dut.wr_frm_gray, pw_a);
            if (hd_wa > 0) begin
                ge_wa <= ge_wa + 1;
                if (hd_wa > gm_wa) gm_wa <= hd_wa;
                if (hd_wa > 1)     gv_wa <= gv_wa + 1;
            end
            pw_a <= dut.wr_frm_gray;
        end
    end

    always @(posedge clk_d) begin
        if (!rst_n) pw_c <= {(AW_S+1){1'b0}};
        else begin
            hd_wc = hamming(dut_fw.wr_frm_gray, pw_c);
            if (hd_wc > 0) begin
                ge_wc <= ge_wc + 1;
                if (hd_wc > gm_wc) gm_wc <= hd_wc;
                if (hd_wc > 1)     gv_wc <= gv_wc + 1;
            end
            pw_c <= dut_fw.wr_frm_gray;
        end
    end

    always @(posedge clk_c) begin
        if (!rst_n) pw_d <= {(AW_S+1){1'b0}};
        else begin
            hd_wd = hamming(dut_sw.wr_frm_gray, pw_d);
            if (hd_wd > 0) begin
                ge_wd <= ge_wd + 1;
                if (hd_wd > gm_wd) gm_wd <= hd_wd;
                if (hd_wd > 1)     gv_wd <= gv_wd + 1;
            end
            pw_d <= dut_sw.wr_frm_gray;
        end
    end

    always @(posedge clk_f) begin
        if (!rst_n) pw_e <= {(AW_S+1){1'b0}};
        else begin
            hd_we = hamming(dut_nc.wr_frm_gray, pw_e);
            if (hd_we > 0) begin
                ge_we <= ge_we + 1;
                if (hd_we > gm_we) gm_we <= hd_we;
                if (hd_we > 1)     gv_we <= gv_we + 1;
            end
            pw_e <= dut_nc.wr_frm_gray;
        end
    end

    always @(posedge clk_b) begin
        if (!rst_n) begin
            pr_a <= {(AW_S+1){1'b0}};
            pr_d <= {(AW_S+1){1'b0}};
        end else begin
            hd_ra = hamming(dut.rd_gray, pr_a);
            if (hd_ra > 0) begin
                ge_ra <= ge_ra + 1;
                if (hd_ra > gm_ra) gm_ra <= hd_ra;
                if (hd_ra > 1)     gv_ra <= gv_ra + 1;
            end
            pr_a <= dut.rd_gray;

            hd_rd = hamming(dut_sw.rd_gray, pr_d);
            if (hd_rd > 0) begin
                ge_rd <= ge_rd + 1;
                if (hd_rd > gm_rd) gm_rd <= hd_rd;
                if (hd_rd > 1)     gv_rd <= gv_rd + 1;
            end
            pr_d <= dut_sw.rd_gray;
        end
    end

    always @(posedge clk_e) begin
        if (!rst_n) pr_c <= {(AW_S+1){1'b0}};
        else begin
            hd_rc = hamming(dut_fw.rd_gray, pr_c);
            if (hd_rc > 0) begin
                ge_rc <= ge_rc + 1;
                if (hd_rc > gm_rc) gm_rc <= hd_rc;
                if (hd_rc > 1)     gv_rc <= gv_rc + 1;
            end
            pr_c <= dut_fw.rd_gray;
        end
    end

    always @(posedge clk_a) begin
        if (!rst_n) pr_e <= {(AW_S+1){1'b0}};
        else begin
            hd_re = hamming(dut_nc.rd_gray, pr_e);
            if (hd_re > 0) begin
                ge_re <= ge_re + 1;
                if (hd_re > gm_re) gm_re <= hd_re;
                if (hd_re > 1)     gv_re <= gv_re + 1;
            end
            pr_e <= dut_nc.rd_gray;
        end
    end

    integer gray_edges, gray_viol, gray_max;

    task gray_total;
        begin
            gray_edges = ge_wa + ge_ra + ge_wc + ge_rc +
                         ge_wd + ge_rd + ge_we + ge_re;
            gray_viol  = gv_wa + gv_ra + gv_wc + gv_rc +
                         gv_wd + gv_rd + gv_we + gv_re;
            gray_max   = 0;
            if (gm_wa > gray_max) gray_max = gm_wa;
            if (gm_ra > gray_max) gray_max = gm_ra;
            if (gm_wc > gray_max) gray_max = gm_wc;
            if (gm_rc > gray_max) gray_max = gm_rc;
            if (gm_wd > gray_max) gray_max = gm_wd;
            if (gm_rd > gray_max) gray_max = gm_rd;
            if (gm_we > gray_max) gray_max = gm_we;
            if (gm_re > gray_max) gray_max = gm_re;
        end
    endtask

    integer inv_hold;
    integer inv_valid_avail;
    integer inv_gmii_ce;
    integer inv_drop_rdy;

    reg           a_v_d, a_r_d, a_l_d;
    reg [DW-1:0]  a_d_d;

    always @(posedge clk_b) begin
        if (!rst_n) begin
            a_v_d <= 1'b0; a_r_d <= 1'b0;
            a_d_d <= {DW{1'b0}}; a_l_d <= 1'b0;
        end else begin
            if (a_v_d && !a_r_d) begin
                if ((a_valid !== 1'b1) || (a_dout !== a_d_d) || (a_last !== a_l_d))
                    inv_hold <= inv_hold + 1;
            end
            if (a_valid && !a_avail) inv_valid_avail <= inv_valid_avail + 1;
            if (g_tx_er && !g_tx_en) inv_gmii_ce     <= inv_gmii_ce + 1;
            a_v_d <= a_valid;
            a_r_d <= a_ready;
            a_d_d <= a_dout;
            a_l_d <= a_last;
        end
    end

    always @(posedge clk_a) begin
        if (rst_n && dut.dropping && !a_tready)
            inv_drop_rdy <= inv_drop_rdy + 1;
    end

    task clear_all;
        begin
            clr = 1'b1;
            #(3.0 * P_E);
            clr = 1'b0;
            #(1.5 * P_E);
        end
    endtask

    task do_reset;
        begin
            rst_n    = 1'b0;
            a_tvalid = 1'b0; a_tlast = 1'b0; a_tdata = 8'h00; a_ready = 1'b0;
            b_tvalid = 1'b0; b_tlast = 1'b0; b_tdata = 8'h00;
            c_tvalid = 1'b0; c_tlast = 1'b0; c_tdata = 8'h00; c_ready = 1'b0;
            d_tvalid = 1'b0; d_tlast = 1'b0; d_tdata = 8'h00; d_ready = 1'b0;
            e_tvalid = 1'b0; e_tlast = 1'b0; e_tdata = 8'h00; e_ready = 1'b0;
            gmii_en  = 1'b0;
            clear_all;
            #(4.0 * P_E);
            @(negedge clk_a) rst_n = 1'b1;
            #(4.0 * P_E);
        end
    endtask

    task w_a(input integer n); integer i;
        begin for (i=0;i<n;i=i+1) @(posedge clk_a); end endtask
    task w_b(input integer n); integer i;
        begin for (i=0;i<n;i=i+1) @(posedge clk_b); end endtask
    task w_e(input integer n); integer i;
        begin for (i=0;i<n;i=i+1) @(posedge clk_e); end endtask

    function [DW-1:0] expd(input integer base, input integer idx);
        begin
            expd = (base + idx) & 8'hFF;
        end
    endfunction

    task wr_a(input integer n, input integer base,
              input integer gap, input use_last);
        integer i, j;
        begin
            i = 0;
            @(negedge clk_a);
            while (i < n) begin
                a_tdata  <= expd(base, i);
                a_tvalid <= 1'b1;
                a_tlast  <= (use_last && (i == (n-1)));
                @(posedge clk_a);
                if (a_tready) i = i + 1;
                @(negedge clk_a);
                if (gap > 0 && i < n) begin
                    a_tvalid <= 1'b0;
                    a_tlast  <= 1'b0;
                    for (j = 0; j < gap; j = j + 1) @(negedge clk_a);
                end
            end
            a_tvalid <= 1'b0;
            a_tlast  <= 1'b0;
        end
    endtask

    task wr_b(input integer n, input integer base,
              input integer gap, input use_last);
        integer i, j;
        begin
            i = 0;
            @(negedge clk_a);
            while (i < n) begin
                b_tdata  <= expd(base, i);
                b_tvalid <= 1'b1;
                b_tlast  <= (use_last && (i == (n-1)));
                @(posedge clk_a);
                if (b_tready) i = i + 1;
                @(negedge clk_a);
                if (gap > 0 && i < n) begin
                    b_tvalid <= 1'b0;
                    b_tlast  <= 1'b0;
                    for (j = 0; j < gap; j = j + 1) @(negedge clk_a);
                end
            end
            b_tvalid <= 1'b0;
            b_tlast  <= 1'b0;
        end
    endtask

    task wr_c(input integer n, input integer base);
        integer i;
        begin
            i = 0;
            @(negedge clk_d);
            while (i < n) begin
                c_tdata  <= expd(base, i);
                c_tvalid <= 1'b1;
                c_tlast  <= (i == (n-1));
                @(posedge clk_d);
                if (c_tready) i = i + 1;
                @(negedge clk_d);
            end
            c_tvalid <= 1'b0;
            c_tlast  <= 1'b0;
        end
    endtask

    task wr_d(input integer n, input integer base);
        integer i;
        begin
            i = 0;
            @(negedge clk_c);
            while (i < n) begin
                d_tdata  <= expd(base, i);
                d_tvalid <= 1'b1;
                d_tlast  <= (i == (n-1));
                @(posedge clk_c);
                if (d_tready) i = i + 1;
                @(negedge clk_c);
            end
            d_tvalid <= 1'b0;
            d_tlast  <= 1'b0;
        end
    endtask

    task wr_e(input integer n, input integer base);
        integer i;
        begin
            i = 0;
            @(negedge clk_f);
            while (i < n) begin
                e_tdata  <= expd(base, i);
                e_tvalid <= 1'b1;
                e_tlast  <= (i == (n-1));
                @(posedge clk_f);
                if (e_tready) i = i + 1;
                @(negedge clk_f);
            end
            e_tvalid <= 1'b0;
            e_tlast  <= 1'b0;
        end
    endtask

    integer vbad;

    task vfy_a(input integer start, input integer n, input integer base);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                if (a_cap[start+i] !== expd(base, i)) vbad = vbad + 1;
        end
    endtask

    task vfy_b(input integer start, input integer n, input integer base);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                if (b_cap[start+i] !== expd(base, i)) vbad = vbad + 1;
        end
    endtask

    task vfy_g(input integer start, input integer n, input integer base);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                if (g_cap[start+i] !== expd(base, i)) vbad = vbad + 1;
        end
    endtask

    task vfy_c(input integer start, input integer n, input integer base);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                if (c_cap[start+i] !== expd(base, i)) vbad = vbad + 1;
        end
    endtask

    task vfy_d(input integer start, input integer n, input integer base);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                if (d_cap[start+i] !== expd(base, i)) vbad = vbad + 1;
        end
    endtask

    task vfy_e(input integer start, input integer n, input integer base);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                if (e_cap[start+i] !== expd(base, i)) vbad = vbad + 1;
        end
    endtask

    reg        a_rand_rdy;
    integer    seed;

    always @(negedge clk_b) begin
        if (a_rand_rdy) a_ready <= (({$random(seed)} % 100) < 55);
    end

    integer k, t0, t1, lat1, lat2, dlat;

    initial begin
        $dumpfile("tx_fifo_tb.vcd");
        $dumpvars(0, tx_fifo_advanced_tb);

        pass_n = 0; fail_n = 0;
        seed   = 32'h5A17_C0DE;
        clr    = 1'b0;
        a_rand_rdy = 1'b0;
        vbad = 0;
        inv_hold = 0; inv_valid_avail = 0; inv_gmii_ce = 0; inv_drop_rdy = 0;
        ge_wa=0; gv_wa=0; gm_wa=0;  ge_ra=0; gv_ra=0; gm_ra=0;
        ge_wc=0; gv_wc=0; gm_wc=0;  ge_rc=0; gv_rc=0; gm_rc=0;
        ge_wd=0; gv_wd=0; gm_wd=0;  ge_rd=0; gv_rd=0; gm_rd=0;
        ge_we=0; gv_we=0; gm_we=0;  ge_re=0; gv_re=0; gm_re=0;

        $display("=========================================================");
        $display(" tx_fifo_advanced_tb -  tx_fifo corner / stress / CDC");
        $display("   dut     ADDR_W=%0d  wr %0.2f ns  rd %0.2f ns", AW_S, P_A, P_B);
        $display("   dut_big ADDR_W=%0d  wr %0.2f ns  rd %0.2f ns  + gmii_mii_tx",
                 AW_L, P_A, P_B);
        $display("   dut_fw  ADDR_W=%0d  wr %0.2f ns  rd %0.2f ns  (writer 8x)",
                 AW_S, P_D, P_E);
        $display("   dut_sw  ADDR_W=%0d  wr %0.2f ns  rd %0.2f ns  (reader 3.75x)",
                 AW_S, P_C, P_B);
        $display("   dut_nc  ADDR_W=%0d  wr %0.2f ns  rd %0.2f ns  (phase drift)",
                 AW_S, P_F, P_A);
        $display("=========================================================");
        $display("");

        $display("[TC1] Reset - all five instances, both domains");
        do_reset;
        check("TC1 dut     tready high, valid low, avail low",
              a_tready === 1'b1 && a_valid === 1'b0 && a_avail === 1'b0);
        check("TC1 dut_big tready high, valid low, avail low",
              b_tready === 1'b1 && b_valid === 1'b0 && b_avail === 1'b0);
        check("TC1 dut_fw  tready high, valid low, avail low",
              c_tready === 1'b1 && c_valid === 1'b0 && c_avail === 1'b0);
        check("TC1 dut_sw  tready high, valid low, avail low",
              d_tready === 1'b1 && d_valid === 1'b0 && d_avail === 1'b0);
        check("TC1 dut_nc  tready high, valid low, avail low",
              e_tready === 1'b1 && e_valid === 1'b0 && e_avail === 1'b0);
        check("TC1 no drop pulses on any instance",
              a_drop === 1'b0 && b_drop === 1'b0 && c_drop === 1'b0 &&
              d_drop === 1'b0 && e_drop === 1'b0);
        check("TC1 gmii TX_EN and TX_ER both low",
              g_tx_en === 1'b0 && g_tx_er === 1'b0);
        $display("");

        $display("[TC2] Reset applied mid-frame, then recovery");
        clear_all;
        a_ready = 1'b1;
        fork
            wr_a(40, 8'h70, 0, 1'b1);
            begin
                w_a(6);
                @(negedge clk_a) rst_n = 1'b0;
                #(4.0 * P_A);
                @(negedge clk_a) rst_n = 1'b1;
            end
        join
        w_b(220);
        check("TC2 the FIFO returns to idle by itself",
              a_valid === 1'b0 && a_avail === 1'b0 && a_tready === 1'b1);
        check("TC2 the reset itself triggered no drop", a_drops === 0);
        clear_all;
        wr_a(24, 8'h33, 0, 1'b1);
        w_b(60);
        vbad = 0; vfy_a(0, 24, 8'h33);
        check("TC2 the next frame after reset is bit-exact",
              a_n === 24 && vbad === 0);
        $display("");

        $display("[TC3] 64-octet minimum frame (clause 4.2.3.3)");
        clear_all;
        wr_a(64, 8'h00, 0, 1'b1);
        w_b(140);
        vbad = 0; vfy_a(0, 64, 8'h00);
        check("TC3 64 octets received",  a_n === 64);
        check("TC3 exactly 1 frame",     a_frames === 1);
        check("TC3 bit-exact",           vbad === 0);
        $display("");

        $display("[TC4] 1518-octet maximum untagged frame - dut_big");
        clear_all;
        gmii_en = 1'b0;
        wr_b(1518, 8'h00, 0, 1'b1);
        check("TC4 all 1518 octets accepted by the write side", b_beats === 1518);
        check("TC4 nothing visible yet (launch gate closed)",   b_n === 0);
        gmii_en = 1'b1;
        w_b(1700);
        vbad = 0; vfy_b(0, 1518, 8'h00);
        check("TC4 1518 octets read out",    b_n === 1518);
        check("TC4 exactly 1 frame",         b_frames === 1);
        check("TC4 bit-exact (256 values swept ~6x)", vbad === 0);
        vbad = 0; vfy_g(0, 1518, 8'h00);
        check("TC4 the same 1518 octets on the GMII pins",
              g_n === 1518 && vbad === 0);
        check("TC4 exactly one TX_EN pulse",  g_pulses === 1);
        check("TC4 TX_EN run length == 1518 (no truncation)", g_run_max === 1518);
        check("TC4 zero underruns on a max-size frame", g_unders === 0);
        gmii_en = 1'b0;
        $display("        TX_EN pulses=%0d  in-frame cycles=%0d  underruns=%0d",
                 g_pulses, g_encyc, g_unders);
        $display("");

        $display("[TC5] 1-octet frame - the most degenerate legal shape");
        clear_all;
        wr_a(1, 8'hE7, 0, 1'b1);
        w_b(30);
        check("TC5 exactly 1 octet received", a_n === 1);
        check("TC5 value correct",            a_cap[0] === 8'hE7);
        check("TC5 last_out set on it",       a_capl[0] === 1'b1);
        check("TC5 exactly 1 frame",          a_frames === 1);
        $display("");

        $display("[TC6] STORE-AND-FORWARD: partial frame invisible for 400 cycles");
        clear_all;
        wr_a(50, 8'h90, 0, 1'b0);
        w_b(400);
        check("TC6 the write side accepted all 50", a_beats === 50);
        check("TC6 the reader saw ZERO octets",     a_n === 0);
        check("TC6 valid_out never rose",           a_vcyc === 0);
        check("TC6 frame_avail_out never rose",     a_facyc === 0);
        check("TC6 no spurious drop",               a_drops === 0);
        $display("        50 octets resident, 0 visible, 400 read cycles elapsed");
        $display("");

        $display("[TC7] Commit atomicity: 0 readable, then all 51 readable");
        clear_all;
        wr_a(1, 8'h90 + 50, 0, 1'b1);
        w_b(140);
        check("TC7 all 51 octets released by ONE commit", a_n === 51);
        check("TC7 exactly 1 frame",                      a_frames === 1);
        vbad = 0; vfy_a(0, 51, 8'h90);
        check("TC7 all 51 bit-exact",                     vbad === 0);
        $display("");

        $display("[TC8] Backpressure without loss - reader idle, FIFO fills");
        clear_all;
        a_ready = 1'b0;
        wr_a(30, 8'h40, 0, 1'b1);
        wr_a(30, 8'h60, 0, 1'b1);
        w_a(10);
        check("TC8 60 of 64 resident, tready still high", a_tready === 1'b1);
        fork
            wr_a(20, 8'hB0, 0, 1'b1);
            begin
                w_a(12);
                check("TC8 tready went LOW (backpressure, not drop)",
                      a_tready === 1'b0);
                check("TC8 nothing dropped while merely full", a_drops === 0);
                @(negedge clk_b) a_ready = 1'b1;
            end
        join
        w_b(300);
        check("TC8 all 80 octets eventually arrive", a_n === 80);
        check("TC8 3 frames",                        a_frames === 3);
        vbad = 0; vfy_a(0,  30, 8'h40);
        check("TC8 frame 1 bit-exact", vbad === 0);
        vbad = 0; vfy_a(30, 30, 8'h60);
        check("TC8 frame 2 bit-exact", vbad === 0);
        vbad = 0; vfy_a(60, 20, 8'hB0);
        check("TC8 frame 3 bit-exact", vbad === 0);
        check("TC8 still zero drops",  a_drops === 0);
        $display("        tready was low for %0d cycles - a LOSSLESS stall",
                 a_nordy);
        $display("");

        $display("[TC9] DEADLOCK ESCAPE - a %0d-octet frame into a %0d-deep FIFO",
                 DEPTH_S + 40, DEPTH_S);
        clear_all;
        a_ready = 1'b0;
        wr_a(DEPTH_S + 40, 8'h01, 0, 1'b1);
        w_a(20);
        check("TC9 frame_drop_out fired EXACTLY once", a_drops === 1);
        check("TC9 the whole oversize frame was swallowed, not stalled",
              a_beats === (DEPTH_S + 40));
        check("TC9 tready is high again (the drop ended at tlast)",
              a_tready === 1'b1);
        check("TC9 dropping flag cleared",  dut.dropping === 1'b0);
        @(negedge clk_b) a_ready = 1'b1;
        w_b(200);
        check("TC9 NOTHING reached the reader",  a_n === 0);
        check("TC9 no ghost frame was emitted",  a_frames === 0);
        check("TC9 tready never went low during the drop", inv_drop_rdy === 0);
        $display("        %0d octets swallowed, 0 emitted, the link is still alive",
                 a_beats);
        $display("");

        $display("[TC10] No ghost frame: the frame after a drop is bit-exact");
        clear_all;
        a_ready = 1'b1;
        wr_a(24, 8'hD0, 0, 1'b1);
        w_b(120);
        vbad = 0; vfy_a(0, 24, 8'hD0);
        check("TC10 24 octets, exactly 1 frame", a_n === 24 && a_frames === 1);
        check("TC10 bit-exact after the drop",   vbad === 0);
        check("TC10 no further drops",           a_drops === 0);
        $display("");

        $display("[TC11] A committed frame survives a later oversize drop");
        clear_all;
        a_ready = 1'b1;
        wr_a(20, 8'h55, 0, 1'b1);
        wr_a(DEPTH_S + 20, 8'hAA, 0, 1'b1);
        w_a(30);
        check("TC11 exactly 1 drop", a_drops === 1);
        check("TC11 every offered octet was consumed, good and dropped alike",
              a_beats === (20 + DEPTH_S + 20));
        w_b(200);
        check("TC11 the good frame survived intact",
              a_n === 20 && a_frames === 1);
        vbad = 0; vfy_a(0, 20, 8'h55);
        check("TC11 the survivor is bit-exact",  vbad === 0);
        check("TC11 not one octet of the oversize frame leaked through",
              a_n === 20);
        $display("");

        $display("[TC12] Drop does NOT fire on ordinary congestion");
        clear_all;
        a_ready = 1'b0;
        fork
            begin : tc12_wr
                for (k = 0; k < 6; k = k + 1)
                    wr_a(16, 8'h10 + (k * 16), 0, 1'b1);
            end
            begin : tc12_drain
                w_a(80);
                check("TC12 the FIFO is genuinely full", a_tready === 1'b0);
                check("TC12 but nothing was dropped",    a_drops === 0);
                @(negedge clk_b) a_ready = 1'b1;
            end
        join
        w_b(400);
        check("TC12 all 96 octets arrive after draining", a_n === 96);
        check("TC12 all 6 frames intact",                 a_frames === 6);
        vbad = 0;
        for (k = 0; k < 6; k = k + 1) vfy_a(k * 16, 16, 8'h10 + (k * 16));
        check("TC12 every congested frame bit-exact", vbad === 0);
        check("TC12 zero drops throughout",           a_drops === 0);
        $display("");

        $display("[TC13] Pointer wrap - %0d octets through a %0d-deep FIFO",
                 16 * DEPTH_S, DEPTH_S);
        clear_all;
        a_ready = 1'b1;
        for (k = 0; k < 32; k = k + 1) wr_a(32, 8'h07 * (k + 1), 0, 1'b1);
        w_b(600);
        check("TC13 all 1024 octets received", a_n === (16 * DEPTH_S));
        check("TC13 32 frames",                a_frames === 32);
        vbad = 0;
        for (k = 0; k < 32; k = k + 1) vfy_a(k * 32, 32, 8'h07 * (k + 1));
        check("TC13 every frame bit-exact across 16 wraps", vbad === 0);
        $display("");

        $display("[TC14] Writer bubbles - 3 idle cycles between every octet");
        clear_all;
        wr_a(40, 8'h2B, 3, 1'b1);
        w_b(200);
        vbad = 0; vfy_a(0, 40, 8'h2B);
        check("TC14 40 octets despite the bubbles", a_n === 40);
        check("TC14 bit-exact",                    vbad === 0);
        check("TC14 exactly 1 frame",              a_frames === 1);
        $display("");

        $display("[TC15] Reader stalls - random ready_in at ~55%% duty");
        clear_all;
        a_rand_rdy = 1'b1;
        wr_a(60, 8'h4C, 0, 1'b1);
        w_b(400);
        a_rand_rdy = 1'b0;
        @(negedge clk_b) a_ready = 1'b1;
        w_b(20);
        vbad = 0; vfy_a(0, 60, 8'h4C);
        check("TC15 60 octets despite random stalls",  a_n === 60);
        check("TC15 bit-exact",                        vbad === 0);
        check("TC15 handshake stability never broken", inv_hold === 0);
        $display("");

        $display("[TC16] Both sides random, simultaneously");
        clear_all;
        a_rand_rdy = 1'b1;
        wr_a(50, 8'h81, 2, 1'b1);
        wr_a(50, 8'hC3, 1, 1'b1);
        w_b(600);
        a_rand_rdy = 1'b0;
        @(negedge clk_b) a_ready = 1'b1;
        w_b(20);
        check("TC16 100 octets total", a_n === 100);
        check("TC16 2 frames",         a_frames === 2);
        vbad = 0; vfy_a(0,  50, 8'h81);
        check("TC16 frame A bit-exact", vbad === 0);
        vbad = 0; vfy_a(50, 50, 8'hC3);
        check("TC16 frame B bit-exact", vbad === 0);
        $display("");

        $display("[TC17] WHITEBOX: every crossing vector is a true Gray code");
        gray_total;
        check("TC17 at least 400 pointer transitions were observed",
              gray_edges > 400);
        check("TC17 max Hamming distance per clock == 1", gray_max === 1);
        check("TC17 ZERO multi-bit transitions",          gray_viol === 0);
        $display("        %0d transitions on 8 crossing vectors, max distance %0d",
                 gray_edges, gray_max);
        $display("        a plain binary pointer would show distance up to %0d here",
                 AW_S + 1);
        $display("");

        $display("[TC18] Writer floods 8:1 - dut_fw (200 MHz in, 25 MHz out)");
        clear_all;
        @(negedge clk_e) c_ready = 1'b1;
        for (k = 0; k < 4; k = k + 1) wr_c(40, 8'h11 * (k + 1));
        w_e(220);
        check("TC18 160 octets received", c_n === 160);
        check("TC18 4 frames",            c_frames === 4);
        vbad = 0;
        for (k = 0; k < 4; k = k + 1) vfy_c(k * 40, 40, 8'h11 * (k + 1));
        check("TC18 bit-exact at 8:1 overspeed", vbad === 0);
        check("TC18 no frame dropped - backpressure did the work",
              c_drops === 0);
        check("TC18 tready DID go low, so the writer really was throttled",
              c_nordy > 0);
        $display("        writer stalled for %0d cycles", c_nordy);
        $display("");

        $display("[TC19] Reader starved 1:3.75 - dut_sw (33 MHz in, 125 MHz out)");
        clear_all;
        @(negedge clk_b) d_ready = 1'b1;
        for (k = 0; k < 4; k = k + 1) wr_d(30, 8'h23 * (k + 1));
        w_b(400);
        check("TC19 120 octets received", d_n === 120);
        check("TC19 4 frames",            d_frames === 4);
        vbad = 0;
        for (k = 0; k < 4; k = k + 1) vfy_d(k * 30, 30, 8'h23 * (k + 1));
        check("TC19 bit-exact with a starved reader", vbad === 0);
        check("TC19 no drops",                        d_drops === 0);
        $display("");

        $display("[TC20] Near-coincident clocks - dut_nc (10.03 ns vs 10.00 ns)");
        clear_all;
        @(negedge clk_a) e_ready = 1'b1;
        for (k = 0; k < 8; k = k + 1) wr_e(24, 8'h31 * (k + 1));
        w_a(500);
        check("TC20 192 octets received", e_n === 192);
        check("TC20 8 frames",            e_frames === 8);
        vbad = 0;
        for (k = 0; k < 8; k = k + 1) vfy_e(k * 24, 24, 8'h31 * (k + 1));
        check("TC20 bit-exact through the phase sweep", vbad === 0);
        check("TC20 no drops",                          e_drops === 0);
        $display("        phase slides a full cycle every ~3.3 us");
        $display("");

        $display("[TC21] Eight 1-octet frames back to back");
        clear_all;
        a_ready = 1'b1;
        for (k = 0; k < 8; k = k + 1) wr_a(1, 8'hF0 + k, 0, 1'b1);
        w_b(200);
        check("TC21 8 octets received", a_n === 8);
        check("TC21 8 DISTINCT frames", a_frames === 8);
        vbad = 0;
        for (k = 0; k < 8; k = k + 1) begin
            if (a_cap[k]  !== (8'hF0 + k)) vbad = vbad + 1;
            if (a_capl[k] !== 1'b1)        vbad = vbad + 1;
        end
        check("TC21 every octet carries last_out", vbad === 0);
        $display("");

        $display("[TC22/TC23] INTEGRATION - gmii_mii_tx fed by dut_big");
        clear_all;
        gmii_en = 1'b1;
        wr_b(64,  8'h00, 4, 1'b1);
        wr_b(100, 8'h40, 7, 1'b1);
        wr_b(64,  8'h80, 2, 1'b1);
        w_b(700);
        check("TC23 3 frames reached the GMII pins", g_pulses === 3);
        check("TC23 228 in-frame cycles total (64+100+64)", g_encyc === 228);
        check("TC23 3 frame_done pulses",            g_dones === 3);
        vbad = 0; vfy_g(0,   64,  8'h00);
        check("TC23 frame 1 bit-exact on the pins",  vbad === 0);
        vbad = 0; vfy_g(64,  100, 8'h40);
        check("TC23 frame 2 bit-exact on the pins",  vbad === 0);
        vbad = 0; vfy_g(164, 64,  8'h80);
        check("TC23 frame 3 bit-exact on the pins",  vbad === 0);
        check("TC22 gmii_mii_tx.underrun_out fired ZERO times", g_unders === 0);
        check("TC22 longest TX_EN run == 100 (frame 2, exactly)",
              g_run_max === 100);
        check("TC22 shortest TX_EN run == 64 (no truncated frame)",
              g_run_min === 64);
        check("TC22 TX_ER never high while TX_EN low (Table 35-1)",
              inv_gmii_ce === 0);
        gmii_en = 1'b0;
        $display("        the writer stalled 4-7 cycles INSIDE every frame.");
        $display("        underruns=%0d   TX_EN runs: min=%0d max=%0d",
                 g_unders, g_run_min, g_run_max);
        $display("");

        $display("[TC24] Commit-to-visible latency is bounded and repeatable");
        clear_all;
        a_ready = 1'b0;
        wr_a(8, 8'h5E, 0, 1'b1);
        t0 = $time;
        @(posedge a_avail);
        lat1 = $time - t0;
        @(negedge clk_b) a_ready = 1'b1;
        w_b(60);
        clear_all;
        a_ready = 1'b0;
        wr_a(8, 8'h6E, 0, 1'b1);
        t0 = $time;
        @(posedge a_avail);
        lat2 = $time - t0;
        @(negedge clk_b) a_ready = 1'b1;
        w_b(60);
        dlat = (lat1 > lat2) ? (lat1 - lat2) : (lat2 - lat1);
        check("TC24 latency bounded below 6 read clocks",
              (lat1 < (6 * P_B)) && (lat2 < (6 * P_B)));
        check("TC24 spread across frames within 2 read clocks",
              dlat <= (2 * P_B));
        $display("        tlast -> frame_avail : %0d ns and %0d ns (2-FF sync)",
                 lat1, lat2);
        $display("");

        $display("[TC25] Randomised soak - 30 frames, random length/gap/stall");
        a_rand_rdy = 1'b1;
        vbad = 0;
        for (k = 0; k < 30; k = k + 1) begin : soak
            integer flen;
            integer fgap;
            flen = 1 + ({$random(seed)} % 45);
            fgap = {$random(seed)} % 3;
            clear_all;
            wr_a(flen, 8'h13 * (k + 1), fgap, 1'b1);
            w_b(30 + (flen * 8));
            if (a_n      !== flen) vbad = vbad + 1;
            if (a_frames !== 1)    vbad = vbad + 1;
            vfy_a(0, flen, 8'h13 * (k + 1));
        end
        a_rand_rdy = 1'b0;
        @(negedge clk_b) a_ready = 1'b1;
        w_b(20);
        check("TC25 all 30 random frames correct - length, framing and data",
              vbad === 0);
        check("TC25 no drops during the soak", a_drops === 0);
        $display("");

        $display("[TC26] Standing invariants over the entire run");
        gray_total;
        check("TC26 offered data never mutated while ready_in was low",
              inv_hold === 0);
        check("TC26 valid_out never high without frame_avail_out",
              inv_valid_avail === 0);
        check("TC26 tready never low while dropping (no drain deadlock)",
              inv_drop_rdy === 0);
        check("TC26 GMII TX_ER never high while TX_EN low, whole run",
              inv_gmii_ce === 0);
        check("TC26 every crossing vector stayed Gray for the whole run",
              gray_viol === 0);
        $display("");

        $display("=========================================================");
        $display(" RESULT : %0d passed, %0d failed, %0d total",
                 pass_n, fail_n, pass_n + fail_n);
        if (fail_n == 0)
            $display(" tx_fifo_advanced_tb : ALL CHECKS PASS");
        else
            $display(" tx_fifo_advanced_tb : *** FAILURES ***");
        $display("=========================================================");
        $finish;
    end

    initial begin
        #4000000;
        $display("*** WATCHDOG TIMEOUT - simulation did not finish ***");
        $finish;
    end

endmodule


`default_nettype wire
