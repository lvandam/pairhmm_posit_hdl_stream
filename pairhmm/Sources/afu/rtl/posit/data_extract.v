`include "posit_pkg.sv"

module data_extract(in, rc, regime, exp, frac);

    parameter N = 16;
    parameter Bs = log2(N);
    parameter es = 2;
    input [N-1:0] in;
    output rc;
    output [Bs-1:0] regime;
    output [es-1:0] exp;
    output [N-es-1:0] frac;

    logic [Bs-1:0] Lshift;
    wire [N-1:0] xin = in;

    // Regime check bit (rc), determining if regime field uses leading 0 or 1
    assign rc = xin[N-2];

    // Leading One/Zero detection
    wire [Bs-1:0] k0, k1;

    LOD_N #(
        .N(N)
    ) xinst_k0(
        .in({xin[N-2:0], 1'b0}),
        .out(k0)
    );

    LZD_N #(
        .N(N)
    ) xinst_k1(
        .in({xin[N-3:0], 2'b0}),
        .out(k1)
    );

    // Determine absolute regime value depending on leading 0 or 1 regime bit
    assign regime = xin[N-2] ? k1 : k0;
    // Regime left shift amount
    assign Lshift = xin[N-2] ? (k1 + 1) : k0;

    // Left shift so that the regime bits are removed, putting the exponent bits at MSB followed by fraction bits
    wire [N-1:0] xin_no_regime;
    DSR_left_N_S #(
        .N(N),
        .S(Bs)
    ) ls (
        .a({xin[N-3:0], 2'b0}),
        .b(Lshift),
        .c(xin_no_regime)
    );

    assign exp = xin_no_regime[N-1:N-es];
    assign frac = xin_no_regime[N-es-1:0];

endmodule
