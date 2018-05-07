`timescale 1ns / 1ps

module positadd_tb;
    parameter N = 32;
    parameter es = 2;

    reg [N-1:0] in1, in2;
    reg start;
    wire [N-1:0] out;
    wire done;
    reg clk;

    // Instantiate the Unit Under Test (UUT)
    positadd uut (
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

        in1 = 32'b01100110010100110001011101001000;
        in2 = 32'b01010110000110110110110010000110;
        // 0 110 01 11001101001100111000010000

        #200
        in1 = 32'b01011010110110011010000001010011;
        in2 = 32'b10110011011010101000110010110110;
        // 0 10 10 111011010001000011100000001

        #200
        in1 = 32'b11111101111011110101100101010110;
        in2 = 32'b10110001111101101000010111100001;

	end

    always #5
    begin
        clk = ~clk;
    end
endmodule
