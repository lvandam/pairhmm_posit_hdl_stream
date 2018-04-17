`timescale 1ns / 1ps
`default_nettype wire

module posit_mult_4 (aclk, in1, in2, start, result, inf, zero, done);

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

    parameter N = 16;
    parameter Bs = log2(N);
    parameter es = 3;

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

    logic r0_rc1, r0_rc2;
    logic [Bs-1:0] r0_regime1, r0_regime2, r0_Lshift1, r0_Lshift2;
    logic [es-1:0] r0_e1, r0_e2;
    logic [N-es-1:0] r0_mant1, r0_mant2;
    logic [N-1:0] r0_xin1, r0_xin2;
    logic r0_mult_s;
    logic [N-es:0] r0_m1, r0_m2;

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

    // Data Extraction
    assign r0_xin1 = r0_s1 ? -r0_in1 : r0_in1;
    assign r0_xin2 = r0_s2 ? -r0_in2 : r0_in2;
    assign r0_mult_s = r0_s1 ^ r0_s2;

    // TODO maybe remove Lshift output?
    data_extract #(.N(N), .es(es)) uut_de1 (
        .in(r0_xin1),
        .rc(r0_rc1),
        .regime(r0_regime1),
        .exp(r0_e1),
        .mant(r0_mant1),
        .Lshift(r0_Lshift1)
    );

    data_extract #(.N(N), .es(es)) uut_de2 (
        .in(r0_xin2),
        .rc(r0_rc2),
        .regime(r0_regime2),
        .exp(r0_e2),
        .mant(r0_mant2),
        .Lshift(r0_Lshift2)
    );

    assign r0_m1 = {r0_zero_tmp1, r0_mant1};
    assign r0_m2 = {r0_zero_tmp2, r0_mant2};


    //  __
    // /_ |
    //  | |
    //  | |
    //  | |
    //  |_|

    logic r1_start, r1_inf, r1_zero, r1_rc1, r1_rc2, r1_mult_s;
    logic [Bs-1:0] r1_regime1, r1_regime2;
    logic [es-1:0] r1_e1, r1_e2;
    logic [N-es:0] r1_m1, r1_m2;
    logic [2*(N-es)+1:0] r1_mult_m;

    always @(posedge aclk)
    begin
        r1_start <= r0_start;
        r1_inf <= r0_inf;
        r1_zero <= r0_zero;
        r1_m1 <= r0_m1;
        r1_m2 <= r0_m2;
        r1_regime1 <= r0_regime1;
        r1_regime2 <= r0_regime2;
        r1_rc1 <= r0_rc1;
        r1_rc2 <= r0_rc2;
        r1_e1 <= r0_e1;
        r1_e2 <= r0_e2;
        r1_mult_s <= r0_mult_s;
    end

    // Mantissa Computation
    assign r1_mult_m = r1_m1 * r1_m2;


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

    logic r2_mult_m_ovf;
    logic [2*(N-es)+1:0] r2_mult_mN;
    logic [Bs+1:0] r2_r1, r2_r2;
    logic [Bs+es+1:0] r2_mult_e;
    logic [es+Bs:0] r2_mult_eN;
    logic [es-1:0] r2_e_o;
    logic [Bs:0] r2_r_o;
    logic [2*N-1:0] r2_tmp_o;

    always @(posedge aclk)
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

    always @(posedge aclk)
    begin
        r2_mult_m <= r1_mult_m;
    end

    assign r2_mult_m_ovf = r2_mult_m[2*(N-es)+1];
    assign r2_mult_mN = ~r2_mult_m_ovf ? r2_mult_m << 1'b1 : r2_mult_m;

    assign r2_r1 = r2_rc1 ? {2'b0, r2_regime1} : -r2_regime1;
    assign r2_r2 = r2_rc2 ? {2'b0, r2_regime2} : -r2_regime2;
    assign r2_mult_e  =  {r2_r1, r2_e1} + {r2_r2, r2_e2} + r2_mult_m_ovf;

    // Exponent and Regime Computation
    assign r2_mult_eN = r2_mult_e[es+Bs+1] ? -r2_mult_e : r2_mult_e;
    assign r2_e_o = (r2_mult_e[es+Bs+1] & |r2_mult_eN[es-1:0]) ? r2_mult_e[es-1:0] : r2_mult_eN[es-1:0];
    assign r2_r_o = (~r2_mult_e[es+Bs+1] || (r2_mult_e[es+Bs+1] & |r2_mult_eN[es-1:0])) ? (r2_mult_eN[es+Bs:es] + 1'b1) : r2_mult_eN[es+Bs:es];

    // Exponent and Mantissa Packing
    assign r2_tmp_o = { { N{~r2_mult_e[es+Bs+1]} }, r2_mult_e[es+Bs+1], r2_e_o, r2_mult_mN[2*(N-es):N-es+2] };


    //  ____
    // |___ \
    //   __) |
    //  |__ <
    //  ___) |
    // |____/

    logic r3_start, r3_inf, r3_zero, r3_mult_s;

    logic [2*(N-es)+1:0] r3_mult_mN;
    logic [Bs:0] r3_r_o;
    logic [2*N-1:0] r3_tmp_o, r3_tmp1_o, r3_tmp1_oN;

    always @(posedge aclk)
    begin
        r3_start <= r2_start;
        r3_inf <= r2_inf;
        r3_zero <= r2_zero;
        r3_mult_s <= r2_mult_s;
    end

    always @(posedge aclk)
    begin
        r3_tmp_o <= r2_tmp_o;
        r3_r_o <= r2_r_o;
        r3_mult_mN <= r2_mult_mN;
    end

    // Including Regime bits in Exponent-Mantissa Packing
    DSR_right_N_S #(
        .N(2*N),
        .S(Bs+1)
    ) dsr2 (
        .a(r3_tmp_o),
        .b(r3_r_o[Bs] ? {Bs{1'b1}} : r3_r_o),
        .c(r3_tmp1_o)
    );

    // Final Output
    assign r3_tmp1_oN = r3_mult_s ? -r3_tmp1_o : r3_tmp1_o;

    assign result = r3_inf | r3_zero | (~r3_mult_mN[2*(N-es)+1]) ? {r3_inf, {N-1{1'b0}}} : {r3_mult_s, r3_tmp1_oN[N-1:1]};
    assign done = r3_start;

endmodule
