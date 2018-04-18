#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <omp.h>
#include <posit/posit>
#include <iostream>

#include "defines.hpp"
#include "batch.hpp"
#include "utils.hpp"

using namespace std;
using namespace sw::unum;

void print_batch_info(t_batch *batch) {
    DEBUG_PRINT("Batch pointers:");
    DEBUG_PRINT("Init: %016lX ", (uint64_t) (batch->init));
    DEBUG_PRINT("Read: %016lX ", (uint64_t) (batch->read));
    DEBUG_PRINT("Hapl: %016lX ", (uint64_t) (batch->hapl));
    DEBUG_PRINT("Prob: %016lX \n", (uint64_t) (batch->prob));
    DEBUG_PRINT("X:%d, PX:%d, PBPX:%d, Y:%d, PY:%d\n",
                batch->init->x_size,
                batch->init->x_padded,
                batch->init->x_bppadded,
                batch->init->y_size,
                batch->init->y_padded
    );
}


// padded read size
int px(int x, int y) {
    if (py(y) > PES)         // if feedback fifo is used
    {
        if (x <= PES)        // and x is equal or smaller than number of PES
        {
            x = PES + 1;     // x will be no. PES + 1, +1 is due to delay in the feedback fifo path
        }
    } else              // feedback fifo is not used
    {
        if (x < PES)  // x is smaller than no. PES
        {
            x = PES;  // pad x to be equal to no. PES
        }
    }
    return (x);
}


int pbp(int x) {
    return ((x / BASE_STEPS + (x % BASE_STEPS != 0)) * BASE_STEPS);
}


// padded haplotype size
int py(int y) {
    // divide Y by PES and round up and multiply:
    return ((y / PES + (y % PES != 0)) * PES);
}


// Load workload from file
t_workload *load_workload(char *fname) {
    int x;
    int y;
    FILE *fp;
    char str[64];
    int lines = 0;
    t_workload *workload = (t_workload *) malloc(sizeof(t_workload));

    fp = fopen(fname, "r");
    if (fp == NULL) {
        return (NULL);
    }

    // Count number of lines:
    while (!feof(fp)) {
        if (fgetc(fp) == '\n') {
            lines++;
        }
    }

    DEBUG_PRINT("Input file containts %d lines\n", lines);

    workload->pairs = lines;

    if (workload->pairs % PIPE_DEPTH != 0) {
        fprintf(stderr, "Number of pairs must be multiple of %d.\n", PIPE_DEPTH);
        exit(EXIT_FAILURE);
    }

    workload->batches = lines / PIPE_DEPTH;

    // Allocate memory
    workload->hapl = (uint32_t *) malloc(lines * sizeof(uint32_t));
    workload->read = (uint32_t *) malloc(lines * sizeof(uint32_t));
    workload->bx = (uint32_t *) malloc(workload->batches * sizeof(uint32_t));
    workload->by = (uint32_t *) malloc(workload->batches * sizeof(uint32_t));
    workload->bbytes = (size_t *) malloc(workload->batches * sizeof(size_t));
    workload->cups_req = 0;

    // Load the data:
    int i = 0;
    rewind(fp);
    while (!feof(fp)) {
        fgets(str, 64, fp);
        if (!feof(fp)) {
            sscanf(str, "%u %u\n", &y, &x);
            if (x > MAX_BP_STRING) {
                fprintf(stderr, "%s line %d: Read size exceeds maximum of %d\n", fname, i, MAX_BP_STRING);
                exit(EXIT_FAILURE);
            }
            if (y > MAX_BP_STRING) {
                fprintf(stderr, "%s line %d: Haplotype size on exceeds maximum of %d\n", fname, i, MAX_BP_STRING);
                exit(EXIT_FAILURE);
            }
            if (y < x) {
                fprintf(stderr, "%s line %d: haplotype must be larger than read.\n", fname, i);
                exit(EXIT_FAILURE);
            }

            workload->hapl[i] = y;
            workload->read[i] = x;
            workload->cups_req += (uint64_t) y * (uint64_t) x;
            i++;
        }
    }

    // Set batch info
    DEBUG_PRINT("Batch ║ MAX X ║ MAX Y ║ Passes ║  Bytes ║\n");
    DEBUG_PRINT("═════════════════════════════════════════\n");

    // One more cacheline for the first batch.
    workload->bytes = CACHELINE_BYTES;

    for (int b = 0; b < workload->pairs / PIPE_DEPTH; b++) {
        int xmax = 0;
        int ymax = 0;
        for (int p = 0; p < PIPE_DEPTH; p++) {
            if (workload->read[b * PIPE_DEPTH + p] > xmax) {
                xmax = workload->read[b * PIPE_DEPTH + p];
            }
            if (workload->hapl[b * PIPE_DEPTH + p] > ymax) {
                ymax = workload->hapl[b * PIPE_DEPTH + p];
            }
        }
        workload->bx[b] = xmax;
        workload->by[b] = ymax;
        workload->bbytes[b] = calc_batch_size(xmax, ymax, PES);
        workload->bytes += workload->bbytes[b];

        DEBUG_PRINT("%5d ║ %5d ║ %5d ║ %6d ║ %6d ║\n", b, xmax, ymax, PASSES(ymax), (unsigned int) workload->bbytes[b]);
    }

    fclose(fp);

    return (workload);
} // load_workload


