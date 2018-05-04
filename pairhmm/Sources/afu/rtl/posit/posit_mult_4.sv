`timescale 1ns / 1ps
`default_nettype wire

module posit_mult_4 (clk, in1, in2, start, result, inf, zero, done);

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
    parameter es = 2;
    parameter Bs = log2(N);

    //   _____   _                           _
    //  / ____| (_)                         | |
    // | (___    _    __ _   _ __     __ _  | |  ___
    //  \___ \  | |  / _` | | '_ \   / _` | | | / __|
    //  ____) | | | | (_| | | | | | | (_| | | | \__ \
    // |_____/  |_|  \__, | |_| |_|  \__,_| |_| |___/
    //                __/ |
    //               |___/

    input wire clk;
    input wire [N-1:0] in1, in2;
    input wire start;
    output wire [N-1:0] result;
    output wire inf, zero;
    output wire done;

    //   ___          _____                           _                  _____            _               ______          _                           _     _
    //  / _ \   _    |_   _|                         | |       ___      |  __ \          | |             |  ____|        | |                         | |   (_)
    // | | | | (_)     | |    _ __    _ __    _   _  | |_     ( _ )     | |  | |   __ _  | |_    __ _    | |__    __  __ | |_   _ __    __ _    ___  | |_   _    ___    _ __
    // | | | |         | |   | '_ \  | '_ \  | | | | | __|    / _ \/\   | |  | |  / _` | | __|  / _` |   |  __|   \ \/ / | __| | '__|  / _` |  / __| | __| | |  / _ \  | '_ \
    // | |_| |  _     _| |_  | | | | | |_) | | |_| | | |_    | (_>  <   | |__| | | (_| | | |_  | (_| |   | |____   >  <  | |_  | |    | (_| | | (__  | |_  | | | (_) | | | | |
    //  \___/  (_)   |_____| |_| |_| | .__/   \__,_|  \__|    \___/\/   |_____/   \__,_|  \__|  \__,_|   |______| /_/\_\  \__| |_|     \__,_|  \___|  \__| |_|  \___/  |_| |_|
    //                               | |
    //                               |_|

    logic [N-1:0] r0_in1, r0_in2;
    logic r0_start, r0_s1, r0_s2, r0_nonzero1, r0_nonzero2, r0_inf, r0_inf1, r0_inf2, r0_zero, r0_zero1, r0_zero2;

    logic r0_rc1, r0_rc2, r0_mult_s;
    logic [Bs-1:0] r0_regime1, r0_regime2;
    logic [es-1:0] r0_e1, r0_e2;
    logic [N-es-1:0] r0_frac1, r0_frac2;
    logic [N-1:0] r0_xin1, r0_xin2;
    logic [N-es:0] r0_f1, r0_f2;

    always @(posedge clk)
    begin
        r0_in1 <= (in1 === 'x) ? '0 : in1;
        r0_s1 <= (in1 === 'x) ? '0 : in1[N-1];
        r0_nonzero1 <= (in1 === 'x) ? '0 : |in1[N-2:0];

        r0_in2 <= (in2 === 'x) ? '0 : in2;
        r0_s2 <= (in2 === 'x) ? '0 : in2[N-1];
        r0_nonzero2 <= (in2 === 'x) ? '0 : |in2[N-2:0];

        r0_start <= (start === 'x) ? '0 : start;
    end

    assign r0_inf1 = (in1[N-1] === 'x) ? '0 : in1[N-1] & (~r0_nonzero1);
    assign r0_inf2 = (in2[N-1] === 'x) ? '0 : in2[N-1] & (~r0_nonzero2);

    assign r0_zero1 = (in1[N-1] === 'x) ? '0 : ~(in1[N-1] | r0_nonzero1);
    assign r0_zero2 = (in2[N-1] === 'x) ? '0 : ~(in2[N-1] | r0_nonzero2);

    assign r0_inf = r0_inf1 | r0_inf2;
    assign r0_zero = r0_zero1 & r0_zero2;

    // Data Extraction
    assign r0_xin1 = r0_s1 ? -r0_in1 : r0_in1;
    assign r0_xin2 = r0_s2 ? -r0_in2 : r0_in2;
    assign r0_mult_s = r0_s1 ^ r0_s2;

    data_extract #(.N(N), .es(es)) data_extract1 (
        .in(r0_xin1),
        .rc(r0_rc1),
        .regime(r0_regime1),
        .exp(r0_e1),
        .frac(r0_frac1)
    );

    data_extract #(.N(N), .es(es)) data_extract2 (
        .in(r0_xin2),
        .rc(r0_rc2),
        .regime(r0_regime2),
        .exp(r0_e2),
        .frac(r0_frac2)
    );

    // Account for hidden bit
    assign r0_f1 = {r0_nonzero1, r0_frac1};
    assign r0_f2 = {r0_nonzero2, r0_frac2};


    //  __
    // /_ |
    //  | |
    //  | |
    //  | |
    //  |_|

    logic r1_start, r1_inf, r1_zero, r1_rc1, r1_rc2, r1_mult_s;
    logic [Bs-1:0] r1_regime1, r1_regime2;
    logic [es-1:0] r1_e1, r1_e2;
    logic [N-es:0] r1_f1, r1_f2;
    logic [2*(N-es)+1:0] r1_mult_m;

    always @(posedge clk)
    begin
        r1_start <= r0_start;
        r1_inf <= r0_inf;
        r1_zero <= r0_zero;

        r1_f1 <= r0_f1;
        r1_f2 <= r0_f2;
        r1_regime1 <= r0_regime1;
        r1_regime2 <= r0_regime2;
        r1_rc1 <= r0_rc1;
        r1_rc2 <= r0_rc2;
        r1_e1 <= r0_e1;
        r1_e2 <= r0_e2;
        r1_mult_s <= r0_mult_s;
    end

    // Fraction multiplication
    assign r1_mult_m = r1_f1 * r1_f2;


    //  ___
    // |__ \
    //    ) |
    //   / /
    //  / /_
    // |____|

    logic r2_start, r2_inf, r2_zero, r2_rc1, r2_rc2, r2_mult_s;
    logic [Bs-1:0] r2_regime1, r2_regime2;
    logic [es-1:0] r2_e1, r2_e2;
    logic [2*(N-es)+1:0] r2_mult_m;

    logic r2_mult_m_overflow;
    logic [2*(N-es)+1:0] r2_mult_mN;
    logic [Bs+1:0] r2_r1, r2_r2;
    logic [es+Bs+1:0] r2_mult_e;
    logic [es+Bs:0] r2_mult_eN;
    logic [es-1:0] r2_e_o;
    logic [Bs:0] r2_r_o;
    logic [2*N-1:0] r2_exp_fraction;

    always @(posedge clk)
    begin
        r2_start <= r1_start;
        r2_inf <= r1_inf;
        r2_zero <= r1_zero;

        r2_regime1 <= r1_regime1;
        r2_regime2 <= r1_regime2;
        r2_rc1 <= r1_rc1;
        r2_rc2 <= r1_rc2;
        r2_e1 <= r1_e1;
        r2_e2 <= r1_e2;
        r2_mult_s <= r1_mult_s;
    end

    always @(posedge clk)
    begin
        r2_mult_m <= r1_mult_m;
    end

    assign r2_mult_m_overflow = r2_mult_m[2*(N-es)+1]; // Is there a 2 in multiplication result? Set overflow bit

    assign r2_mult_mN = ~r2_mult_m_overflow ? r2_mult_m << 1'b1 : r2_mult_m; // Overflow? Divide fraction by 2 (put in exponent)

    assign r2_r1 = r2_rc1 ? {2'b0, r2_regime1} : -r2_regime1; // Leading 0 -> Regime value is negative
    assign r2_r2 = r2_rc2 ? {2'b0, r2_regime2} : -r2_regime2;

    // SIGNED REGIME + EXPONENT (taking into account fraction multiplication overflow)
    assign r2_mult_e  =  {r2_r1, r2_e1} + {r2_r2, r2_e2} + r2_mult_m_overflow;

    // ABSOLUTE REGIME + EXPONENT
    assign r2_mult_eN = r2_mult_e[es+Bs+1] ? -r2_mult_e : r2_mult_e;

    // UNSIGNED EXPONENT
    // (Regime + Exponent) negative, ES of absolute (Regime + Exponent) nonzero? -> Unsigned Exponent = 2's complement
    assign r2_e_o = (r2_mult_e[es+Bs+1] & |r2_mult_eN[es-1:0]) ? r2_mult_e[es-1:0] : r2_mult_eN[es-1:0];

    // UNSIGNED REGIME
    //              (positive regime+exponent OR (negative reg+exp && non-zero exponent)  ) then (absolute regime + 1)      else absolute regime
    assign r2_r_o = (~r2_mult_e[es+Bs+1]      || (r2_mult_e[es+Bs+1] & |r2_mult_eN[es-1:0])) ? (r2_mult_eN[es+Bs:es] + 1'b1) : r2_mult_eN[es+Bs:es];

    // Exponent and Fraction Packing
    assign r2_exp_fraction = {
        { N{~r2_mult_e[es+Bs+1]} }, // Repeat negated sign bit of (Regime + Exponent)
        r2_mult_e[es+Bs+1], // Sign bit of (Regime + Exponent)
        r2_e_o, // Unsigned exponent field
        r2_mult_mN[2*(N-es):N-es+2] // Fraction field (cut off)
    };


    //  ____
    // |___ \
    //   __) |
    //  |__ <
    //  ___) |
    // |____/

    logic r3_start, r3_inf, r3_zero, r3_mult_s;

    logic r3_mult_zero;
    logic [Bs:0] r3_r_o;
    logic [2*N-1:0] r3_exp_fraction, r3_out_unsigned, r3_out_signed;

    always @(posedge clk)
    begin
        r3_start <= r2_start;
        r3_inf <= r2_inf;
        r3_zero <= r2_zero;
        r3_mult_s <= r2_mult_s;

        r3_exp_fraction <= r2_exp_fraction;
        r3_r_o <= r2_r_o;
        r3_mult_zero <= r2_mult_mN[2*(N-es)+1]; // "Hidden bit" might be 0 (when inf/zero)
    end

    // Including Regime bits in Exponent + Fraction package
    DSR_right_N_S #(
        .N(2*N),
        .S(Bs+1)
    ) dsr2 (
        .a(r3_exp_fraction), // exponent + fraction bits
        .b(r3_r_o[Bs] ? {Bs{1'b1}} : r3_r_o), // Shift to right by regime value (clip at maximum number of bits)
        .c(r3_out_unsigned)
    );

    // Signed output (2*N wide)
    assign r3_out_signed = r3_mult_s ? -r3_out_unsigned : r3_out_unsigned; // Fix the sign

    // Final Output
    assign zero = r3_zero;
    assign inf = r3_inf;
    assign done = r3_start;

    // Output infinite or zero? Set this as output. Otherwise, pack the sign bit and signed output
    assign result = (r3_inf | r3_zero | (~r3_mult_zero)) ? {r3_inf, {N-1{1'b0}}} : {r3_mult_s, r3_out_signed[N-1:1]};

endmodule
