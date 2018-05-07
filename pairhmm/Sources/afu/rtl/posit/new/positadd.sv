// Laurens van Dam
// Delft University of Technology
// May 2018

`timescale 1ns / 1ps
`default_nettype wire

`include "posit_defines.sv"

import posit_defines::*;

module positadd (clk, in1, in2, start, result, inf, zero, done);

    input wire clk, start;
    input wire [31:0] in1, in2;
    output wire [31:0] result;
    output wire inf, zero, done;

    value a, b;
    value_sum sum;

    // Extract posit characteristics, among others the regime & exponent scales
    posit_extract a_extract (
        .in(in1),
        .out(a)
    );

    posit_extract b_extract (
        .in(in2),
        .out(b)
    );

    value low, hi;

    assign sum.zero = a.zero & b.zero;
    assign sum.inf = a.inf | b.inf;

    logic a_lt_b; // A larger than B
    assign a_lt_b = ((a.scale < b.scale) || ((a.scale == b.scale) && (a.fraction < b.fraction))); // TODO or: r0_xin1[N-2:0] >= r0_xin2[N-2:0] ? '1 : '0;
    assign operation = a.sign ~^ b.sign; // 1 = equal signs = add, 0 = unequal signs = subtract
    assign low = a_lt_b ? a : b;
    assign hi = a_lt_b ? b : a;

    // Difference in scales (regime and exponent)
    logic unsigned [7:0] scale_diff;
    assign scale_diff = hi.scale - low.scale;

    // Amount the smaller input has to be shifted (everything of the scale difference that the regime cannot cover)
    logic unsigned [7:0] equalize_shift_amount;
    assign equalize_shift_amount = scale_diff % (2 << ES);

    // Shift smaller magnitude based on scale difference
    logic [ABITS-1:0] low_fraction_shifted; // TODO We lose some bits here
    DSR_right_N_S #(
        .N(ABITS),
        .S(8)
    ) scale_matching_shift (
        .a({1'b1, low.fraction, {3{1'b0}}}),
        .b(equalize_shift_amount), // Shift to right by scale difference
        .c(low_fraction_shifted)
    );

    // Add the fractions
    logic unsigned [ABITS:0] fraction_sum_raw, fraction_sum_raw_add, fraction_sum_raw_sub;

    assign fraction_sum_raw_add = {1'b1, hi.fraction, {3{1'b0}}} + low_fraction_shifted;
    assign fraction_sum_raw_sub = {1'b1, hi.fraction, {3{1'b0}}} - low_fraction_shifted;
    assign fraction_sum_raw = operation ? fraction_sum_raw_add : fraction_sum_raw_sub;

    // Result normalization: shift until normalized (and fix the sign)
    logic signed [8:0] scale_sum;
    assign scale_sum = fraction_sum_raw[ABITS] ? (hi.scale - 1) : hi.scale;

    // TODO
    // if(shift >= ABITS) {
    //     set sum to 0
    // }

    // Normalize the sum output (shift left)

    logic [29:0] fraction_sum_normalized;
    assign fraction_sum_normalized = fraction_sum_raw[ABITS] ? fraction_sum_raw[ABITS-1:1] : fraction_sum_raw[ABITS-2:0]; // TODO overflow 2 MSB's are 00

    // assign scale_sum = (~fraction_sum_overflow) ? hi.scale : hi.scale + 1;

    assign sum.sign = hi.sign;
    assign sum.scale = scale_sum;










    // PACK INTO POSIT
    logic [ES-1:0] result_exponent;
    assign result_exponent = sum.scale % (2 << ES);

    logic [2*NBITS-1:0] regime_exp_fraction;
    assign regime_exp_fraction = { {NBITS-1{~sum.scale[8]}}, // Regime leading bits
                            sum.scale[8], // Regime terminating bit
                            result_exponent, // Exponent
                            fraction_sum_normalized[29:0]}; // Fraction

    logic [6:0] regime_shift_amount;
    assign regime_shift_amount = (sum.scale[8] == 0) ? 1 + (sum.scale >> ES) : -(sum.scale >> ES);

    logic [2*NBITS-1:0] exp_fraction_shifted_for_regime;
    DSR_right_N_S #(
        .N(2*NBITS),
        .S(7)
    ) shift_in_regime (
        .a(regime_exp_fraction), // exponent + fraction bits
        .b(regime_shift_amount), // Shift to right by regime value (clip at maximum number of bits)
        .c(exp_fraction_shifted_for_regime)
    );

    // TODO Inward projection
    // Determine result (without sign), either a full regime part (inward projection) or the unsigned regime+exp+fraction
    logic [NBITS-2:0] result_no_sign;
    assign result_no_sign = exp_fraction_shifted_for_regime[NBITS:2];

    // TODO sticky bit
    logic [NBITS-2:0] result_no_sign_rounded;
    assign result_no_sign_rounded = result_no_sign;

    // In case the product is negative, take 2's complement of everything but the sign
    logic [NBITS-2:0] signed_result_no_sign;
    assign signed_result_no_sign = sum.sign ? -result_no_sign_rounded[NBITS-2:0] : result_no_sign_rounded[NBITS-2:0];



    // Final output
    assign result = (sum.zero | sum.inf) ? {sum.inf, {NBITS-1{1'b0}}} : {sum.sign, signed_result_no_sign[NBITS-2:0]};
    assign inf = sum.inf;
    assign zero = ~sum.inf & sum.zero;
    assign done = start;


endmodule