t_workload *gen_workload(unsigned long pairs, unsigned long fixedX, unsigned long fixedY) {
    DEBUG_PRINT("Generating workload for %d pairs, with X=%d and Y=%d\n", (int) pairs, (int) fixedX, (int) fixedY);
    t_workload *workload = (t_workload *) malloc(sizeof(t_workload));

    if (fixedY < fixedX) {
        //printf("Haplotype cannot be smaller than read.\n");
        //exit(EXIT_FAILURE);
    }

    workload->pairs = pairs;

    if (workload->pairs % PIPE_DEPTH != 0) {
        printf("Number of pairs must be an integer multiple of %d.\n", PIPE_DEPTH);
        exit(EXIT_FAILURE);
    }

    workload->batches = pairs / PIPE_DEPTH;

    // Allocate memory
    workload->hapl = (uint32_t *) malloc(workload->pairs * sizeof(uint32_t));
    workload->read = (uint32_t *) malloc(workload->pairs * sizeof(uint32_t));
    workload->bx = (uint32_t *) malloc(workload->batches * sizeof(uint32_t));
    workload->by = (uint32_t *) malloc(workload->batches * sizeof(uint32_t));
    workload->bbytes = (size_t *) malloc(workload->batches * sizeof(size_t));
    workload->cups_req = 0;

    for (int i = 0; i < workload->pairs; i++) {
        workload->hapl[i] = fixedY;
        workload->read[i] = fixedX;
        workload->cups_req += fixedY * fixedX;
    }

    // Set batch info
    DEBUG_PRINT("Batch ║ MAX X ║ MAX Y ║ Passes ║  Bytes ║\n");
    DEBUG_PRINT("═════════════════════════════════════════\n");

    workload->bytes = CACHELINE_BYTES;

    for (int b = 0; b < workload->pairs / PIPE_DEPTH; b++) {
        int xmax = 0;
        int ymax = 0;
        for (int p = 0; p < PIPE_DEPTH; p++) {
            if (workload->read[b * PIPE_DEPTH + p] > xmax) {
                xmax = workload->read[b * PIPE_DEPTH + p];
            }
            if (workload->hapl[b * PIPE_DEPTH + p] > ymax) {
                ymax = workload->hapl[b * PIPE_DEPTH + p];
            }
        }
        workload->bx[b] = xmax;
        workload->by[b] = ymax;
        workload->bbytes[b] = calc_batch_size(xmax, ymax, PES);
        workload->bytes += workload->bbytes[b];

        DEBUG_PRINT("%5d ║ %5d ║ %5d ║ %6d ║ %6d ║\n", b, xmax, ymax, PASSES(ymax), (unsigned int) workload->bbytes[b]);
    }

    return (workload);
} // gen_workload
