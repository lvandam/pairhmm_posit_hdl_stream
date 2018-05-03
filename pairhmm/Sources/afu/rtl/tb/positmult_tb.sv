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

        // #200
        // in1 = 32'b00000000000000000010000010111110;
        // in2 = 32'b00000000000000000010000010111110;
        // // 00000000000000000000000000000001
        //
        // #200
        // in1 = 32'b01110100000000000010000010111110;
        // in2 = 32'b01110101000000000000000010111110;
        // // 00000000000000000000000000000001

	end

    always #5
    begin
        clk = ~clk;
    end
endmodule
