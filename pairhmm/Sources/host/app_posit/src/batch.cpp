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

const char XDATA[] = "ACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGAC";
const char YDATA[] = "GTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTAC";

void fill_batch(t_batch *batch, int x, int y, float initial) {
    t_inits *init = batch->init;
    t_bbase *read = batch->read;
    t_bbase *hapl = batch->hapl;
    t_probs *prob = batch->prob;

    int xp = px(x, y);
    int xbp = pbp(xp);
    int yp = py(y);
    int ybp = pbp(yp);

    init->batch_bytes = calc_batch_size(x, y, PES);
    init->x_size = xp;
    init->x_padded = xp;
    init->x_bppadded = xbp;
    init->y_size = yp;
    init->y_padded = ybp;

    posit<NBITS,ES> zeta(0), eta(0), upsilon(0), delta(0), beta(0), alpha(0), distm_diff(0), distm_simi(0);

    for (int k = 0; k < PIPE_DEPTH; k++) {
        posit<NBITS, ES> initial_posit(initial);
        initial_posit += k;

        // Get raw bits to send to HW
        init->initials[k] = to_uint(initial_posit);

        for (int i = 0; i < xbp; i++) {
            if (i < x) {
                read[i].base[k] = XDATA[i + k];
            } else // padding:
            {
                read[i].base[k] = 'S';
            }
        }

        for (int i = 0; i < ybp; i++) {
            if (i < y) {
                hapl[i].base[k] = YDATA[i + k];
            } else {
                hapl[i].base[k] = 'S';
            }
        }

        for (int i = 0; i < xp; i++) {
            srand((k * PIPE_DEPTH + i) * xp + x * 9949 + y * 9133); // Seed number generator

            zeta = 0.5 + (rand() * 0.1 / RAND_MAX);
            eta = 0.125 + (rand() * 0.05 / RAND_MAX);
            upsilon = 0.5 + (rand() * 0.1 / RAND_MAX);
            delta = 0.125 + (rand() * 0.05 / RAND_MAX);
            beta = 0.5 + (rand() * 0.1 / RAND_MAX);
            alpha = 0.125 + (rand() * 0.05 / RAND_MAX);
            distm_diff = 0.5 + (rand() * 0.1 / RAND_MAX);
            distm_simi = 0.125 + (rand() * 0.05 / RAND_MAX);

            prob[i * PIPE_DEPTH + k].p[0].b = (int)zeta.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[1].b = (int)eta.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[2].b = (int)upsilon.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[3].b = (int)delta.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[4].b = (int)beta.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[5].b = (int)alpha.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[6].b = (int)distm_diff.collect().to_ulong();
            prob[i * PIPE_DEPTH + k].p[7].b = (int)distm_simi.collect().to_ulong();
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
