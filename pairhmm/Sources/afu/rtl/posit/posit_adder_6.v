`timescale 1ns / 1ps
`default_nettype wire

module posit_adder (aclk, in1, in2, start, result, inf, zero, done);

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
        r0_in1 <= in1;
        r0_in2 <= in2;
        r0_start <= start;

        r0_s1 <= in1[N-1];
        r0_s2 <= in2[N-1];

        r0_zero_tmp1 <= |in1[N-2:0];
        r0_zero_tmp2 <= |in2[N-2:0];
    end


    assign r0_inf1 = in1[N-1] & (~r0_zero_tmp1);
    assign r0_inf2 = in2[N-1] & (~r0_zero_tmp2);

    assign r0_zero1 = ~(in1[N-1] | r0_zero_tmp1);
    assign r0_zero2 = ~(in2[N-1] | r0_zero_tmp2);

    assign r0_inf = r0_inf1 | r0_inf2;
    assign r0_zero = r0_zero1 & r0_zero2;

    //  __         _____            _               ______          _                           _     _
    // /_ |  _    |  __ \          | |             |  ____|        | |                         | |   (_)
    //  | | (_)   | |  | |   __ _  | |_    __ _    | |__    __  __ | |_   _ __    __ _    ___  | |_   _    ___    _ __
    //  | |       | |  | |  / _` | | __|  / _` |   |  __|   \ \/ / | __| | '__|  / _` |  / __| | __| | |  / _ \  | '_ \
    //  | |  _    | |__| | | (_| | | |_  | (_| |   | |____   >  <  | |_  | |    | (_| | | (__  | |_  | | | (_) | | | | |
    //  |_| (_)   |_____/   \__,_|  \__|  \__,_|   |______| /_/\_\  \__| |_|     \__,_|  \___|  \__| |_|  \___/  |_| |_|

    logic [N-1:0] r1_in1, r1_in2;
    logic r1_start, r1_s1, r1_s2, r1_zero_tmp1, r1_zero_tmp2, r1_inf, r1_zero;

    logic r1_rc1, r1_rc2;
    logic [Bs-1:0] r1_regime1, r1_regime2, r1_Lshift1, r1_Lshift2;
    logic [es-1:0] r1_e1, r1_e2;
    logic [N-es-1:0] r1_mant1, r1_mant2;
    logic [N-es:0] r1_m1, r1_m2;
    logic r1_in1_gt_in2;
    logic [N-1:0] r1_xin1, r1_xin2;

    always @(posedge aclk) // Global pipeline signals
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

    // TODO Laurens: assign might break things?
    assign r1_m1 = {r1_zero_tmp1, r1_mant1};
    assign r1_m2 = {r1_zero_tmp2, r1_mant2};

    // Large Checking and Assignment
    // TODO Laurens: assign might break things?
    assign r1_in1_gt_in2 = r1_xin1[N-2:0] >= r1_xin2[N-2:0] ? '1 : '0;

    //  ___          __  __                   _     _                                        _       _   _   _     _
    // |__ \   _    |  \/  |                 | |   (_)                           /\         | |     | | (_) | |   (_)
    //    ) | (_)   | \  / |   __ _   _ __   | |_   _   ___   ___    __ _       /  \      __| |   __| |  _  | |_   _    ___    _ __
    //   / /        | |\/| |  / _` | | '_ \  | __| | | / __| / __|  / _` |     / /\ \    / _` |  / _` | | | | __| | |  / _ \  | '_ \
    //  / /_   _    | |  | | | (_| | | | | | | |_  | | \__ \ \__ \ | (_| |    / ____ \  | (_| | | (_| | | | | |_  | | | (_) | | | | |
    // |____| (_)   |_|  |_|  \__,_| |_| |_|  \__| |_| |___/ |___/  \__,_|   /_/    \_\  \__,_|  \__,_| |_|  \__| |_|  \___/  |_| |_|

    logic [N-1:0] r2_in1, r2_in2;
    logic r2_start, r2_s1, r2_s2, r2_inf, r2_zero;

    logic r2_rc1, r2_rc2;
    logic [Bs-1:0] r2_regime1, r2_regime2;
    logic [es-1:0] r2_e1, r2_e2;
    logic [N-es:0] r2_m1, r2_m2;
    logic r2_in1_gt_in2;


    logic r2_ls, r2_op, r2_lrc, r2_src;
    // Regime
    logic [Bs-1:0] r2_lr, r2_sr;
    // Exponent
    logic [es-1:0] r2_le, r2_se;
    // Mantissa
    logic [N-es:0] r2_lm, r2_sm;

    always @(posedge aclk) // Global pipeline signals
    begin
       r2_in1 <= r1_in1;
       r2_in2 <= r1_in2;
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

    //
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

    // Exponent Difference: Lower Mantissa Right Shift Amount
    logic [Bs:0] r2_r_diff11, r2_r_diff12, r2_r_diff2;

    sub_N #(
    	.N(Bs)
    ) uut_sub1 (
    	r2_lr,
    	r2_sr,
    	r2_r_diff11
    );

    add_N #(
    	.N(Bs)
    ) uut_add1 (
    	r2_lr,
    	r2_sr,
    	r2_r_diff12
    );

    sub_N #(
    	.N(Bs)
    ) uut_sub2 (
    	r2_sr,
    	r2_lr,
    	r2_r_diff2
    );

    // DSR Right Shifting of Small Mantissa
    logic [N-1:0] r2_DSR_right_in;
    generate
        if (es >= 2)
        begin
            assign r2_DSR_right_in = {r2_sm, {es-1{1'b0}}};
        end
        else
        begin
            assign r2_DSR_right_in = r2_sm;
        end
    endgenerate

    logic [Bs:0] r2_r_diff, r2_lr_N;

    assign r2_r_diff = r2_lrc ? (r2_src ? r2_r_diff11 : r2_r_diff12) : r2_r_diff2;
    assign r2_lr_N = r2_lrc ? {1'b0, r2_lr} : -{1'b0, r2_lr};



















    // Laurens: Dependency here (Pipeline stage?)
    logic [es+Bs+1:0] diff;

    sub_N #(
    	.N(es + Bs + 1)
    ) uut_sub_diff (
    	.a({r2_r_diff, r2_le}),
    	.b({{Bs+1{1'b0}}, r2_se}),
    	.c(diff)
    );

    // Laurens: Dependency here (diff) (Pipeline stage?)
    logic [Bs-1:0] exp_diff;
    assign exp_diff = (|diff[es+Bs:Bs]) ? {Bs{1'b1}} : diff[Bs-1:0];

    // Laurens: Dependency here (exp_diff) (Pipeline stage?)
    logic [N-1:0] DSR_right_out;
    logic [Bs-1:0] DSR_e_diff;
    assign DSR_e_diff = exp_diff;

    DSR_right_N_S #(
    	.N(N),
    	.S(Bs)
    ) dsr1 (
    	.a(r2_DSR_right_in),
    	.b(DSR_e_diff),
    	.c(DSR_right_out)
    );

    // Mantissa Addition
    logic [N-1:0] add_m_in1;
    generate
    	if (es >= 2)
        begin
    		assign add_m_in1 = {r2_lm, {es-1{1'b0}}};
        end
    	else
        begin
    		assign add_m_in1 = r2_lm;
        end
    endgenerate

    // Laurens: Dependency here (DSR_right_out, add_m_in1) (Pipeline stage?)
    logic [N:0] add_m1, add_m2;

    add_N #(
    	.N(N)
    ) uut_add_m1 (
    	add_m_in1,
    	DSR_right_out,
    	add_m1
    );

    sub_N #(
    	.N(N)
    ) uut_sub_m2 (
    	add_m_in1,
    	DSR_right_out,
    	add_m2
    );

    // Laurens: Dependency here (add_m1, add_m2) (Pipeline stage?)
    logic [N:0] add_m;
    assign add_m = r2_op ? add_m1 : add_m2;

    // Laurens: Dependency here (add_m) (Pipeline stage?)
    // LOD of mantissa addition result
    logic [1:0] mant_ovf;
    assign mant_ovf = add_m[N:N-1];

    logic [N-1:0] LOD_in;
    assign LOD_in = {(add_m[N] | add_m[N-1]), add_m[N-2:0]};

    // Laurens: Dependency here (LOD_in) (Pipeline stage?)
    logic [Bs-1:0] left_shift;
    LOD_N #(
    	.N(N)
    ) l2 (
    	.in(LOD_in),
    	.out(left_shift)
    );

    // Laurens: Dependency here (left_shift) (Pipeline stage?)
    // DSR Left Shifting of mantissa result
    // Exponent and Regime Computation
    logic [N-1:0] DSR_left_out_t;
    logic [es+Bs+1:0] le_o_tmp;

    DSR_left_N_S #(
    	.N(N),
    	.S(Bs)
    ) dsl1 (
    	.a(add_m[N:1]),
    	.b(left_shift),
    	.c(DSR_left_out_t)
    );

    sub_N #(
    	.N(es+Bs+1)
    ) sub3 (
    	.a({r2_lr_N, r2_le}),
    	.b({{es+1{1'b0}}, left_shift}),
    	.c(le_o_tmp)
    );

    // Laurens: Dependency here (DSR_left_out_t, le_o_tmp) (Pipeline stage?)
    logic [N-1:0] DSR_left_out;
    assign DSR_left_out = DSR_left_out_t[N-1] ? DSR_left_out_t[N-1:0] : {DSR_left_out_t[N-2:0], 1'b0};

    logic [es+Bs+1:0] le_o;

    add_mantovf #(
    	es+Bs+1
    ) uut_add_mantovf (
    	le_o_tmp,
    	mant_ovf[1],
    	le_o
    );

    // Laurens: Dependency here (le_o) (Pipeline stage?)
    logic [es+Bs:0] le_oN;
    assign le_oN = le_o[es+Bs] ? -le_o : le_o;
    logic [es-1:0] e_o;
    assign e_o = (le_o[es+Bs] & |le_oN[es-1:0]) ? le_o[es-1:0] : le_oN[es-1:0];
    logic [Bs-1:0] r_o;
    assign r_o = (~le_o[es+Bs] || (le_o[es+Bs] & |le_oN[es-1:0])) ? (le_oN[es+Bs-1:es] + 1'b1) : le_oN[es+Bs-1:es];

    // Exponent and Mantissa Packing
    logic [2*N-1:0] tmp_o;
    assign tmp_o = { {N{~le_o[es+Bs]}}, le_o[es+Bs], e_o, DSR_left_out[N-2:es]};
    logic [2*N-1:0] tmp1_o;

    // Laurens: Dependency here (tmp_o, r_o) (Pipeline stage?)
    DSR_right_N_S #(
    	.N(2*N),
    	.S(Bs)
    ) dsr2 (
    	.a(tmp_o),
    	.b(r_o),
    	.c(tmp1_o)
    );

    //  _____                         _   _
    // |  __ \                       | | | |
    // | |__) |   ___   ___   _   _  | | | |_
    // |  _  /   / _ \ / __| | | | | | | | __|
    // | | \ \  |  __/ \__ \ | |_| | | | | |_
    // |_|  \_\  \___| |___/  \__,_| |_|  \__|

    // Laurens: Dependency here (tmp1_o) (Pipeline stage?)
    logic [2*N-1:0] tmp1_oN;
    assign tmp1_oN = r2_ls ? -tmp1_o : tmp1_o;

    // Final Output
    assign zero = r2_zero;
    assign inf = r2_inf;
    assign result = r2_inf | r2_zero | (~DSR_left_out[N-1]) ? {r2_inf, {N-1{1'b0}}} : {r2_ls, tmp1_oN[N-1:1]};
    assign done = r2_start;

endmodule
