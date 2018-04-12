`timescale 1ns / 1ps
`default_nettype wire

module posit_adder_12 (aclk, in1, in2, start, result, inf, zero, done);

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

   //  _____                           _
   // |_   _|                         | |
   //   | |    _ __    _ __    _   _  | |_   ___
   //   | |   | '_ \  | '_ \  | | | | | __| / __|
   //  _| |_  | | | | | |_) | | |_| | | |_  \__ \
   // |_____| |_| |_| | .__/   \__,_|  \__| |___/
   //                 | |
   //                 |_|

    input wire aclk;
    input wire [N-1:0] in1, in2;
    input wire start;
    output wire [N-1:0] result;
    output wire inf, zero;
    output wire done;


    //   ___           _____   _                  _        _                           _
    //  / _ \   _     / ____| | |                | |      (_)                         | |
    // | | | | (_)   | |      | |   ___     ___  | | __    _   _ __    _ __    _   _  | |_   ___
    // | | | |       | |      | |  / _ \   / __| | |/ /   | | | '_ \  | '_ \  | | | | | __| / __|
    // | |_| |  _    | |____  | | | (_) | | (__  |   <    | | | | | | | |_) | | |_| | | |_  \__ \
    //  \___/  (_)    \_____| |_|  \___/   \___| |_|\_\   |_| |_| |_| | .__/   \__,_|  \__| |___/
    //                                                                | |
    //                                                                |_|

    logic [N-1:0] r0_in1, r0_in2;
    logic r0_start, r0_s1, r0_s2, r0_zero_tmp1, r0_zero_tmp2, r0_inf, r0_inf1, r0_inf2, r0_zero, r0_zero1, r0_zero2;

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


    //  __         _____            _               ______          _                           _     _
    // /_ |  _    |  __ \          | |             |  ____|        | |                         | |   (_)
    //  | | (_)   | |  | |   __ _  | |_    __ _    | |__    __  __ | |_   _ __    __ _    ___  | |_   _    ___    _ __
    //  | |       | |  | |  / _` | | __|  / _` |   |  __|   \ \/ / | __| | '__|  / _` |  / __| | __| | |  / _ \  | '_ \
    //  | |  _    | |__| | | (_| | | |_  | (_| |   | |____   >  <  | |_  | |    | (_| | | (__  | |_  | | | (_) | | | | |
    //  |_| (_)   |_____/   \__,_|  \__|  \__,_|   |______| /_/\_\  \__| |_|     \__,_|  \___|  \__| |_|  \___/  |_| |_|

    // Global pipeline signals
    logic [N-1:0] r1_in1, r1_in2;
    logic r1_start, r1_s1, r1_s2, r1_zero_tmp1, r1_zero_tmp2, r1_inf, r1_zero;

    logic r1_rc1, r1_rc2, r1_in1_gt_in2;
    logic [Bs-1:0] r1_regime1, r1_regime2, r1_Lshift1, r1_Lshift2;
    logic [es-1:0] r1_e1, r1_e2;
    logic [N-es-1:0] r1_mant1, r1_mant2;
    logic [N-es:0] r1_m1, r1_m2;
    logic [N-1:0] r1_xin1, r1_xin2;

    always @(posedge aclk)
    begin
        r1_in1 <= r0_in1;
        r1_in2 <= r0_in2;
        r1_start <= r0_start;
        r1_s1 <= r0_s1;
        r1_s2 <= r0_s2;
        r1_zero_tmp1 <= r0_zero_tmp1;
        r1_zero_tmp2 <= r0_zero_tmp2;
        r1_inf <= r0_inf;
        r1_zero <= r0_zero;
    end

    assign r1_xin1 = r1_s1 ? -r1_in1 : r1_in1;
    assign r1_xin2 = r1_s2 ? -r1_in2 : r1_in2;

    data_extract #(
    	.N(N),
    	.es(es)
    ) uut_de1 (
    	.in(r1_xin1),
    	.rc(r1_rc1),
    	.regime(r1_regime1),
    	.exp(r1_e1),
    	.mant(r1_mant1),
    	.Lshift(r1_Lshift1)
    );

    data_extract #(
    	.N(N),
    	.es(es)
    ) uut_de2 (
    	.in(r1_xin2),
    	.rc(r1_rc2),
    	.regime(r1_regime2),
    	.exp(r1_e2),
    	.mant(r1_mant2),
    	.Lshift(r1_Lshift2)
    );

    assign r1_m1 = {r1_zero_tmp1, r1_mant1};
    assign r1_m2 = {r1_zero_tmp2, r1_mant2};

    // Large Checking and Assignment
    assign r1_in1_gt_in2 = (r1_xin1[N-2:0] >= r1_xin2[N-2:0]) ? '1 : '0;


    //  ___          __  __                   _     _                                        _       _   _   _     _
    // |__ \   _    |  \/  |                 | |   (_)                           /\         | |     | | (_) | |   (_)
    //    ) | (_)   | \  / |   __ _   _ __   | |_   _   ___   ___    __ _       /  \      __| |   __| |  _  | |_   _    ___    _ __
    //   / /        | |\/| |  / _` | | '_ \  | __| | | / __| / __|  / _` |     / /\ \    / _` |  / _` | | | | __| | |  / _ \  | '_ \
    //  / /_   _    | |  | | | (_| | | | | | | |_  | | \__ \ \__ \ | (_| |    / ____ \  | (_| | | (_| | | | | |_  | | | (_) | | | | |
    // |____| (_)   |_|  |_|  \__,_| |_| |_|  \__| |_| |___/ |___/  \__,_|   /_/    \_\  \__,_|  \__,_| |_|  \__| |_|  \___/  |_| |_|

    // Global pipeline signals
    logic r2_start, r2_s1, r2_s2, r2_inf, r2_zero;

    logic r2_rc1, r2_rc2, r2_in1_gt_in2, r2_ls, r2_op, r2_lrc, r2_src;
    logic [Bs-1:0] r2_regime1, r2_regime2, r2_lr, r2_sr;
    logic [es-1:0] r2_e1, r2_e2, r2_le, r2_se;
    logic [N-es:0] r2_m1, r2_m2, r2_lm, r2_sm;

    always @(posedge aclk)
    begin
       r2_start <= r1_start;
       r2_s1 <= r1_s1;
       r2_s2 <= r1_s2;
       r2_inf <= r1_inf;
       r2_zero <= r1_zero;
    end

    always @(posedge aclk) // Extracted data
    begin
        r2_rc1 <= r1_rc1;
        r2_rc2 <= r1_rc2;

        r2_regime1 <= r1_regime1;
        r2_regime2 <= r1_regime2;

        r2_e1 <= r1_e1;
        r2_e2 <= r1_e2;

        r2_m1 <= r1_m1;
        r2_m2 <= r1_m2;

        r2_in1_gt_in2 <= r1_in1_gt_in2;
    end

    assign r2_ls = r2_in1_gt_in2 ? r2_s1 : r2_s2;
    assign r2_op = r2_s1 ~^ r2_s2;

    assign r2_lrc = r2_in1_gt_in2 ? r2_rc1 : r2_rc2;
    assign r2_src = r2_in1_gt_in2 ? r2_rc2 : r2_rc1;

    // Regime
    assign r2_lr = r2_in1_gt_in2 ? r2_regime1 : r2_regime2;
    assign r2_sr = r2_in1_gt_in2 ? r2_regime2 : r2_regime1;

    // Exponent
    assign r2_le = r2_in1_gt_in2 ? r2_e1 : r2_e2;
    assign r2_se = r2_in1_gt_in2 ? r2_e2 : r2_e1;

    // Mantissa
    assign r2_lm = r2_in1_gt_in2 ? r2_m1 : r2_m2;
    assign r2_sm = r2_in1_gt_in2 ? r2_m2 : r2_m1;


    //  ____
    // |___ \
    //   __) |
    //  |__ <
    //  ___) |
    // |____/

    // Global pipeline signals
    logic r3_start, r3_inf, r3_zero;

    logic r3_ls, r3_op, r3_lrc, r3_src;
    logic [Bs-1:0] r3_lr, r3_sr;
    logic [es-1:0] r3_le, r3_se;
    logic [N-es:0] r3_lm, r3_sm;
    logic [Bs:0] r3_r_diff11, r3_r_diff12, r3_r_diff2;

    always @(posedge aclk)
    begin
       r3_start <= r2_start;
       r3_inf <= r2_inf;
       r3_zero <= r2_zero;
    end

    always @(posedge aclk) // Extracted data
    begin
        r3_ls <= r2_ls;
        r3_op <= r2_op;
        r3_lrc <= r2_lrc;
        r3_src <= r2_src;
        r3_lr <= r2_lr;
        r3_sr <= r2_sr;
        r3_le <= r2_le;
        r3_se <= r2_se;
        r3_lm <= r2_lm;
        r3_sm <= r2_sm;
    end

    // Exponent Difference: Lower Mantissa Right Shift Amount
    sub_N #(
    	.N(Bs)
    ) uut_sub1 (
    	r3_lr,
    	r3_sr,
    	r3_r_diff11
    );

    add_N #(
    	.N(Bs)
    ) uut_add1 (
    	r3_lr,
    	r3_sr,
    	r3_r_diff12
    );

    sub_N #(
    	.N(Bs)
    ) uut_sub2 (
    	r3_sr,
    	r3_lr,
    	r3_r_diff2
    );


    //  _  _
    // | || |
    // | || |_
    // |__   _|
    //    | |
    //    |_|
    //

    // Global pipeline signals
    logic r4_start, r4_inf, r4_zero;

    logic r4_ls, r4_op, r4_lrc, r4_src;
    logic [Bs-1:0] r4_lr;
    logic [es-1:0] r4_le, r4_se;
    logic [N-es:0] r4_lm, r4_sm;
    logic [Bs:0] r4_r_diff11, r4_r_diff12, r4_r_diff2, r4_r_diff, r4_lr_N;
    logic [N-1:0] r4_DSR_right_in;

    always @(posedge aclk)
    begin
       r4_start <= r3_start;
       r4_inf <= r3_inf;
       r4_zero <= r3_zero;
    end

    always @(posedge aclk) // Extracted data
    begin
        r4_ls <= r3_ls;
        r4_op <= r3_op;
        r4_lrc <= r3_lrc;
        r4_src <= r3_src;
        r4_le <= r3_le;
        r4_se <= r3_se;
        r4_lm <= r3_lm;
        r4_sm <= r3_sm;
        r4_lr <= r3_lr;

        r4_r_diff11 <= r3_r_diff11;
        r4_r_diff12 <= r3_r_diff12;
        r4_r_diff2 <= r3_r_diff2;
    end

    // DSR Right Shifting of Small Mantissa
    generate
        if (es >= 2)
        begin
            assign r4_DSR_right_in = {r4_sm, {es-1{1'b0}}};
        end
        else
        begin
            assign r4_DSR_right_in = r4_sm;
        end
    endgenerate

    assign r4_r_diff = r4_lrc ? (r4_src ? r4_r_diff11 : r4_r_diff12) : r4_r_diff2;
    assign r4_lr_N = r4_lrc ? {1'b0, r4_lr} : -{1'b0, r4_lr};


    //  _____
    // | ____|
    // | |__
    // |___ \
    //  ___) |
    // |____/

    // Global pipeline signals
    logic r5_start, r5_inf, r5_zero;

    logic r5_ls, r5_op;
    logic [es-1:0] r5_le, r5_se;
    logic [N-es:0] r5_lm;
    logic [Bs:0] r5_r_diff, r5_lr_N;
    logic [N-1:0] r5_DSR_right_in;
    logic [es+Bs+1:0] r5_diff;
    logic [Bs-1:0] r5_exp_diff;

    always @(posedge aclk)
    begin
       r5_start <= r4_start;
       r5_inf <= r4_inf;
       r5_zero <= r4_zero;
    end

    always @(posedge aclk)
    begin
        r5_r_diff <= r4_r_diff;
        r5_le <= r4_le;
        r5_se <= r4_se;
        r5_DSR_right_in <= r4_DSR_right_in;
        r5_lm <= r4_lm;
        r5_op <= r4_op;
        r5_ls <= r4_ls;
        r5_lr_N <= r4_lr_N;
    end

    sub_N #(
    	.N(es + Bs + 1)
    ) uut_sub_diff (
    	.a({r5_r_diff, r5_le}),
    	.b({{Bs+1{1'b0}}, r5_se}),
    	.c(r5_diff)
    );

    assign r5_exp_diff = (|r5_diff[es+Bs:Bs]) ? {Bs{1'b1}} : r5_diff[Bs-1:0];


    //    __
    //   / /
    //  / /_
    // | '_ \
    // | (_) |
    //  \___/

    // Global pipeline signals
    logic r6_start, r6_inf, r6_zero;

    logic r6_ls, r6_op;
    logic [N-1:0] r6_DSR_right_out, r6_DSR_right_in;
    logic [Bs-1:0] r6_DSR_e_diff, r6_exp_diff;
    logic [es-1:0] r6_le, r6_se;
    logic [N-es:0] r6_lm;
    logic [Bs:0] r6_r_diff, r6_lr_N;

    always @(posedge aclk)
    begin
        r6_start <= r5_start;
        r6_inf <= r5_inf;
        r6_zero <= r5_zero;
    end

    always @(posedge aclk)
    begin
        r6_r_diff <= r5_r_diff;
        r6_le <= r5_le;
        r6_se <= r5_se;
        r6_DSR_right_in <= r5_DSR_right_in;
        r6_lm <= r5_lm;
        r6_op <= r5_op;
        r6_ls <= r5_ls;
        r6_lr_N <= r5_lr_N;
        r6_exp_diff <= r5_exp_diff;
    end

    assign r6_DSR_e_diff = r6_exp_diff;

    DSR_right_N_S #(
    	.N(N),
    	.S(Bs)
    ) dsr1 (
    	.a(r6_DSR_right_in),
    	.b(r6_DSR_e_diff),
    	.c(r6_DSR_right_out)
    );


    //  ______
    // |____  |
    //     / /
    //    / /
    //   / /
    //  /_/
    //

    // Global pipeline signals
    logic r7_start, r7_inf, r7_zero;

    logic r7_ls, r7_op;
    logic [N-1:0] r7_DSR_right_out, r7_add_m_in1;
    logic [N:0] r7_add_m, r7_add_m1, r7_add_m2;
    logic [es-1:0] r7_le, r7_se;
    logic [N-es:0] r7_lm;
    logic [Bs:0] r7_lr_N;

    always @(posedge aclk)
    begin
        r7_start <= r6_start;
        r7_inf <= r6_inf;
        r7_zero <= r6_zero;
    end

    always @(posedge aclk)
    begin
        r7_le <= r6_le;
        r7_se <= r6_se;
        r7_lm <= r6_lm;
        r7_op <= r6_op;
        r7_ls <= r6_ls;
        r7_lr_N <= r6_lr_N;
        r7_DSR_right_out <= r6_DSR_right_out;
    end

    // Mantissa Addition
    generate
    	if (es >= 2)
        begin
    		assign r7_add_m_in1 = {r7_lm, {es-1{1'b0}}};
        end
    	else
        begin
    		assign r7_add_m_in1 = r7_lm;
        end
    endgenerate

    // Laurens: Dependency here (DSR_right_out, add_m_in1) (Pipeline stage?)

    add_N #(
    	.N(N)
    ) uut_add_m1 (
    	r7_add_m_in1,
    	r7_DSR_right_out,
    	r7_add_m1
    );

    sub_N #(
    	.N(N)
    ) uut_sub_m2 (
    	r7_add_m_in1,
    	r7_DSR_right_out,
    	r7_add_m2
    );

    // Laurens: Dependency here (add_m1, add_m2) (Pipeline stage?)
    assign r7_add_m = r7_op ? r7_add_m1 : r7_add_m2;


    //   ___
    //  / _ \
    // | (_) |
    //  > _ <
    // | (_) |
    //  \___/

    // Global pipeline signals
    logic r8_start, r8_inf, r8_zero;

    logic r8_ls;
    logic [1:0] r8_mant_ovf;
    logic [N-1:0] r8_LOD_in;
    logic [N:0] r8_add_m;
    logic [es-1:0] r8_le;
    logic [Bs-1:0] r8_left_shift;
    logic [Bs:0] r8_lr_N;

    always @(posedge aclk)
    begin
        r8_start <= r7_start;
        r8_inf <= r7_inf;
        r8_zero <= r7_zero;
    end

    always @(posedge aclk)
    begin
        r8_le <= r7_le;
        r8_ls <= r7_ls;
        r8_lr_N <= r7_lr_N;
        r8_add_m <= r7_add_m;
    end

    // LOD of mantissa addition result
    assign r8_mant_ovf = r8_add_m[N:N-1];
    assign r8_LOD_in = {(r8_add_m[N] | r8_add_m[N-1]), r8_add_m[N-2:0]};

    // Laurens: Dependency here (LOD_in) (Pipeline stage?)
    LOD_N #(
    	.N(N)
    ) l2 (
    	.in(r8_LOD_in),
    	.out(r8_left_shift)
    );


    //   ___
    //  / _ \
    // | (_) |
    //  \__, |
    //    / /
    //   /_/

    // Global pipeline signals
    logic r9_start, r9_inf, r9_zero;

    logic r9_ls;
    logic [1:0] r9_mant_ovf;
    logic [N-1:0] r9_DSR_left_out_t, r9_DSR_left_out;
    logic [N:0] r9_add_m;
    logic [es-1:0] r9_le;
    logic [Bs-1:0] r9_left_shift;
    logic [Bs:0] r9_lr_N;
    logic [es+Bs+1:0] r9_le_o_tmp, r9_le_o;

    always @(posedge aclk)
    begin
        r9_start <= r8_start;
        r9_inf <= r8_inf;
        r9_zero <= r8_zero;
    end

    always @(posedge aclk)
    begin
        r9_le <= r8_le;
        r9_ls <= r8_ls;
        r9_lr_N <= r8_lr_N;
        r9_add_m <= r8_add_m;

        r9_mant_ovf <= r8_mant_ovf;
        r9_left_shift <= r8_left_shift;
    end

    // DSR Left Shifting of mantissa result
    // Exponent and Regime Computation

    DSR_left_N_S #(
    	.N(N),
    	.S(Bs)
    ) dsl1 (
    	.a(r9_add_m[N:1]),
    	.b(r9_left_shift),
    	.c(r9_DSR_left_out_t)
    );

    sub_N #(
    	.N(es+Bs+1)
    ) sub3 (
    	.a({r9_lr_N, r9_le}),
    	.b({{es+1{1'b0}}, r9_left_shift}),
    	.c(r9_le_o_tmp)
    );

    // Laurens: Dependency here (DSR_left_out_t, le_o_tmp) (Pipeline stage?)
    assign r9_DSR_left_out = r9_DSR_left_out_t[N-1] ? r9_DSR_left_out_t[N-1:0] : {r9_DSR_left_out_t[N-2:0], 1'b0};


    add_mantovf #(
    	es+Bs+1
    ) uut_add_mantovf (
    	r9_le_o_tmp,
    	r9_mant_ovf[1],
    	r9_le_o
    );


    //  __    ___
    // /_ |  / _ \
    //  | | | | | |
    //  | | | | | |
    //  | | | |_| |
    //  |_|  \___/

    // Global pipeline signals
    logic r10_start, r10_inf, r10_zero;

    logic r10_ls;
    logic [N-1:0] r10_DSR_left_out;
    logic [es+Bs+1:0] r10_le_o;
    logic [es+Bs:0] r10_le_oN;
    logic [es-1:0] r10_e_o;
    logic [Bs-1:0] r10_r_o;
    logic [2*N-1:0] r10_tmp_o, r10_tmp1_o;

    always @(posedge aclk)
    begin
        r10_start <= r9_start;
        r10_inf <= r9_inf;
        r10_zero <= r9_zero;
    end

    always @(posedge aclk)
    begin
        r10_ls <= r9_ls;
        r10_DSR_left_out <= r9_DSR_left_out;
        r10_le_o <= r9_le_o;
    end

    assign r10_le_oN = r10_le_o[es+Bs] ? -r10_le_o : r10_le_o;
    assign r10_e_o = (r10_le_o[es+Bs] & |r10_le_oN[es-1:0]) ? r10_le_o[es-1:0] : r10_le_oN[es-1:0];
    assign r10_r_o = (~r10_le_o[es+Bs] || (r10_le_o[es+Bs] & |r10_le_oN[es-1:0])) ? (r10_le_oN[es+Bs-1:es] + 1'b1) : r10_le_oN[es+Bs-1:es];

    // Exponent and Mantissa Packing
    assign r10_tmp_o = { {N{~r10_le_o[es+Bs]}}, r10_le_o[es+Bs], r10_e_o, r10_DSR_left_out[N-2:es]};

    // Laurens: Dependency here (tmp_o, r_o) (Pipeline stage?)
    DSR_right_N_S #(
    	.N(2*N),
    	.S(Bs)
    ) dsr2 (
    	.a(r10_tmp_o),
    	.b(r10_r_o),
    	.c(r10_tmp1_o)
    );

    //  __   __         _____                         _   _
    // /_ | /_ |  _    |  __ \                       | | | |
    //  | |  | | (_)   | |__) |   ___   ___   _   _  | | | |_
    //  | |  | |       |  _  /   / _ \ / __| | | | | | | | __|
    //  | |  | |  _    | | \ \  |  __/ \__ \ | |_| | | | | |_
    //  |_|  |_| (_)   |_|  \_\  \___| |___/  \__,_| |_|  \__|

    // TODO Laurens: temporarily removed this pipeline stage

    // Global pipeline signals
    logic r11_start, r11_inf, r11_zero;

    logic r11_ls;
    logic [N-1:0] r11_DSR_left_out;
    logic [2*N-1:0] r11_tmp1_o, r11_tmp1_oN;

    always @(posedge aclk)
    begin
        r11_start <= r10_start;
        r11_inf <= r10_inf;
        r11_zero <= r10_zero;
    end

    always @(posedge aclk)
    begin
        r11_ls <= r10_ls;
        r11_DSR_left_out <= r10_DSR_left_out;
        r11_tmp1_o <= r10_tmp1_o;
    end

    assign r11_tmp1_oN = r11_ls ? -r11_tmp1_o : r11_tmp1_o;

    // Final Output
    assign zero = r11_zero;
    assign inf = r11_inf;
    assign result = (r11_inf | r11_zero | (~r11_DSR_left_out[N-1])) ? {r11_inf, {N-1{1'b0}}} : {r11_ls, r11_tmp1_oN[N-1:1]};
    assign done = r11_start;

endmodule
