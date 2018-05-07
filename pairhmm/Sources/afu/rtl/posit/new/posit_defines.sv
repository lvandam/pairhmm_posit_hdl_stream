// Laurens van Dam
// Delft University of Technology
// May 2018

package posit_defines;

parameter NBITS = 32;
parameter ES = 2;
parameter FBITS = NBITS - 3 - ES; // Size of fraction bits
parameter FHBITS = FBITS + 1; // Size of fraction + hidden bit
parameter MBITS = 2 *  FHBITS; // Size of multiplier output
parameter ABITS = FBITS + 4; // Size of addend

typedef struct {
    logic sign;
    logic signed [7:0] scale;
    logic [ES-1:0] exponent;
    logic [FBITS-1:0] fraction;
    logic inf;
    logic zero;
} value;

typedef struct {
    logic sign;
    logic signed [8:0] scale;
    logic [ES-1:0] exponent;
    logic [MBITS-1:0] fraction;
    logic inf;
    logic zero;
} value_product;

typedef struct {
    logic sign;
    logic signed [8:0] scale;
    logic [ES-1:0] exponent;
    logic [ABITS-1:0] fraction;
    logic inf;
    logic zero;
} value_sum;

endpackage : posit_defines
