#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <posit/posit>
#include <iostream>

#include "batch.hpp"
#include "utils.hpp"
#include "config.hpp"

using namespace std;
using namespace sw::unum;

const char XDATA[] = "ACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGAC";
const char YDATA[] = "GTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTAC";

void fill_batch(t_batch *batch, int x, int y, float initial)
{
    t_inits *init = batch->init;
    t_bbase *read = batch->read;
    t_bbase *hapl = batch->hapl;
    t_probs *prob = batch->prob;

    int     xp  = px(x, y);
    int     xbp = pbp(xp);
    int     yp  = py(y);
    int     ybp = pbp(yp);

    init->batch_bytes = calc_batch_size(x, y, PES);
    init->x_size      = xp;
    init->x_padded    = xp;
    init->x_bppadded  = xbp;
    init->y_size      = yp;
    init->y_padded    = ybp;

    for (int k = 0; k < PIPE_DEPTH; k++)
    {
        posit<NBITS,ES> initial_posit(initial);
        initial_posit += k;

        // Get raw bits to send to HW
        init->initials[k] = to_uint(initial_posit);

        for (int i = 0; i < xbp; i++)
        {
            if (i < x)
            {
                read[i].base[k] = XDATA[i + k];
            }
            else // padding:
            {
                read[i].base[k] = 'S';
            }
        }

        for (int i = 0; i < ybp; i++)
        {
            if (i < y)
            {
                hapl[i].base[k] = YDATA[i + k];
            }
            else
            {
                hapl[i].base[k] = 'S';
            }
        }

        for (int i = 0; i < xp; i++)
        {
            prob[i * PIPE_DEPTH + k].p[0].b = (0x38000000 | (k << 4) | (i << 8) | ((rand() / (RAND_MAX / 256)) << 8)); // zeta
            prob[i * PIPE_DEPTH + k].p[1].b = (0x28000001 | (k << 4) | (i << 8) | ((rand() / (RAND_MAX / 256)) << 8)); // eta
            prob[i * PIPE_DEPTH + k].p[2].b = (0x38000002 | (k << 4) | (i << 8) | ((rand() / (RAND_MAX / 256)) << 8)); // upsilon
            prob[i * PIPE_DEPTH + k].p[3].b = (0x28000003 | (k << 4) | (i << 8) | ((rand() / (RAND_MAX / 256)) << 8)); // delta
            prob[i * PIPE_DEPTH + k].p[4].b = (0x38000004 | (k << 4) | (i << 8) | ((rand() / (RAND_MAX / 256)) << 8)); // beta
            prob[i * PIPE_DEPTH + k].p[5].b = (0x28000005 | (k << 4) | (i << 8) | ((rand() / (RAND_MAX / 256)) << 8)); // alpha
            prob[i * PIPE_DEPTH + k].p[6].b = (0x38000006 | (k << 4) | (i << 8) | ((rand() / (RAND_MAX / 256)) << 8)); // distm_diff
            prob[i * PIPE_DEPTH + k].p[7].b = (0x28000007 | (k << 4) | (i << 8) | ((rand() / (RAND_MAX / 256)) << 8)); // distm_simi
        }
    }
} // fill_batch


