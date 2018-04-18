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
            prob[i * PIPE_DEPTH + k].p[0].b = (0x38000000 | (k << 4) | (i << 8) |
                                               ((rand() / (RAND_MAX / 256)) << 8)); // zeta
            prob[i * PIPE_DEPTH + k].p[1].b = (0x28000001 | (k << 4) | (i << 8) |
                                               ((rand() / (RAND_MAX / 256)) << 8)); // eta
            prob[i * PIPE_DEPTH + k].p[2].b = (0x38000002 | (k << 4) | (i << 8) |
                                               ((rand() / (RAND_MAX / 256)) << 8)); // upsilon
            prob[i * PIPE_DEPTH + k].p[3].b = (0x28000003 | (k << 4) | (i << 8) |
                                               ((rand() / (RAND_MAX / 256)) << 8)); // delta
            prob[i * PIPE_DEPTH + k].p[4].b = (0x38000004 | (k << 4) | (i << 8) |
                                               ((rand() / (RAND_MAX / 256)) << 8)); // beta
            prob[i * PIPE_DEPTH + k].p[5].b = (0x28000005 | (k << 4) | (i << 8) |
                                               ((rand() / (RAND_MAX / 256)) << 8)); // alpha
            prob[i * PIPE_DEPTH + k].p[6].b = (0x38000006 | (k << 4) | (i << 8) |
                                               ((rand() / (RAND_MAX / 256)) << 8)); // distm_diff
            prob[i * PIPE_DEPTH + k].p[7].b = (0x28000007 | (k << 4) | (i << 8) |
                                               ((rand() / (RAND_MAX / 256)) << 8)); // distm_simi
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
