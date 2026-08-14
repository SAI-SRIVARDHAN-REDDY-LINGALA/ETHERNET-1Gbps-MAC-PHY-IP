`timescale 1ns / 1ps

module half_adder_tb;

    // Inputs
    reg a;
    reg b;

    // Outputs
    wire sum;
    wire carry;

    // DUT Instantiation
    half_adder uut (
        .a(a),
        .b(b),
        .sum(sum),
        .carry(carry)
    );

    // VCD Dump
    initial begin
        $dumpfile("sim/half_adder.vcd");
        $dumpvars(0, half_adder_tb);
    end

    // Test Stimulus
    initial begin

        $display("Time\tA\tB\tSum\tCarry");
        $monitor("%0t\t%b\t%b\t%b\t%b",
                  $time, a, b, sum, carry);

        a = 0; b = 0; #10;
        a = 0; b = 1; #10;
        a = 1; b = 0; #10;
        a = 1; b = 1; #10;

        $finish;
    end

endmodule