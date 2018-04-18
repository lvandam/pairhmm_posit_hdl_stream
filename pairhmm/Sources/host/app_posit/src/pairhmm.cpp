#define _POSIX_C_SOURCE    200809L

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <vector>
#include <omp.h>
#include <posit/posit>

#include <iostream>

// libcxl
extern "C" {
#include "libcxl.h"
}

#include "defines.hpp"
#include "batch.hpp"
#include "utils.hpp"
#include "psl.hpp"
#include "pairhmm_posit.hpp"
#include "pairhmm_float.hpp"

#define BILLION    1000000000L

using namespace std;
using namespace sw::unum;


int main(int argc, char *argv[]) {
    struct cxl_afu_h *afu;
    void *batch;
    t_result *result_hw;
    t_workload *workload;
    t_batch *batches;

    bool show_table = false;
    bool show_results = false;
    bool calculate_sw = true;

    uint64_t threads = 1;

    DEBUG_PRINT("Parsing input arguments...\n");
    if (argc < 5) {
        fprintf(stderr,
                "ERROR: Correct usage is: %s <-f = file, -m = manual> ... \n-m: <pairs> <X> <Y> ... \n-f: <input file>\n... <number of threads*> <sw solve?*> <show results?*> <show MID table?*> (* is optional)\n",
                APP_NAME);
        return (-1);
    } else {
        if (strncmp(argv[1], "-f", 2) == 0) {
            if ((workload = load_workload(argv[2])) == NULL) {
                fprintf(stderr, "ERROR: %s cannot be opened.\n", argv[2]);
                return (-1);
            }
            if (argc >= 4) {
                threads = strtoul(argv[3], NULL, 0);
            }
            if (argc >= 5) {
                calculate_sw = strtoul(argv[4], NULL, 0);
            }
            if (argc >= 6) {
                show_results = strtoul(argv[5], NULL, 0);
            }
            if (argc >= 7) {
                show_table = strtoul(argv[6], NULL, 0);
            }

            if (threads <= 0) {
                threads = omp_get_max_threads();
            }

            BENCH_PRINT("%s, ", argv[2]);
            BENCH_PRINT("%8d, ", (int) workload->pairs);
            BENCH_PRINT("%8d, ", (int) threads);
        } else if (strncmp(argv[1], "-m", 2) == 0) {
            DEBUG_PRINT("Manual input mode selected. %d arguments supplied.\n", argc);
            int pairs = strtoul(argv[2], NULL, 0);
            int x = strtoul(argv[3], NULL, 0);
            int y = strtoul(argv[4], NULL, 0);

            workload = gen_workload(pairs, x, y);

            if (argc >= 6) {
                threads = strtoul(argv[5], NULL, 0);
            }
            if (argc >= 7) {
                calculate_sw = strtoul(argv[6], NULL, 0);
            }
            if (argc >= 8) {
                show_results = strtoul(argv[7], NULL, 0);
            }
            if (argc >= 9) {
                show_table = strtoul(argv[8], NULL, 0);
            }
            if (threads <= 0) {
                threads = omp_get_max_threads();
            }

            BENCH_PRINT("M, ");
            BENCH_PRINT("%8d, %8d, %8d, ", workload->pairs, x, y);
            BENCH_PRINT("%8d, ", (int) threads);
        } else {
            fprintf(stderr,
                    "ERROR: Correct usage is: %s <-f = file, -m = manual> ... \n-m: <pairs> <X> <Y> ... \n-f: <input file>\n... <number of threads*> <sw solve?*> <show results?*> <show MID table?*> (* is optional)\n",
                    APP_NAME);
            return (EXIT_FAILURE);
        }
    }

    BENCH_PRINT("%16lu, ", workload->cups_req);

    DEBUG_PRINT("Total workload bytes: %17d \n", (unsigned int) workload->bytes);
    DEBUG_PRINT("CUPS required       : %17lu \n", workload->cups_req);
    DEBUG_PRINT("Allocating memory for %d batches and %d results...\n", (unsigned int) workload->batches,
                (unsigned int) workload->pairs);

    if (posix_memalign((void **) &batch, CACHELINE_BYTES, workload->bytes)) {
        perror("Could not allocate memory to store the batches.\n");
        return (-1);
    }

    if (posix_memalign((void **) &result_hw, CACHELINE_BYTES, sizeof(t_result) * workload->batches * PIPE_DEPTH)) {
        perror("Could not allocate memory to store hardware results.\n");
        return (-1);
    }

    DEBUG_PRINT("Clearing batch and host result memory ...\n");
    memset(batch, 0x00, workload->bytes);

    DEBUG_PRINT("Filling batches...\n");

    void *batch_cur = batch;

    batches = (t_batch *) malloc(sizeof(t_batch) * workload->batches);

    for (int q = 0; q < workload->batches; q++) {
        init_batch_address(&batches[q], batch_cur, workload->bx[q], workload->by[q]);
        fill_batch(&batches[q], workload->bx[q], workload->by[q], 1.0);
        print_batch_info(&batches[q]);
        batch_cur = (void *) ((uint64_t) batch_cur + (uint64_t) workload->bbytes[q]);
    }

    PairHMMPosit pairhmm_posit(workload, show_results, show_table);
    // PairHMMFloat<float> pairhmm_float(workload, show_results, show_table);

    if (calculate_sw) {
        DEBUG_PRINT("Calculating on host...\n");
        pairhmm_posit.calculate(batches);
        // pairhmm_float.calculate(batches);
    }

    DEBUG_PRINT("Clearing HW result memory\n");
    memset(result_hw, 0xFF, sizeof(t_result) * workload->batches * PIPE_DEPTH);

    DEBUG_PRINT("Opening device: %s ...\n", DEVICE);
    afu = cxl_afu_open_dev((char *) (DEVICE));
    if (!afu) {
        perror("cxl_afu_open_dev");
        return (-1);
    }

    DEBUG_PRINT("Setting up Work Element Descriptor...\n");
    struct wed *wed0 = NULL;
    if (posix_memalign((void **) &(wed0), CACHELINE_BYTES, sizeof(struct wed))) {
        perror("posix_memalign");
        return (-1);
    }

    wed0->status = 0;
    wed0->source = (__u64 *) batch;
    wed0->destination = (__u64 *) result_hw;
    wed0->batch_size = (__u32) 0;
    wed0->pair_size = (__u32) 0;
    wed0->padded_size = (__u32) 0;
    wed0->batches = (__u32) workload->batches;

    DEBUG_PRINT("Attaching to AFU and passing WED address...\n");
    if (cxl_afu_attach(afu, (__u64) wed0) < 0) {
        perror("cxl_afu_attach");
        return (-1);
    }

    DEBUG_PRINT("Mapping MMIO...\n");
    if ((cxl_mmio_map(afu, CXL_MMIO_BIG_ENDIAN)) < 0) {
        perror("cxl_mmio_map");
        return (-1);
    }

    DEBUG_PRINT("Waiting for last result...\n");

    while (!wed0->status) {
        sleep(5);
        for (int i = 0; i < workload->batches * PIPE_DEPTH; i++) {
            // Interpret 32-bit value from HW as posits and print
            posit<NBITS, ES> res0, res1, res2, res3;
            res0.set_raw_bits(result_hw[i].b[0]);
            res1.set_raw_bits(result_hw[i].b[1]);
            res2.set_raw_bits(result_hw[i].b[2]);
            res3.set_raw_bits(result_hw[i].b[3]);

            cout << i << ": " << hexstring(res0.collect()) << " " << hexstring(res1.collect()) << " "
                 << hexstring(res2.collect()) << " " << hexstring(res3.collect()) << endl;
        }
    }

    for (int i = 0; i < workload->batches * PIPE_DEPTH; i++) {
        // Interpret 32-bit value from HW as posits and print
        posit<NBITS, ES> res0, res1, res2, res3;
        res0.set_raw_bits(result_hw[i].b[0]);
        res1.set_raw_bits(result_hw[i].b[1]);
        res2.set_raw_bits(result_hw[i].b[2]);
        res3.set_raw_bits(result_hw[i].b[3]);

        cout << i << ": " << hexstring(res0.collect()) << " " << hexstring(res1.collect()) << " "
             << hexstring(res2.collect()) << " " << hexstring(res3.collect()) << endl;
    }

    // Check for errors
    if (calculate_sw) {
        int errs_posit = 0;
        errs_posit = pairhmm_posit.count_errors((uint32_t *) result_hw);
        DEBUG_PRINT("Errors Posit: %d\n", errs_posit);
    }

    // Release the afu
    cxl_mmio_unmap(afu);
    cxl_afu_free(afu);

    BENCH_PRINT("\n");

    free(workload);
    free(result_hw);
    free(batch);
    free(wed0);

    return (0);

} // main
