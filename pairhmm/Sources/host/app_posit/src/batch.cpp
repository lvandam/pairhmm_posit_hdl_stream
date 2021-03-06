#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <posit/posit>
#include <iostream>

#include "batch.hpp"
#include "utils.hpp"
#include "defines.hpp"

using namespace std;
using namespace sw::unum;

// const char XDATA[] = "GTCGCGTACCTGTGGTATAAGAGCTTTGGGCTTTCGCAGTCCCGACTAGTCTGAACTTACCCAGACTCCCAGTCTGTAGTGAATAAGGTGAAAAGATTTGGTTTGCCTCAAACATCCCAGACGCCGCGCGGACCTCTGGAAGACGGTAAGACAGTCTG";
// const char YDATA[] = "CGGAAACTCATAATGAGGGCGAAGCAGGTCTGCCGCTAGGACAAGGCTTAATAACCCAAGTGTGACATCGTTCTTACGGAAGTAGGTAATGTCCCT";

posit<NBITS, ES> random_number(float offset, float dev) {
    float num_float;
    posit<NBITS, 2> num_posit_2;
    posit<NBITS, 3> num_posit_3;

    do {
        num_float = offset + (rand() * dev / RAND_MAX);
        num_posit_2 = num_float;
        num_posit_3 = num_float;
    } while (num_posit_2 != num_float || num_posit_3 != num_float);

    return posit<NBITS, ES>(num_float);
}

uint32_t getProb(unsigned char rb) {
    // uint32_t prob_A = 0x39201000;
    // uint32_t prob_C = 0x39202000;
    // uint32_t prob_T = 0x39203000;
    // uint32_t prob_G = 0x39204000;
    //
    // if(rb == 'A') return prob_A;
    // if(rb == 'C') return prob_C;
    // if(rb == 'T') return prob_T;
    // if(rb == 'G') return prob_G;
    // return 0x39200000;
    uint32_t prob_A = 0x39038FA0;
    uint32_t prob_C = 0x398B1970;
    uint32_t prob_T = 0x387CDA80;
    uint32_t prob_G = 0x38393A00;

    if(rb == 'A') return prob_A;
    if(rb == 'C') return prob_C;
    if(rb == 'T') return prob_T;
    if(rb == 'G') return prob_G;
    return 0x38741A00;
}

void fill_batch(t_batch *batch, string& x_string, string& y_string, int x, int y, float initial) {
    t_inits *init = batch->init;
    t_bbase *read = batch->read;
    t_bbase *hapl = batch->hapl;
    t_probs *prob = batch->prob;

    int xp = px(x, y); // Padded read size
    int xbp = pbp(xp); // Padded base pair (how many reads)
    int yp = py(y); // Padded haplotype size
    int ybp = pbp(yp); // Padded base pair (how many haplos)

    init->batch_bytes = calc_batch_size(x, y, PES);
    init->x_size = xp;
    init->x_padded = xp;
    init->x_bppadded = xbp;
    init->y_size = yp;
    init->y_padded = ybp;

    posit<NBITS, ES> zeta(0), eta(0), epsilon(0), delta(0), beta(0), alpha(0), distm_diff(0), distm_simi(0);

    for (int k = 0; k < PIPE_DEPTH; k++) {
        posit<NBITS, ES> initial_posit(initial / yp);

        // Get raw bits to send to HW
        init->initials[k] = to_uint(initial_posit);

        for (int i = 0; i < xbp; i++) {
            if (i < x) {
                // read[i].base[k] = XDATA[i + k];
                read[i].base[k] = x_string[i + k];
            } else // padding:
            {
                read[i].base[k] = 'S';
            }
        }

        for (int i = 0; i < ybp; i++) {
            if (i < y) {
                // hapl[i].base[k] = YDATA[i + k];
                hapl[i].base[k] = y_string[i + k];
            } else {
                hapl[i].base[k] = 'S';
            }
        }

        for (int i = 0; i < xp; i++) {
            srand((k * PIPE_DEPTH + i) * xp + x * 9949 + y * 9133); // Seed number generator

            eta = random_number(0.5, 0.1);
            // if(k==0)
            //         cout << "generated: " << hexstring(eta.collect()) << endl;
            zeta = random_number(0.125, 0.05);
            epsilon = random_number(0.5, 0.1);
            delta = random_number(0.125, 0.05);
            beta = random_number(0.5, 0.1);
            alpha = random_number(0.125, 0.05);
            distm_diff = random_number(0.5, 0.1);
            distm_simi = random_number(0.125, 0.05);

            // eta.set_raw_bits(getProb(read[i].base[k]));
            // zeta.set_raw_bits(getProb(read[i].base[k]));
            // epsilon.set_raw_bits(getProb(read[i].base[k]));
            // delta.set_raw_bits(getProb(read[i].base[k]));
            // beta.set_raw_bits(getProb(read[i].base[k]));
            // alpha.set_raw_bits(getProb(read[i].base[k]));
            // distm_diff.set_raw_bits(0x00000000);// distm_diff.set_raw_bits(getProb(read[i].base[k]));
            // distm_simi.set_raw_bits(getProb(read[i].base[k]));

            prob[i * PIPE_DEPTH + k].p[0].b = (int) eta.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[1].b = (int) zeta.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[2].b = (int) epsilon.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[3].b = (int) delta.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[4].b = (int) beta.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[5].b = (int) alpha.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[6].b = (int) distm_diff.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[7].b = (int) distm_simi.collect().to_ulong();
        }
    }
} // fill_batch

void init_batch_address(t_batch *b, void *batch, int x, int y) {
    b->init = (t_inits *) ((uint64_t) batch);
    b->read = (t_bbase *) ((uint64_t) b->init + CACHELINE_BYTES);
    b->hapl = (t_bbase *) ((uint64_t) b->read + (uint64_t) pbp(px(x, y)) * (uint64_t) sizeof(t_bbase));
    b->prob = (t_probs *) ((uint64_t) b->hapl + (uint64_t) pbp(py(y)) * (uint64_t) sizeof(t_bbase));
}


size_t calc_batch_size(int x, int y, int e) {
    // Pad X and Y if necessary
    int xpadded = px(x, y);
    int ypadded = py(y);

    // Pad X and Y basepairs
    int ybps = pbp(ypadded);
    int xbps = pbp(xpadded);

    size_t init_size = CACHELINE_BYTES;

    size_t xbases = xbps * sizeof(t_bbase);
    size_t ybases = ybps * sizeof(t_bbase);

    size_t prob_size = xpadded * PIPE_DEPTH * sizeof(t_probs);

    // Determine size of batch in bytes.
    size_t batch_size = init_size + xbases + ybases + prob_size;

    return (batch_size);
}
