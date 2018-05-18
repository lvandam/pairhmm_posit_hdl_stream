`timescale 1ns / 1ps

module positaccum_8_tb;
    parameter N = 32;
    parameter es = 2;

    reg [N-1:0] in;
    reg rst;
    reg start;
    wire [N-1:0] out;
    wire done;
    reg clk;

    // Instantiate the Unit Under Test (UUT)
    positaccum_8 #(
        .OUT_STAGES(8)
    ) uut (
        .clk(clk),
        .rst(rst),
        .in1(in),
        .start(start),
        .result(out),
        .inf(inf),
        .zero(zero),
        .done(done)
    );

    reg [15:0] i;

	initial
    begin
		// Initialize Inputs
		clk = 0;
        rst = 0;
		in = 0;
		start = 0;
        #10 rst = 1;
        #10 rst = 0;

        #100 start = 1; in = 32'b01000000000000000000000000000000;
        // #100 i = 0; start = 1; in = 32'b00011100000000010101000000100001;
        // #60 in = 32'b00000010000000010101000000100001;
	end

    always @(posedge clk)
    begin
        if(i/16 == 5000)
        begin
            $display("%b", out);
            $finish;
        end
        else
        begin
            i = i + 1;
        end
    end

    always #5
    begin
        clk = ~clk;
    end
endmodule
