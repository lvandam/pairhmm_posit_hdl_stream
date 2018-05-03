`timescale 1ns / 1ps

module positmult_tb;
    parameter N = 32;
    parameter es = 2;

    reg [N-1:0] in1, in2;
    reg start;
    wire [N-1:0] out;
    wire done;
    reg clk;

    // Instantiate the Unit Under Test (UUT)
    positmult uut (
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
        in1 = 32'b11001110101010100000011101011110;
        in2 = 32'b10011011100101010100000110011100;
        // 01011010010011110001101100111100

        #200
        in1 = 32'b01011010110110011010000001010011;
        in2 = 32'b10110011011010101000110010110110;
        // 10011011101110111011011101110111

        #200
        in1 = 32'b11000010010010011000100100000011;
        in2 = 32'b00000001101010010011011010001100;
        // 11111110011001011101001111010011

	end

    always #5
    begin
        clk = ~clk;
    end
endmodule
