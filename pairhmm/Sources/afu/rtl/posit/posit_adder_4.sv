`timescale 1ns / 1ps
`default_nettype wire

`include "posit_pkg.sv"

module posit_adder_4 (clk, in1, in2, start, result, inf, zero, done);

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

    logic r0_rc1, r0_rc2, r0_in1_gt_in2;
    logic [Bs-1:0] r0_regime1, r0_regime2;
    logic [es-1:0] r0_e1, r0_e2;
    logic [N-es-1:0] r0_frac1, r0_frac2;
    logic [N-es:0] r0_f1, r0_f2;
    logic [N-1:0] r0_xin1, r0_xin2;

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

    assign r0_inf1 = (in1[N-1] === 'x) ? '0 : in1[N-1] & (~r0_zero_tmp1);
    assign r0_inf2 = (in2[N-1] === 'x) ? '0 : in2[N-1] & (~r0_zero_tmp2);

    assign r0_zero1 = (in1[N-1] === 'x) ? '0 : ~(in1[N-1] | r0_zero_tmp1);
    assign r0_zero2 = (in2[N-1] === 'x) ? '0 : ~(in2[N-1] | r0_zero_tmp2);

    assign r0_inf = r0_inf1 | r0_inf2;
    assign r0_zero = r0_zero1 & r0_zero2;

    assign r0_xin1 = r0_s1 ? -r0_in1 : r0_in1;
    assign r0_xin2 = r0_s2 ? -r0_in2 : r0_in2;

    // Extract data of input posits
    //  - Leading regime check bit
    //  - Regime
    //  - Exponent
    //  - Fraction
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

    // Determine largest operand
    assign r0_in1_gt_in2 = r0_xin1[N-2:0] >= r0_xin2[N-2:0] ? '1 : '0;


    //  __
    // /_ |
    //  | |
    //  | |
    //  | |
    //  |_|

    logic r1_start, r1_s1, r1_s2, r1_inf, r1_zero;

    logic r1_rc1, r1_rc2, r1_in1_gt_in2, r1_ls, r1_op, r1_lrc, r1_src;
    logic [Bs-1:0] r1_regime1, r1_regime2, r1_lr, r1_sr; // Regime
    logic [es-1:0] r1_e1, r1_e2, r1_le, r1_se; // Exponent
    logic [N-es:0] r1_f1, r1_f2, r1_lf, r1_sf; // Fraction
    logic [Bs:0] r1_r_diff11, r1_r_diff12, r1_r_diff2, r1_r_diff, r1_lr_N;
    logic [N-1:0] r1_sf_pad;

    always @(posedge clk) // Global pipeline signals
    begin
        r1_start <= r0_start;
        r1_s1 <= r0_s1;
        r1_s2 <= r0_s2;
        r1_inf <= r0_inf;
        r1_zero <= r0_zero;

        r1_in1_gt_in2 <= r0_in1_gt_in2;
        r1_rc1 <= r0_rc1;
        r1_rc2 <= r0_rc2;
        r1_regime1 <= r0_regime1;
        r1_regime2 <= r0_regime2;
        r1_e1 <= r0_e1;
        r1_e2 <= r0_e2;
        r1_f1 <= r0_f1;
        r1_f2 <= r0_f2;
    end

    // Determine posit data for large (l) and small (s) inputs

    // Sign of largest input
    assign r1_ls = r1_in1_gt_in2 ? r1_s1 : r1_s2;
    // Operation: Add or Subtract
    assign r1_op = r1_s1 ~^ r1_s2; // Equal signs: add

    // Regime check bits (leading 0 or 1)
    assign r1_lrc = r1_in1_gt_in2 ? r1_rc1 : r1_rc2;
    assign r1_src = r1_in1_gt_in2 ? r1_rc2 : r1_rc1;

    // Regime
    assign r1_lr = r1_in1_gt_in2 ? r1_regime1 : r1_regime2;
    assign r1_sr = r1_in1_gt_in2 ? r1_regime2 : r1_regime1;

    // Exponent
    assign r1_le = r1_in1_gt_in2 ? r1_e1 : r1_e2;
    assign r1_se = r1_in1_gt_in2 ? r1_e2 : r1_e1;

    // Fraction
    assign r1_lf = r1_in1_gt_in2 ? r1_f1 : r1_f2;
    assign r1_sf = r1_in1_gt_in2 ? r1_f2 : r1_f1;

    // Add/Subtract regime
    assign r1_r_diff11 = {1'b0, r1_lr} - {1'b0, r1_sr};
    assign r1_r_diff12 = {1'b0, r1_lr} + {1'b0, r1_sr};
    assign r1_r_diff2 = {1'b0, r1_sr} - {1'b0, r1_lr};

    // DSR Right Shifting of Small Fraction
    generate
        if (es >= 2)
        begin
            assign r1_sf_pad = {r1_sf, {es-1{1'b0}}};
        end
        else
        begin
            assign r1_sf_pad = r1_sf;
        end
    endgenerate

    // Regime difference
    // Positive large regime
        // Positive small regime: r1_r_diff11   (large regime - small regime)
        // Negative small regime: r1_r_diff12   (large regime + small regime)
    // Negative large regime: r1_r_diff2        (small regime - large regime)
    assign r1_r_diff = r1_lrc ? (r1_src ? r1_r_diff11 : r1_r_diff12) : r1_r_diff2;

    // Negative large regime: negate absolute regime value
    assign r1_lr_N = r1_lrc ? {1'b0, r1_lr} : -{1'b0, r1_lr};


    //  ___
    // |__ \
    //    ) |
    //   / /
    //  / /_
    // |____|

    // Global pipeline signals
    logic r2_start, r2_inf, r2_zero;

    logic r2_ls, r2_op;
    logic [N-1:0] r2_add_f_in2, r2_add_f_in1, r2_sf_pad;
    logic [Bs-1:0] r2_exp_diff;
    logic [N:0] r2_add_f, r2_add_f1, r2_add_f2;
    logic [es-1:0] r2_le, r2_se;
    logic [N-es:0] r2_lf;
    logic [Bs:0] r2_r_diff, r2_lr_N;
    logic [es+Bs+1:0] r2_diff;

    always @(posedge clk)
    begin
        r2_start <= r1_start;
        r2_inf <= r1_inf;
        r2_zero <= r1_zero;

        r2_r_diff <= r1_r_diff;
        r2_le <= r1_le;
        r2_se <= r1_se;
        r2_sf_pad <= r1_sf_pad;
        r2_lf <= r1_lf;
        r2_op <= r1_op;
        r2_ls <= r1_ls;
        r2_lr_N <= r1_lr_N;
    end

    assign r2_diff = {1'b0, r2_r_diff, r2_le} - {1'b0, {Bs+1{1'b0}}, r2_se};
    assign r2_exp_diff = (|r2_diff[es+Bs:Bs]) ? {Bs{1'b1}} : r2_diff[Bs-1:0];

    // Shift right fraction of smallest input by exponent difference
    DSR_right_N_S #(.N(N), .S(Bs)) dsr1 (
    	.a(r2_sf_pad), // small input fraction
    	.b(r2_exp_diff), // exponent difference
    	.c(r2_add_f_in2)
    );

    // Fraction Addition
    generate
    	if (es >= 2)
        begin
    		assign r2_add_f_in1 = {r2_lf, {es-1{1'b0}}};
        end
    	else
        begin
    		assign r2_add_f_in1 = r2_lf;
        end
    endgenerate

    // Add/Subtract fractions
    assign r2_add_f1 = {1'b0, r2_add_f_in1} + {1'b0, r2_add_f_in2};
    assign r2_add_f2 = {1'b0, r2_add_f_in1} - {1'b0, r2_add_f_in2};
    // Fraction addition result mux (by operation)
    assign r2_add_f = r2_op ? r2_add_f1 : r2_add_f2;


    //  ____
    // |___ \
    //   __) |
    //  |__ <
    //  ___) |
    // |____/

    // Global pipeline signals
    logic r3_start, r3_inf, r3_zero;

    logic r3_ls;
    logic [1:0] r3_frac_ovf;
    logic [N-1:0] r3_LOD_in, r3_DSR_left_out_t, r3_add_f_normalized;
    logic [N:0] r3_add_f;
    logic [es-1:0] r3_le, r3_se, r3_e_o;
    logic [Bs-1:0] r3_left_shift, r3_r_o;
    logic [Bs:0] r3_lr_N;
    logic [es+Bs+1:0] r3_le_o, r3_le_o_tmp;
    logic [es+Bs:0] r3_le_oN;
    logic [2*N-1:0] r3_exp_frac, r3_regime_exp_frac, r3_regime_exp_frac_signed;

    always @(posedge clk)
    begin
        r3_start <= r2_start;
        r3_inf <= r2_inf;
        r3_zero <= r2_zero;

        r3_le <= r2_le;
        r3_se <= r2_se;
        r3_ls <= r2_ls;
        r3_lr_N <= r2_lr_N;
        r3_add_f <= r2_add_f;
    end

    // Laurens: Dependency here (add_f) (Pipeline stage?)
    assign r3_frac_ovf = r3_add_f[N:N-1];

    // Leading-Zero detector input: OR of first two MSB + remaining bits
    // Determined for normalization of fraction result
    assign r3_LOD_in = {(r3_add_f[N] | r3_add_f[N-1]), r3_add_f[N-2:0]};

    // Leading-Zero counter of fraction addition result
    LOD_N #(.N(N)) l2 (
    	.in(r3_LOD_in),
    	.out(r3_left_shift)
    );

    // Laurens: Dependency here (left_shift) (Pipeline stage?)

    // Exponent and Regime Computation
    // Shift left fraction result (normalization)
    DSR_left_N_S #(.N(N), .S(Bs)) dsl1 (
    	.a(r3_add_f[N:1]),
    	.b(r3_left_shift),
    	.c(r3_DSR_left_out_t)
    );

    assign r3_le_o_tmp = {1'b0, r3_lr_N, r3_le} - {1'b0, {es+1{1'b0}}, r3_left_shift};

    // Normalized sum fraction:
    // Negative: Use negative result
    // Positive: Shift left by 1
    assign r3_add_f_normalized = r3_DSR_left_out_t[N-1] ? r3_DSR_left_out_t[N-1:0] : {r3_DSR_left_out_t[N-2:0], 1'b0};

    // Fraction overflow
    assign r3_le_o = r3_le_o_tmp + r3_frac_ovf[1];

    // Correct exponent and regime sign
    assign r3_le_oN = r3_le_o[es+Bs] ? -r3_le_o : r3_le_o;
    assign r3_e_o = (r3_le_o[es+Bs] & |r3_le_oN[es-1:0]) ? r3_le_o[es-1:0] : r3_le_oN[es-1:0];
    assign r3_r_o = (~r3_le_o[es+Bs] || (r3_le_o[es+Bs] & |r3_le_oN[es-1:0])) ? (r3_le_oN[es+Bs-1:es] + 1'b1) : r3_le_oN[es+Bs-1:es];

    // Exponent and Fraction Packing
    assign r3_exp_frac = { {N{~r3_le_o[es+Bs]}}, r3_le_o[es+Bs], r3_e_o, r3_add_f_normalized[N-2:es]};

    DSR_right_N_S #(.N(2*N), .S(Bs)) dsr2 (
    	.a(r3_exp_frac),
    	.b(r3_r_o),
    	.c(r3_regime_exp_frac)
    );


    //  _____                         _   _
    // |  __ \                       | | | |
    // | |__) |   ___   ___   _   _  | | | |_
    // |  _  /   / _ \ / __| | | | | | | | __|
    // | | \ \  |  __/ \__ \ | |_| | | | | |_
    // |_|  \_\  \___| |___/  \__,_| |_|  \__|

    assign r3_regime_exp_frac_signed = r3_ls ? -r3_regime_exp_frac : r3_regime_exp_frac;

    // Final Output
    assign zero = r3_zero;
    assign inf = r3_inf;
    assign done = r3_start;

    // Output infinite or zero? Set this as output. Otherwise, pack the sign bit and signed output
    assign result = (r3_inf | r3_zero | (~r3_add_f_normalized[N-1])) ? {r3_inf, {N-1{1'b0}}} : {r3_ls, r3_regime_exp_frac_signed[N-1:1]};

endmodule
