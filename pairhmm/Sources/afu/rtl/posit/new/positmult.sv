`timescale 1ns / 1ps
`default_nettype wire

`include "posit_defines.sv"

import posit_defines::*;

module positmult (clk, in1, in2, start, result, inf, zero, done);

    input wire clk, start;
    input wire [31:0] in1, in2;
    output wire [31:0] result;
    output wire inf, zero, done;

    value a, b;
    value_product product;

    // Extract posit characteristics, among others the regime & exponent scales
    posit_extract a_extract (
        .in(in1),
        .out(a)
    );

    posit_extract b_extract (
        .in(in2),
        .out(b)
    );

    // TODO MULTIPLY THE TWO INPUTS (module_multiply function)
    // TODO implement this (mux?)
    // if (lhs.isInfinite() || rhs.isInfinite()) {
    //     result.setToInfinite();
    //     return;
    // }
    // if (lhs.isZero() || rhs.isZero()) {
    //     result.setToZero();
    //     return;
    // }

    logic [MBITS-1:0] fraction_mult, result_fraction;

    logic [FHBITS-1:0] r1, r2;
    assign r1 = {1'b1, a.fraction}; // Add back hidden bit (fraction is without hidden bit) TODO does this work? What if the hidden bit is 0???
    assign r2 = {1'b1, b.fraction}; // Add back hidden bit (fraction is without hidden bit)
    assign fraction_mult = r1 * r2; // Unsigned multiplication of fractions

    // Check if the radix point needs to shift

    assign product.scale = fraction_mult[MBITS-1] ? (a.scale + b.scale + 1) : (a.scale + b.scale);

    assign result_fraction = fraction_mult[MBITS-1] ? (fraction_mult << 1) : (fraction_mult << 2); // Shift hidden bit out

    assign product.fraction = result_fraction[MBITS-1:0];
    assign product.sign = a.sign ^ b.sign;
    assign product.zero = a.zero | b.zero;
    assign product.inf = a.inf | b.inf;

    // TODO special case handling output
    //     if (product.isZero()) {
    //         setToZero();
    //     }
    //     else if (product.isInfinite()) {
    //         setToNaR();
    //     }


    // TODO check inward projection:
    // if (check_inward_projection_range(scale)) {    // regime dominated
    // ELSE::::


    logic [ES-1:0] result_exponent;
    assign result_exponent = product.scale % (2 << ES);

    logic [4:0] regime_shift_amount;
    // Positive scale -> Should shift with 1's with 1 extra (specification)
    // Negative scale -> Make value positive
    assign regime_shift_amount = (product.scale[6] == 0) ? 1 + (product.scale >> ES) : -(product.scale >> ES);

    logic [2*NBITS-1:0] regime_exp_fraction;
    assign regime_exp_fraction = { {NBITS{~product.scale[6]}}, // Regime leading bits
                            product.scale[6], // Regime terminating bit
                            result_exponent, // Exponent
                            product.fraction[MBITS-1:MBITS-NBITS+3]}; // Fraction

    logic [2*NBITS-1:0] exp_fraction_shifted_for_regime;

    DSR_right_N_S #(
        .N(2*NBITS),
        .S(5)
    ) dsr2 (
        .a(regime_exp_fraction), // exponent + fraction bits
        .b(regime_shift_amount), // Shift to right by regime value (clip at maximum number of bits)
        .c(exp_fraction_shifted_for_regime)
    );

    // STICKY BIT CALCULATION (all the bits from [msb, lsb], that is, msb is included)
    logic [MBITS-1:0] fraction_leftover;
    logic [NBITS-1:0] leftover_shift;
    assign leftover_shift = NBITS - 3 - regime_shift_amount;
    DSR_left_N_S #(
        .N(MBITS),
        .S(NBITS)
    ) fraction_leftover_shift (
        .a(product.fraction), // exponent + fraction bits
        .b(leftover_shift), // Shift to right by regime value (clip at maximum number of bits)
        .c(fraction_leftover)
    );
    logic sticky_bit;
    assign sticky_bit = |fraction_leftover[MBITS-1:0];

    // TODO THIS PART
    // bool sb = anyAfter(input_fraction, input_fbits - 1 - nf);
    //
    // // construct the untruncated posit
    // // pt    = BitOr[BitShiftLeft[reg, es + nf + 1], BitShiftLeft[esval, nf + 1], BitShiftLeft[fv, 1], sb];
    // regime <<= es + nf + 1;
    // exponent <<= nf + 1;
    // fraction <<= 1;
    // sticky_bit.set(0, sb);
    //
    // pt_bits |= regime;
    // pt_bits |= exponent;
    // pt_bits |= fraction;
    // pt_bits |= sticky_bit;
    //
    // unsigned len = 1 + std::max<unsigned>((nbits + 1), (2 + run + es));
    // bool blast = pt_bits.test(len - nbits);
    // bool bafter = pt_bits.test(len - nbits - 1);
    // bool bsticky = anyAfter(pt_bits, len - nbits - 1 - 1);
    //
    // bool rb = (blast & bafter) | (bafter & bsticky);

    // special case check for projecting values between (0, minpos] to minpos and [maxpos, inf) to maxpos
	// Returns true if the scale is too small or too large for this posit config
	// DO NOT USE the k value for this, as the k value encodes the useed regions and thus is too coarse to make this decision
	// Using the scale directly is the simplest expression of the inward projection test.
    // int k = (scale < 0) ? -30 : 30;
    // return (scale < 0) ? (scale < (k << ES)) : (scale > (k << ES));


    // if (check_inward_projection_range(scale)) {    // regime dominated
    // std::cout << "inward projection" << std::endl;
    // // we are projecting to minpos/maxpos
    // _regime.assign_regime_pattern(k);
    // // store raw bit representation
    // _raw_bits = _sign ? twos_complement(collect()) : collect();
    // _raw_bits.set(nbits - 1, _sign);
    // // we are done
    // if (_trace_rounding) std::cout << "projection  rounding ";
    // }





    assign result = (product.zero | product.inf) ? {product.inf, {NBITS-1{1'b0}}} : {product.sign, exp_fraction_shifted_for_regime[NBITS-1:1]};
    assign inf = product.inf;
    assign zero = product.zero;
    assign done = start;
    //
    // logic rb;
    // assign rb = (             )

    //
    // pt_bits <<= pt_len - len;
    // bitblock<nbits> ptt;
    // truncate(pt_bits, ptt);
    //
    // if (rb) increment_bitset(ptt);
    // if (s) ptt = twos_complement(ptt);


endmodule





// void convert(bool sign, int scale, bitblock<input_fbits> input_fraction) {
//
//     // construct the posit
//     _sign = sign;
//     int k = calculate_unconstrained_k<nbits, es>(scale);
//     // interpolation rule checks
//     if (check_inward_projection_range(scale)) {    // regime dominated
//         // we are projecting to minpos/maxpos
//         _regime.assign_regime_pattern(k);
//         // store raw bit representation
//         _raw_bits = _sign ? twos_complement(collect()) : collect();
//         _raw_bits.set(nbits - 1, _sign);
//         // we are done
//     }
//     else {
//
//
//         unsigned run = (r ? 1 + (e >> es) : -(e >> es));
//         regime.set(0, 1 ^ r);
//         for (unsigned i = 1; i <= run; i++) regime.set(i, r);
//
//         unsigned esval = e % (uint32_t(1) << es);
//         exponent = convert_to_bitblock<pt_len>(esval);
//         unsigned nf = (unsigned)std::max<int>(0, (nbits + 1) - (2 + run + es));
//         // TODO: what needs to be done if nf > fbits?
//         //assert(nf <= input_fbits);
//         // copy the most significant nf fraction bits into fraction
//         unsigned lsb = nf <= input_fbits ? 0 : nf - input_fbits;
//         for (unsigned i = lsb; i < nf; i++) fraction[i] = input_fraction[input_fbits - nf + i];
//
//         bool sb = anyAfter(input_fraction, input_fbits - 1 - nf);
//
//         // construct the untruncated posit
//         // pt    = BitOr[BitShiftLeft[reg, es + nf + 1], BitShiftLeft[esval, nf + 1], BitShiftLeft[fv, 1], sb];
//         regime <<= es + nf + 1;
//         exponent <<= nf + 1;
//         fraction <<= 1;
//         sticky_bit.set(0, sb);
//
//         pt_bits |= regime;
//         pt_bits |= exponent;
//         pt_bits |= fraction;
//         pt_bits |= sticky_bit;
//
//         unsigned len = 1 + std::max<unsigned>((nbits + 1), (2 + run + es));
//         bool blast = pt_bits.test(len - nbits);
//         bool bafter = pt_bits.test(len - nbits - 1);
//         bool bsticky = anyAfter(pt_bits, len - nbits - 1 - 1);
//
//         bool rb = (blast & bafter) | (bafter & bsticky);
//
//         pt_bits <<= pt_len - len;
//         bitblock<nbits> ptt;
//         truncate(pt_bits, ptt);
//
//         if (rb) increment_bitset(ptt);
//         if (s) ptt = twos_complement(ptt);
//         decode(ptt);
//     }
// }
