// tx_padding_tb - Comprehensive padding tests.

`timescale 1ns / 1ps

module tx_padding_tb;

    reg        tx_clk, rst_n;
    reg        valid_in, sof_in, eof_in;
    reg  [7:0] data_in;
    wire       ready_in;

    wire       valid_out, sof_out, eof_out;
    wire [7:0] data_out;
    reg        ready_out;

    tx_padding #(.MIN_FRAME_LEN(60)) dut (
        .tx_clk    (tx_clk),
        .rst_n     (rst_n),
        .data_in   (data_in),
        .valid_in  (valid_in),
        .sof_in    (sof_in),
        .eof_in    (eof_in),
        .ready_in  (ready_in),
        .data_out  (data_out),
        .valid_out (valid_out),
        .sof_out   (sof_out),
        .eof_out   (eof_out),
        .ready_out (ready_out)
    );

    always #5 tx_clk = ~tx_clk;

    integer pass_count     = 0;
    integer fail_count     = 0;
    integer out_count      = 0;
    integer pad_count      = 0;
    integer k;
    integer timeout;
    integer timed_out_flag;

    task send_frame;
        input integer frame_len;
        input integer gap_mode;
        begin
            for (k = 0; k < frame_len; k = k + 1) begin
                if (gap_mode && (k == frame_len/2)) begin
                    valid_in = 0;
                    @(posedge tx_clk); #1;
                    @(posedge tx_clk); #1;
                    @(posedge tx_clk); #1;
                end
                data_in  = 8'h10 + (k % 200);
                sof_in   = (k == 0);
                eof_in   = (k == frame_len-1);
                valid_in = 1;
                timeout = 0;
                while (!ready_in && timeout < 200) begin
                    @(posedge tx_clk); #1;
                    timeout = timeout + 1;
                end
                @(posedge tx_clk); #1;
            end
            valid_in = 0; sof_in = 0; eof_in = 0;
        end
    endtask

    task inject_backpressure;
        input integer trigger_at;
        input integer stall_cycles;
        integer i;
        begin
            @(posedge tx_clk); #1;
            while (out_count < trigger_at) begin
                @(posedge tx_clk); #1;
            end
            ready_out = 0;
            for (i = 0; i < stall_cycles; i = i + 1) begin
                @(posedge tx_clk); #1;
            end
            ready_out = 1;
        end
    endtask

    task capture_output_frame;
        begin
            out_count      = 0;
            pad_count      = 0;
            timed_out_flag = 0;
            timeout        = 0;

            while (!(valid_out && sof_out && ready_out) && timeout < 2000) begin
                @(posedge tx_clk); #1;
                timeout = timeout + 1;
            end
            if (timeout >= 2000) timed_out_flag = 1;

            if (valid_out && ready_out) begin
                out_count = out_count + 1;
                if (data_out == 8'h00) pad_count = pad_count + 1;
            end

            while (!(eof_out && valid_out && ready_out) && timeout < 2000) begin
                @(posedge tx_clk); #1;
                timeout = timeout + 1;

                if (valid_out && ready_out) begin
                    out_count = out_count + 1;
                    if (data_out == 8'h00) pad_count = pad_count + 1;
                end
            end
            if (timeout >= 2000) timed_out_flag = 1;
        end
    endtask

    task check;
        input [255:0] name;
        input integer expected_total;
        begin
            if (timed_out_flag) begin
                $display("%0s -> ** FAIL ** (TIMED OUT waiting for sof_out/eof_out -- frame boundary never seen)", name);
                fail_count = fail_count + 1;
            end else if (out_count === expected_total) begin
                $display("%0s -> total_bytes=%0d (pad_bytes=%0d)  ** PASS **",
                          name, out_count, pad_count);
                pass_count = pass_count + 1;
            end else begin
                $display("%0s -> total_bytes=%0d (pad_bytes=%0d)  ** FAIL ** (expected %0d)",
                          name, out_count, pad_count, expected_total);
                fail_count = fail_count + 1;
            end
        end
    endtask

    integer t, rand_len, expected;

    initial begin
        tx_clk = 0; rst_n = 0; valid_in = 0; sof_in = 0; eof_in = 0; data_in = 0;
        ready_out = 1;
        @(posedge tx_clk); #1;
        rst_n = 1;
        @(posedge tx_clk); #1;

        fork
            send_frame(10, 0);
            capture_output_frame;
        join
        check("TC1  undersized 10-byte frame -> padded to 60       ", 60);

        fork
            send_frame(60, 0);
            capture_output_frame;
        join
        check("TC2  exact 60-byte frame -> no padding needed       ", 60);

        fork
            send_frame(100, 0);
            capture_output_frame;
        join
        check("TC3  100-byte frame -> passes through unpadded      ", 100);

        fork
            send_frame(1, 0);
            capture_output_frame;
        join
        check("TC4  1-byte frame (sof+eof same cycle) -> padded    ", 60);

        fork
            send_frame(59, 0);
            capture_output_frame;
        join
        check("TC5  boundary 59-byte frame -> padded to 60 (1 pad) ", 60);

        fork
            send_frame(61, 0);
            capture_output_frame;
        join
        check("TC6  boundary 61-byte frame -> no padding           ", 61);

        fork
            send_frame(70, 0);
            begin
                capture_output_frame;
            end
            inject_backpressure(20, 8);
        join
        check("TC7  backpressure mid-DATA state (70B, no pad)      ", 70);

        fork
            send_frame(10, 0);
            begin
                capture_output_frame;
            end
            inject_backpressure(15, 8);
        join
        check("TC8  backpressure mid-PADDING state (10B -> 60)     ", 60);

        fork
            send_frame(20, 1);
            capture_output_frame;
        join
        check("TC9  sender pauses valid_in mid-frame (20B -> 60)   ", 60);

        fork
            send_frame(10, 0);
            capture_output_frame;
        join
        check("TC10a back-to-back frame #1 (10B -> 60)             ", 60);
        fork
            send_frame(15, 0);
            capture_output_frame;
        join
        check("TC10b back-to-back frame #2, zero gap (15B -> 60)   ", 60);

        valid_in = 0; sof_in = 0; eof_in = 0;
        data_in = 8'hAA; sof_in = 1; valid_in = 1;
        @(posedge tx_clk); #1;
        sof_in = 0; data_in = 8'hBB;
        @(posedge tx_clk); #1;
        rst_n = 0;
        valid_in = 0;
        @(posedge tx_clk); #1;
        rst_n = 1;
        @(posedge tx_clk); #1;
        fork
            send_frame(5, 0);
            capture_output_frame;
        join
        check("TC11 clean frame after mid-frame reset (5B -> 60)   ", 60);

        fork
            send_frame(1518, 0);
            capture_output_frame;
        join
        check("TC12 max-size 1518-byte frame -> unpadded           ", 1518);

        for (t = 0; t < 15; t = t + 1) begin
            rand_len = 1 + ($random % 200);
            if (rand_len < 1) rand_len = -rand_len + 1;
            expected = (rand_len < 60) ? 60 : rand_len;
            fork
                send_frame(rand_len, (t % 2));
                capture_output_frame;
            join
            $display("  -- random frame %0d/15: len=%0d, gap_mode=%0d --", t+1, rand_len, t%2);
            check("TC13 random frame                                  ", expected);
        end

        $display("--------------------------------------------------");
        $display("TOTAL: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("*** %0d TEST(S) FAILED ***", fail_count);
        $finish;
    end

    initial begin
        $dumpfile("tx_padding_tb.vcd");
        $dumpvars(0, tx_padding_tb);
    end

endmodule

