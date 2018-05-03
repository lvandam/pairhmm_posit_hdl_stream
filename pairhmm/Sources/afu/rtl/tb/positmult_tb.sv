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
        in1 = 32'b00000000000111001100110110010101;
        in2 = 32'b00000000000111001100110110010101;
        // 00000000000000000000110011100010

        #200
        in1 = 32'b00000000001101100100111101100001;
        in2 = 32'b00000000001101100100111101100001;
        // 00000000000000000010110011001100

	end

    always #5
    begin
        clk = ~clk;
    end
endmodule
