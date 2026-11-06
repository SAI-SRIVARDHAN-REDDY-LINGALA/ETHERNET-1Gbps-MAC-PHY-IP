// tx_protocol_checker - Test-only whitebox protocol checker.

`timescale 1ns / 1ps
`default_nettype none

module tx_protocol_checker #(
    parameter integer PREAMBLE_OCTETS = 7,
    parameter integer MIN_FRAMED      = 64,
    parameter integer MAX_FRAMED      = 1518,
    parameter integer MIN_IPG_BITS    = 96
)(
    input  wire        tx_clk,
    input  wire        tx_rst_n,
    input  wire        speed_select,
    input  wire [7:0]  gmii_txd,
    input  wire        gmii_tx_en,
    input  wire        gmii_tx_er,
    input  wire        check_en,
    output reg  [15:0] err_count,
    output reg  [15:0] frame_count
);

    function [31:0] crc_next;
        input [7:0]  d;
        input [31:0] c;
        reg   [31:0] t;
        integer      i;
        begin
            t = c ^ {24'h000000, d};
            for (i = 0; i < 8; i = i + 1) begin
                if (t[0]) t = (t >> 1) ^ 32'hEDB88320;
                else      t = (t >> 1);
            end
            crc_next = t;
        end
    endfunction

    localparam [31:0] RESIDUE = 32'hDEBB20E3;

    reg  [7:0]  frm [0:2047];
    integer     frm_len_q;
    integer     ipg_bits_q;
    integer     min_ipg_q;

    reg         en_d;
    reg         nib;
    reg  [3:0]  lo_nib;
    reg  [7:0]  oct;
    reg         got_oct;
    reg         mode_q;
    reg         seen_burst;
    reg  [31:0] crc;
    integer     oi;
    integer     framed;
    integer     idle_cyc;
    integer     ipg_bits;

    task chk_fail;
        input [8*72:1] msg;
        begin
            err_count = err_count + 16'd1;
            $display("  ** CHK FAIL ** t=%0t : %0s", $time, msg);
        end
    endtask

    initial begin
        err_count   = 16'd0;
        frame_count = 16'd0;
        frm_len_q   = 0;
        ipg_bits_q  = 0;
        min_ipg_q   = 1000000;
        en_d        = 1'b0;
        nib         = 1'b0;
        lo_nib      = 4'h0;
        oct         = 8'h00;
        got_oct     = 1'b0;
        mode_q      = 1'b1;
        seen_burst  = 1'b0;
        crc         = 32'hFFFFFFFF;
        oi          = 0;
        framed      = 0;
        idle_cyc    = 0;
        ipg_bits    = 0;
    end

    always @(posedge tx_clk) begin

        if (!tx_rst_n) begin

            if (check_en && gmii_tx_en)
                chk_fail("W8: TX_EN asserted while tx_rst_n is low");

            en_d       = 1'b0;
            nib        = 1'b0;
            oi         = 0;
            framed     = 0;
            idle_cyc   = 0;
            seen_burst = 1'b0;

        end else begin

            if (check_en && (!gmii_tx_en) && gmii_tx_er)
                chk_fail("W1: TX_ER high with TX_EN low = CARRIER EXTEND (Tbl 35-1)");

            if (gmii_tx_en) begin

                if (!en_d) begin

                    if (seen_burst) begin
                        ipg_bits = idle_cyc * (mode_q ? 8 : 4);
                        if (check_en && (ipg_bits < MIN_IPG_BITS))
                            chk_fail("W5: inter-frame gap shorter than 96 bit times");
                        if (ipg_bits < min_ipg_q) min_ipg_q = ipg_bits;
                    end else begin
                        ipg_bits = -1;
                    end
                    ipg_bits_q = ipg_bits;

                    mode_q = speed_select;
                    oi     = 0;
                    nib    = 1'b0;
                    framed = 0;
                    crc    = 32'hFFFFFFFF;
                end

                if (check_en && (!mode_q) && (gmii_txd[7:4] != 4'h0))
                    chk_fail("W6: TXD[7:4] nonzero in MII mode (clause 22.2.3)");

                got_oct = 1'b0;
                if (mode_q) begin
                    oct     = gmii_txd;
                    got_oct = 1'b1;
                end else begin
                    if (!nib) begin
                        lo_nib = gmii_txd[3:0];
                        nib    = 1'b1;
                    end else begin
                        oct     = {gmii_txd[3:0], lo_nib};
                        nib     = 1'b0;
                        got_oct = 1'b1;
                    end
                end

                if (got_oct) begin

                    if (oi < PREAMBLE_OCTETS) begin
                        if (check_en && (oct !== 8'h55))
                            chk_fail("W3: preamble octet is not 0x55 (clause 3.2.1)");
                    end else if (oi == PREAMBLE_OCTETS) begin
                        if (check_en && (oct !== 8'hD5))
                            chk_fail("W3: SFD octet is not 0xD5 (clause 3.2.2)");
                    end else begin

                        if (framed < 2048) frm[framed] = oct;
                        crc    = crc_next(oct, crc);
                        framed = framed + 1;
                    end
                    oi = oi + 1;
                end

                idle_cyc = 0;

            end else begin

                if (en_d) begin
                    frm_len_q = framed;

                    if (check_en && (!mode_q) && nib)
                        chk_fail("W2: MII burst ended mid-octet (odd nibble count)");

                    if (check_en && (framed < MIN_FRAMED))
                        chk_fail("W4: framed length below the 64 octet minimum");
                    if (check_en && (framed > MAX_FRAMED))
                        chk_fail("W4: framed length above maxUntaggedFrameSize 1518");

                    if (check_en && (crc !== RESIDUE)) begin
                        $display("  ** CHK FAIL ** t=%0t : W7: FCS residue is %08x, must be %08x",
                                 $time, crc, RESIDUE);
                        err_count = err_count + 16'd1;
                    end

                    frame_count = frame_count + 16'd1;
                    seen_burst  = 1'b1;
                    nib         = 1'b0;
                end

                idle_cyc = idle_cyc + 1;
            end

            en_d = gmii_tx_en;
        end
    end

endmodule

`default_nettype wire

