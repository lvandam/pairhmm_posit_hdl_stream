`timescale 1ns / 1ps

module positadd_tb;
    parameter N = 32;
    parameter es = 3;

    reg [N-1:0] in1, in2;
    reg start;
    wire [N-1:0] out;
    wire done;
    reg clk;

    // Instantiate the Unit Under Test (UUT)
    positadd_4_es3 uut (
        .clk(clk),
        .in1(in1),
        .in2(in2),
        .start(start),
        .result(out),
        .inf(inf),
        .zero(zero),
        .done(done)
    );

	initial
    begin
		// Initialize Inputs
		in1 = 0;
		in2 = 0;
		clk = 0;
		start = 1;

        in1 = 32'b10101101101110010100101000000111; // 01 011 = -5
        in2 = 32'b00011110011111001001100001100100; // 01 101 = -3
        // 1 10 01101000000111001101000010000
        // = -5


        // 1 01 100 10111111000110010111110000


        // 01 100 = -4

	end

    always #5
    begin
        clk = ~clk;
    end
endmodule
