`timescale 1ns / 1ps

module testmult;

    function [31:0] log2;
        input reg [31:0] value;
    	begin
        	value = value - 1;
        	for (log2 = 0; value > 0; log2 = log2 + 1)
            begin
            	value = value >> 1;
            end
      	end
    endfunction

    parameter N = 32;
    parameter Bs = log2(N);
    parameter es = 2;

    reg [N-1:0] in1, in2;
    reg start;
    wire [N-1:0] out;
    wire done;

    reg clk;


    // Instantiate the Unit Under Test (UUT)
    posit_adder_4 #(
        .N(N),
        .es(es)
    ) uut (
        .aclk(clk),
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
        in1 = 32'h2CCCCCCD; // 0.20000000018626451
        in2 = 32'h2CCCCCCD; // 0.20000000018626451
	end

    always #5
    begin
        clk = ~clk;
    end
endmodule