void calculate_mids(t_batch *batch, int pair, int r, int c, t_posit_matrix &M, t_posit_matrix &I, t_posit_matrix &D)
{
    int     w     = c + 1;
    t_inits *init = batch->init;
    t_bbase *read = batch->read;
    t_bbase *hapl = batch->hapl;
    t_probs *prob = batch->prob;

    // Set to zero and intial value in the X direction
    for (int j = 0; j < c + 1; j++)
    {
        M[0][j] = 0.0;
        I[0][j] = 0.0;
        D[0][j].set_raw_bits(init->initials[pair]);
    }

    // Set to zero in Y direction
    for (int i = 1; i < r + 1; i++)
    {
        M[i][0] = 0.0;
        I[i][0] = 0.0;
        D[i][0] = 0.0;
    }

    for (int i = 1; i < r + 1; i++)
    {
        for (int j = 1; j < c + 1; j++)
        {
            posit<NBITS, ES> distm_simi;
            posit<NBITS, ES> distm_diff;
            posit<NBITS, ES> alpha;
            posit<NBITS, ES> beta;
            posit<NBITS, ES> delta;
            posit<NBITS, ES> upsilon;
            posit<NBITS, ES> zeta;
            posit<NBITS, ES> eta;

            posit<NBITS, ES> distm;

            distm_simi.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[7].b);
            distm_diff.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[6].b);
            alpha.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[5].b);
            beta.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[4].b);
            delta.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[3].b);
            upsilon.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[2].b);
            zeta.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[1].b);
            eta.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[0].b);

            unsigned char    rb = read[i - 1].base[pair];
            unsigned char    hb = hapl[j - 1].base[pair];

            if (rb == hb || rb == 'N' || hb == 'N')
            {
                distm = distm_simi;
            }
            else
            {
                distm = distm_diff;
            }

            M[i][j] = distm * (alpha * M[i - 1][j - 1] + beta * I[i - 1][j - 1] + beta * D[i - 1][j - 1]);
            I[i][j] = delta * M[i - 1][j] + upsilon * I[i - 1][j];
            D[i][j] = eta * M[i][j - 1] + zeta * D[i][j - 1];
        }
    }
} // calculate_mids


int count_errors(uint32_t *hr, std::vector<t_result_sw> &sr, int num_batches)
{
    int              total_errors = 0;
    // uint32_t         hw;
    // uint32_t         sw;
    // float            hwf;
    // float            swf;

    posit<NBITS, ES> hwp, swp;

    for (int i = 0; i < num_batches; i++)
    {
        for (int j = 0; j < PIPE_DEPTH; j++)
        {
            swp = sr[i * PIPE_DEPTH + j][0];
            hwp.set_raw_bits(hr[i * 4 * PIPE_DEPTH + j * 4]);

            // hw  = hr[i * 4 * PIPE_DEPTH + j * 4];
            // hwf = *(float *)&hr[i * 4 * PIPE_DEPTH + j * 4];

            // float err = fabs(swf / hwf);
            posit<NBITS,ES> err = swp / hwp;

            if ((err < ERR_LOWER) || (err > ERR_UPPER))
            {
                total_errors++;
                cout << "SW: " << hexstring(swp.collect()) << ", HW: " << hexstring(hwp.collect()) << endl;
                exit(-1);
            }
        }
    }

    return(total_errors);
}


void init_batch_address(t_batch *b, void *batch, int x, int y)
{
    b->init = (t_inits *)((uint64_t)batch);
    b->read = (t_bbase *)((uint64_t)b->init + CACHELINE_BYTES);
    b->hapl = (t_bbase *)((uint64_t)b->read + (uint64_t)pbp(px(x, y)) * (uint64_t)sizeof(t_bbase));
    b->prob = (t_probs *)((uint64_t)b->hapl + (uint64_t)pbp(py(y)) * (uint64_t)sizeof(t_bbase));
}


size_t calc_batch_size(int x, int y, int e)
{
    // Pad X and Y if necessary
    int xpadded = px(x, y);
    int ypadded = py(y);

    // Pad X and Y basepairs
    int    ybps = pbp(ypadded);
    int    xbps = pbp(xpadded);

    size_t init_size = CACHELINE_BYTES;

    size_t xbases = xbps * sizeof(t_bbase);
    size_t ybases = ybps * sizeof(t_bbase);

    size_t prob_size = xpadded * PIPE_DEPTH * sizeof(t_probs);

    // Determine size of batch in bytes.
    size_t batch_size = init_size + xbases + ybases + prob_size;

    return(batch_size);
}
