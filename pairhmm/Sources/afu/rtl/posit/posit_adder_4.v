`timescale 1ns / 1ps
`default_nettype wire

module posit_adder_4 (aclk, in1, in2, start, result, inf, zero, done);

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

    parameter N = 8;
    parameter es = 4;
    parameter Bs = log2(N);

    //   _____   _                           _
    //  / ____| (_)                         | |
    // | (___    _    __ _   _ __     __ _  | |  ___
    //  \___ \  | |  / _` | | '_ \   / _` | | | / __|
    //  ____) | | | | (_| | | | | | | (_| | | | \__ \
    // |_____/  |_|  \__, | |_| |_|  \__,_| |_| |___/
    //                __/ |
    //               |___/

    input wire aclk;
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
    //                               |_|                                                                                                                                                                                                  |_|

    logic [N-1:0] r0_in1, r0_in2;
    logic r0_start, r0_s1, r0_s2, r0_zero_tmp1, r0_zero_tmp2, r0_inf, r0_inf1, r0_inf2, r0_zero, r0_zero1, r0_zero2;

    logic r0_rc1, r0_rc2;
    logic [Bs-1:0] r0_regime1, r0_regime2;
    logic [es-1:0] r0_e1, r0_e2;
    logic [N-es-1:0] r0_frac1, r0_frac2;
    logic [N-es:0] r0_m1, r0_m2;
    logic r0_in1_gt_in2;
    logic [N-1:0] r0_xin1, r0_xin2;

    always @(posedge aclk)
    begin
        if(in1 === 'x)
        begin
            r0_in1 <= '0;
            r0_s1 <= 0;
            r0_zero_tmp1 <= 0;
        end
        else
        begin
            r0_in1 <= in1;
            r0_s1 <= in1[N-1];
            r0_zero_tmp1 <= |in1[N-2:0];
        end

        if(in2 === 'x)
        begin
            r0_in2 <= '0;
            r0_s2 <= 0;
            r0_zero_tmp2 <= 0;
        end
        else
        begin
            r0_in2 <= in2;
            r0_s2 <= in2[N-1];
            r0_zero_tmp2 <= |in2[N-2:0];
        end

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

    data_extract #(
    	.N(N),
    	.es(es)
    ) uut_de1 (
    	.in(r0_xin1),
    	.rc(r0_rc1),
    	.regime(r0_regime1),
    	.exp(r0_e1),
    	.frac(r0_frac1)
    );

    data_extract #(
    	.N(N),
    	.es(es)
    ) uut_de2 (
    	.in(r0_xin2),
    	.rc(r0_rc2),
    	.regime(r0_regime2),
    	.exp(r0_e2),
    	.frac(r0_frac2)
    );

    assign r0_m1 = {r0_zero_tmp1, r0_frac1};
    assign r0_m2 = {r0_zero_tmp2, r0_frac2};

    // Large Checking and Assignment
    assign r0_in1_gt_in2 = r0_xin1[N-2:0] >= r0_xin2[N-2:0] ? '1 : '0;

    //  __         __  __                   _     _                                        _       _   _   _     _
    // /_ |  _    |  \/  |                 | |   (_)                           /\         | |     | | (_) | |   (_)
    //  | | (_)   | \  / |   __ _   _ __   | |_   _   ___   ___    __ _       /  \      __| |   __| |  _  | |_   _    ___    _ __
    //  | |       | |\/| |  / _` | | '_ \  | __| | | / __| / __|  / _` |     / /\ \    / _` |  / _` | | | | __| | |  / _ \  | '_ \
    //  | |  _    | |  | | | (_| | | | | | | |_  | | \__ \ \__ \ | (_| |    / ____ \  | (_| | | (_| | | | | |_  | | | (_) | | | | |
    //  |_| (_)   |_|  |_|  \__,_| |_| |_|  \__| |_| |___/ |___/  \__,_|   /_/    \_\  \__,_|  \__,_| |_|  \__| |_|  \___/  |_| |_|

    logic r1_start, r1_s1, r1_s2, r1_inf, r1_zero;

    logic r1_rc1, r1_rc2, r1_in1_gt_in2, r1_ls, r1_op, r1_lrc, r1_src;
    logic [Bs-1:0] r1_regime1, r1_regime2, r1_lr, r1_sr;
    logic [es-1:0] r1_e1, r1_e2, r1_le, r1_se;
    logic [N-es:0] r1_m1, r1_m2, r1_lm, r1_sm;
    logic [Bs:0] r1_r_diff11, r1_r_diff12, r1_r_diff2, r1_r_diff, r1_lr_N;
    logic [N-1:0] r1_DSR_right_in;

    always @(posedge aclk) // Global pipeline signals
    begin
       r1_start <= r0_start;
       r1_s1 <= r0_s1;
       r1_s2 <= r0_s2;
       r1_inf <= r0_inf;
       r1_zero <= r0_zero;
    end

    always @(posedge aclk) // Extracted data
    begin
        r1_rc1 <= r0_rc1;
        r1_rc2 <= r0_rc2;

        r1_regime1 <= r0_regime1;
        r1_regime2 <= r0_regime2;

        r1_e1 <= r0_e1;
        r1_e2 <= r0_e2;

        r1_m1 <= r0_m1;
        r1_m2 <= r0_m2;

        r1_in1_gt_in2 <= r0_in1_gt_in2;
    end

    //
    assign r1_ls = r1_in1_gt_in2 ? r1_s1 : r1_s2;
    assign r1_op = r1_s1 ~^ r1_s2;

    assign r1_lrc = r1_in1_gt_in2 ? r1_rc1 : r1_rc2;
    assign r1_src = r1_in1_gt_in2 ? r1_rc2 : r1_rc1;

    // Regime
    assign r1_lr = r1_in1_gt_in2 ? r1_regime1 : r1_regime2;
    assign r1_sr = r1_in1_gt_in2 ? r1_regime2 : r1_regime1;

    // Exponent
    assign r1_le = r1_in1_gt_in2 ? r1_e1 : r1_e2;
    assign r1_se = r1_in1_gt_in2 ? r1_e2 : r1_e1;

    // Fraction
    assign r1_lm = r1_in1_gt_in2 ? r1_m1 : r1_m2;
    assign r1_sm = r1_in1_gt_in2 ? r1_m2 : r1_m1;

    // Exponent Difference: Lower Fraction Right Shift Amount

    sub_N #(
    	.N(Bs)
    ) uut_sub1 (
    	r1_lr,
    	r1_sr,
    	r1_r_diff11
    );

    add_N #(
    	.N(Bs)
    ) uut_add1 (
    	r1_lr,
    	r1_sr,
    	r1_r_diff12
    );

    sub_N #(
    	.N(Bs)
    ) uut_sub2 (
    	r1_sr,
    	r1_lr,
    	r1_r_diff2
    );

    // DSR Right Shifting of Small Fraction
    generate
        if (es >= 2)
        begin
            assign r1_DSR_right_in = {r1_sm, {es-1{1'b0}}};
        end
        else
        begin
            assign r1_DSR_right_in = r1_sm;
        end
    endgenerate

    assign r1_r_diff = r1_lrc ? (r1_src ? r1_r_diff11 : r1_r_diff12) : r1_r_diff2;
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
    logic [N-1:0] r2_DSR_right_out, r2_add_m_in1, r2_DSR_right_in;
    logic [Bs-1:0] r2_DSR_e_diff, r2_exp_diff;
    logic [N:0] r2_add_m, r2_add_m1, r2_add_m2;
    logic [es-1:0] r2_le, r2_se;
    logic [N-es:0] r2_lm;
    logic [Bs:0] r2_r_diff, r2_lr_N;
    logic [es+Bs+1:0] r2_diff;

    always @(posedge aclk)
    begin
        r2_start <= r1_start;
        r2_inf <= r1_inf;
        r2_zero <= r1_zero;
    end

    always @(posedge aclk)
    begin
        r2_r_diff <= r1_r_diff;
        r2_le <= r1_le;
        r2_se <= r1_se;
        r2_DSR_right_in <= r1_DSR_right_in;
        r2_lm <= r1_lm;
        r2_op <= r1_op;
        r2_ls <= r1_ls;
        r2_lr_N <= r1_lr_N;
    end


    sub_N #(
        .N(es + Bs + 1)
    ) uut_sub_diff (
        .a({r2_r_diff, r2_le}),
        .b({{Bs+1{1'b0}}, r2_se}),
        .c(r2_diff)
    );

    assign r2_exp_diff = (|r2_diff[es+Bs:Bs]) ? {Bs{1'b1}} : r2_diff[Bs-1:0];

    // Laurens: Dependency here (exp_diff) (Pipeline stage?)
    assign r2_DSR_e_diff = r2_exp_diff;

    DSR_right_N_S #(
    	.N(N),
    	.S(Bs)
    ) dsr1 (
    	.a(r2_DSR_right_in),
    	.b(r2_DSR_e_diff),
    	.c(r2_DSR_right_out)
    );

    // Fraction Addition
    generate
    	if (es >= 2)
        begin
    		assign r2_add_m_in1 = {r2_lm, {es-1{1'b0}}};
        end
    	else
        begin
    		assign r2_add_m_in1 = r2_lm;
        end
    endgenerate

    // Laurens: Dependency here (DSR_right_out, add_m_in1) (Pipeline stage?)

    add_N #(
    	.N(N)
    ) uut_add_m1 (
    	r2_add_m_in1,
    	r2_DSR_right_out,
    	r2_add_m1
    );

    sub_N #(
    	.N(N)
    ) uut_sub_m2 (
    	r2_add_m_in1,
    	r2_DSR_right_out,
    	r2_add_m2
    );

    // Laurens: Dependency here (add_m1, add_m2) (Pipeline stage?)
    assign r2_add_m = r2_op ? r2_add_m1 : r2_add_m2;

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
    logic [N-1:0] r3_LOD_in, r3_DSR_left_out_t, r3_DSR_left_out;
    logic [N:0] r3_add_m;
    logic [es-1:0] r3_le, r3_se;
    logic [Bs-1:0] r3_left_shift;
    logic [Bs:0] r3_lr_N;
    logic [es+Bs+1:0] r3_le_o_tmp;

    always @(posedge aclk)
    begin
        r3_start <= r2_start;
        r3_inf <= r2_inf;
        r3_zero <= r2_zero;
    end

    always @(posedge aclk)
    begin
        r3_le <= r2_le;
        r3_se <= r2_se;
        r3_ls <= r2_ls;
        r3_lr_N <= r2_lr_N;
        r3_add_m <= r2_add_m;
    end

    // Laurens: Dependency here (add_m) (Pipeline stage?)
    // LOD of fraction addition result
    assign r3_frac_ovf = r3_add_m[N:N-1];
    assign r3_LOD_in = {(r3_add_m[N] | r3_add_m[N-1]), r3_add_m[N-2:0]};

    LOD_N #(
    	.N(N)
    ) l2 (
    	.in(r3_LOD_in),
    	.out(r3_left_shift)
    );

    // Laurens: Dependency here (left_shift) (Pipeline stage?)
    // DSR Left Shifting of fraction result
    // Exponent and Regime Computation

    DSR_left_N_S #(
    	.N(N),
    	.S(Bs)
    ) dsl1 (
    	.a(r3_add_m[N:1]),
    	.b(r3_left_shift),
    	.c(r3_DSR_left_out_t)
    );

    sub_N #(
    	.N(es+Bs+1)
    ) sub3 (
    	.a({r3_lr_N, r3_le}),
    	.b({{es+1{1'b0}}, r3_left_shift}),
    	.c(r3_le_o_tmp)
    );

    // Laurens: Dependency here (DSR_left_out_t, le_o_tmp) (Pipeline stage?)
    assign r3_DSR_left_out = r3_DSR_left_out_t[N-1] ? r3_DSR_left_out_t[N-1:0] : {r3_DSR_left_out_t[N-2:0], 1'b0};

    logic [es+Bs+1:0] r3_le_o;
    logic [es+Bs:0] r3_le_oN;
    logic [es-1:0] r3_e_o;
    logic [Bs-1:0] r3_r_o;
    logic [2*N-1:0] r3_tmp_o, r3_tmp1_o;

    add_mantovf #(
    	es+Bs+1
    ) uut_add_mantovf (
    	r3_le_o_tmp,
    	r3_frac_ovf[1],
    	r3_le_o
    );

    assign r3_le_oN = r3_le_o[es+Bs] ? -r3_le_o : r3_le_o;
    assign r3_e_o = (r3_le_o[es+Bs] & |r3_le_oN[es-1:0]) ? r3_le_o[es-1:0] : r3_le_oN[es-1:0];
    assign r3_r_o = (~r3_le_o[es+Bs] || (r3_le_o[es+Bs] & |r3_le_oN[es-1:0])) ? (r3_le_oN[es+Bs-1:es] + 1'b1) : r3_le_oN[es+Bs-1:es];

    // Exponent and Fraction Packing
    assign r3_tmp_o = { {N{~r3_le_o[es+Bs]}}, r3_le_o[es+Bs], r3_e_o, r3_DSR_left_out[N-2:es]};

    // Laurens: Dependency here (tmp_o, r_o) (Pipeline stage?)
    DSR_right_N_S #(
    	.N(2*N),
    	.S(Bs)
    ) dsr2 (
    	.a(r3_tmp_o),
    	.b(r3_r_o),
    	.c(r3_tmp1_o)
    );

    //  _____                         _   _
    // |  __ \                       | | | |
    // | |__) |   ___   ___   _   _  | | | |_
    // |  _  /   / _ \ / __| | | | | | | | __|
    // | | \ \  |  __/ \__ \ | |_| | | | | |_
    // |_|  \_\  \___| |___/  \__,_| |_|  \__|

    // Laurens: Dependency here (tmp1_o) (Pipeline stage?)
    logic [2*N-1:0] r3_tmp1_oN;
    assign r3_tmp1_oN = r3_ls ? -r3_tmp1_o : r3_tmp1_o;

    // Final Output
    assign zero = r3_zero;
    assign inf = r3_inf;
    assign result = r3_inf | r3_zero | (~r3_DSR_left_out[N-1]) ? {r3_inf, {N-1{1'b0}}} : {r3_ls, r3_tmp1_oN[N-1:1]};
    assign done = r3_start;

endmodule
