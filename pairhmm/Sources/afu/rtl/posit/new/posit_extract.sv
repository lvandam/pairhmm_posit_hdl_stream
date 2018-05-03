`timescale 1ns / 1ps
`default_nettype wire

`include "posit_defines.sv"

import posit_defines::*;

module posit_extract (input wire [NBITS-1:0] in, output value out);

    logic [6:0] regime_scale;
    logic [4:0] regime, k0, k1;
    logic [ES-1:0] exponent_scale;
    logic [NBITS-1:0] exp_fraction;
    logic [4:0] regime_width;
    logic [31:0] in_unsigned;

    // Check if part without sign is non-zero (to determine inf and zero cases)
    logic posit_nonzero_without_sign;
    assign posit_nonzero_without_sign = |in[NBITS-2:0];

    // TODO Implement this
    // special case handling (inf, zero) for both inputs
    assign out.zero = ~(in[NBITS-1] | posit_nonzero_without_sign);
    assign out.inf = in[NBITS-1] & (~posit_nonzero_without_sign);

    assign out.sign = in[NBITS-1];

    assign in_unsigned = out.sign ? -in : in;

    LOD_N #(
        .N(NBITS)
    ) xinst_k0(
        .in({in_unsigned[NBITS-2:0], 1'b0}),
        .out(k0)
    );

    LZD_N #(
        .N(NBITS)
    ) xinst_k1(
        .in({in_unsigned[NBITS-3:0], 2'b0}),
        .out(k1)
    );

    // Determine absolute regime value depending on leading 0 or 1 regime bit
    assign regime = in_unsigned[NBITS-2] ? k1 : k0;

    assign regime_scale = in_unsigned[NBITS-2] ? (regime << ES) : -(regime << ES); // Negative regime? Make the regime scale negative
    assign regime_width = in_unsigned[NBITS-2] ? (k1 + 1) : k0; // Number of bits taken by regime

    DSR_left_N_S #(
        .N(32),
        .S(5)
    ) ls (
        .a({in_unsigned[NBITS-3:0], 2'b0}),
        .b(regime_width),
        .c(exp_fraction)
    );

    assign out.exponent = exp_fraction[NBITS-1:NBITS-ES];
    assign out.fraction = exp_fraction[NBITS-ES-1:3]; // TODO is [:3] correct?

    // Scale = k*(2^es) + 2^exp
    assign out.scale = regime_scale + out.exponent;


endmodule
