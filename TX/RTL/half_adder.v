// Half Adder Module using Dataflow Modeling
module half_adder (
    input  wire a,     // Input bit A
    input  wire b,     // Input bit B
    output wire sum,   // Sum output bit
    output wire carry  // Carry output bit
);

    // Sum is calculated using the bitwise XOR operator (^)
    assign sum = a ^ b; 
    
    // Carry is calculated using the bitwise AND operator (&)
    assign carry = a & b; 

endmodule
