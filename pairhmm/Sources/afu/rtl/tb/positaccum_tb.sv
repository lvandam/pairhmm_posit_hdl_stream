`timescale 1ns / 1ps

module positaccum_tb;
    parameter N = 32;
    parameter es = 2;

    reg [N-1:0] in;
    reg start;
    wire [N-1:0] out;
    wire done;
    reg clk;

    // Instantiate the Unit Under Test (UUT)
    positaccumulator uut (
        .clk(clk),
        .in(in),
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

        #50 in = 32'b01000000000000000000000000000000;
        #50 in = 32'b01001010000000000000000000000000;

	end

    always #5
    begin
        clk = ~clk;
    end
endmodule
