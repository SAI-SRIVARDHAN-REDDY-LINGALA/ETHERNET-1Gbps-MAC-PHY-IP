// tx_fcs_advanced_tb - Advanced TX FCS tests.

`timescale 1ns / 1ps

module tx_fcs_advanced_tb;

    reg         clk, rst_n, init, data_valid;
    reg  [7:0]  data_in;
    wire [31:0] fcs_out;
    wire        fcs_valid;

    tx_fcs dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .init       (init),
        .data_valid (data_valid),
        .data_in    (data_in),
        .fcs_out    (fcs_out),
        .fcs_valid  (fcs_valid)
    );

    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    function [31:0] golden_crc32;
        input [511:0] msg;
        input integer len;
        reg   [31:0] c;
        reg   [7:0]  b;
        integer i, j;
        begin
            c = 32'hFFFFFFFF;
            for (i = 0; i < len; i = i + 1) begin
                b = msg[8*(len-1-i) +: 8];
                c = c ^ b;
                for (j = 0; j < 8; j = j + 1) begin
                    if (c[0])
                        c = (c >> 1) ^ 32'hEDB88320;
                    else
                        c = c >> 1;
                end
            end
            golden_crc32 = ~c;
        end
    endfunction

    reg [7:0] msg [0:63];
    integer   msg_len, k;
    reg       pause_mode;

    task run_frame;
        begin
            data_valid = 0;
            init = 1;
            $display("  [init]  pulsing init for 1 cycle -> CRC register reloaded to 0xFFFFFFFF");
            @(posedge clk); #1;
            init = 0;

            for (k = 0; k < msg_len; k = k + 1) begin
                if (pause_mode && (k == msg_len/2)) begin
                    $display("  [pause] backpressure: holding data_valid=0 for 3 idle cycles (byte %0d)", k);
                    data_valid = 0;
                    @(posedge clk); #1;
                    @(posedge clk); #1;
                    @(posedge clk); #1;
                end
                data_in    = msg[k];
                data_valid = 1;
                $display("  [byte]  k=%0d  data_in=0x%02x  data_valid=1", k, msg[k]);
                @(posedge clk); #1;
            end
            data_valid = 0;
            $display("  [end]   data_valid deasserted -- last byte was byte %0d, waiting for falling-edge strobe", msg_len-1);
            @(posedge clk); #1;
            $display("  [strobe] fcs_valid=%b  fcs_out=0x%08x", fcs_valid, fcs_out);
        end
    endtask

    task check_result;
        input [255:0] name;
        reg [31:0] expected;
        begin
            expected = golden_crc32(packed_msg(msg_len), msg_len);
            if (fcs_out === expected && fcs_valid === 1'b1) begin
                $display("%0s -> fcs_out=0x%08x  ** PASS **", name, fcs_out);
                pass_count = pass_count + 1;
            end else begin
                $display("%0s -> fcs_out=0x%08x fcs_valid=%b  ** FAIL ** (expected 0x%08x)",
                          name, fcs_out, fcs_valid, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    function [511:0] packed_msg;
        input integer len;
        integer i;
        begin
            packed_msg = 0;
            for (i = 0; i < len; i = i + 1)
                packed_msg[8*(len-1-i) +: 8] = msg[i];
        end
    endfunction

    integer t;

    initial begin
        clk = 0; rst_n = 0; init = 0; data_valid = 0; data_in = 0; pause_mode = 0;
        $display("====================================================");
        $display("Applying initial reset (rst_n=0)");
        @(posedge clk); #1;
        rst_n = 1;
        $display("Releasing reset (rst_n=1)");
        @(posedge clk); #1;

        $display("\n---- TC1: known-vector \"123456789\" ----");
        msg[0]="1";msg[1]="2";msg[2]="3";msg[3]="4";msg[4]="5";
        msg[5]="6";msg[6]="7";msg[7]="8";msg[8]="9";
        msg_len = 9; pause_mode = 0;
        run_frame;
        check_result("TC1 known-vector \"123456789\"       ");

        $display("\n---- TC2: single-byte frame (minimum length edge case) ----");
        msg[0] = 8'hA5;
        msg_len = 1; pause_mode = 0;
        run_frame;
        check_result("TC2 single-byte frame               ");

        $display("\n---- TC3a: back-to-back frame #1 (\"ABC\") ----");
        msg[0]="A"; msg[1]="B"; msg[2]="C";
        msg_len = 3; pause_mode = 0;
        run_frame;
        check_result("TC3a back-to-back frame #1 (\"ABC\")   ");

        $display("\n---- TC3b: back-to-back frame #2 (\"XYZ!\"), zero gap after TC3a ----");
        msg[0]="X"; msg[1]="Y"; msg[2]="Z"; msg[3]="!";
        msg_len = 4; pause_mode = 0;
        run_frame;
        check_result("TC3b back-to-back frame #2 (\"XYZ!\")  ");

        $display("\n---- TC4: backpressure mid-frame (same msg as TC1, must match TC1 result) ----");
        msg[0]="1";msg[1]="2";msg[2]="3";msg[3]="4";msg[4]="5";
        msg[5]="6";msg[6]="7";msg[7]="8";msg[8]="9";
        msg_len = 9; pause_mode = 1;
        run_frame;
        check_result("TC4 backpressure mid-frame (same msg)");

        $display("\n---- TC5: mid-frame reset recovery ----");
        msg[0]="D"; msg[1]="E"; msg[2]="A"; msg[3]="D";
        msg_len = 4; pause_mode = 0;

        data_valid = 0; init = 1;
        $display("  [init]  starting a frame we intend to abandon...");
        @(posedge clk); #1; init = 0;
        data_in = msg[0]; data_valid = 1;
        $display("  [byte]  fed 1 byte (0x%02x) into the doomed frame", msg[0]);
        @(posedge clk); #1;
        data_in = msg[1];
        $display("  [byte]  fed 2nd byte (0x%02x), now glitching reset...", msg[1]);
        @(posedge clk); #1;
        rst_n = 0;
        data_valid = 0;
        $display("  [reset] rst_n=0 asserted mid-frame -- CRC register forced back to 0xFFFFFFFF");
        @(posedge clk); #1;
        rst_n = 1;
        $display("  [reset] rst_n=1 released -- now running a clean frame to prove recovery");
        @(posedge clk); #1;

        msg[0]="O"; msg[1]="K"; msg_len = 2; pause_mode = 0;
        run_frame;
        check_result("TC5 clean frame after mid-frame reset");

        $display("\n---- TC6: 10x random frames, random length 1-30 bytes ----");
        for (t = 0; t < 10; t = t + 1) begin
            msg_len = 1 + ($random % 30);
            if (msg_len < 1) msg_len = 1;
            for (k = 0; k < msg_len; k = k + 1)
                msg[k] = $random;
            pause_mode = (t % 2);
            $display("\n  -- random frame %0d/10, length=%0d bytes, backpressure=%0d --", t+1, msg_len, pause_mode);
            run_frame;
            check_result("TC6 random frame                    ");
        end

        $display("\n====================================================");
        $display("TOTAL: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("*** %0d TEST(S) FAILED ***", fail_count);
        $finish;
    end

        initial begin
            $dumpfile("tx_fcs_tb.vcd");
            $dumpvars(0, tx_fcs_advanced_tb);
        end

endmodule

