#include <unistd.h>
#include <sys/time.h>
#include <vector>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <posit/posit>
#include <boost/multiprecision/cpp_dec_float.hpp>
#include <omp.h>

// libcxl
extern "C" {
#include "libcxl.h"
}

#include "defines.hpp"
#include "batch.hpp"
#include "utils.hpp"
#include "psl.hpp"
#include "debug_values.hpp"
#include "pairhmm_posit.hpp"
#include "pairhmm_float.hpp"

#define BILLION    1000000000L

using namespace std;
using namespace sw::unum;
using boost::multiprecision::cpp_dec_float_100;


int main(int argc, char *argv[]) {
    // Times
    double start, stop;
    double t_fill_batch, t_create_core, t_fpga, t_sw, t_float, t_dec = 0.0;

    struct cxl_afu_h *afu;
    void *batch;
    t_result *result_hw;
    t_workload *workload;
    t_batch *batches;

    float f_hw = 125e6;
    float max_cups = f_hw * (float)16;

    unsigned long pairs, x, y = 0;
    int initial_constant_power = 1;
    bool calculate_sw = true;
    bool show_results = false;
    bool show_table = false;

    DEBUG_PRINT("Parsing input arguments...\n");
    if (argc > 4) {
            pairs = strtoul(argv[1], NULL, 0);
            x = strtoul(argv[2], NULL, 0);
            y = strtoul(argv[3], NULL, 0);
            initial_constant_power = strtoul(argv[4], NULL, 0);

            workload = gen_workload(pairs, x, y);

            BENCH_PRINT("M, ");
            BENCH_PRINT("%8d, %8d, %8d, ", workload->pairs, x, y);
    } else {
        fprintf(stderr,
                "ERROR: Correct usage is: %s <pairs> <X> <Y> <initial constant power>\n",
                "pairhmm");
        return (-1);
    }

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

    start = omp_get_wtime();
    batches = (t_batch *) malloc(sizeof(t_batch) * workload->batches);

    // Generate random basepair strings for reads and haplotypes
    std::string x_string = randomBasepairs(16 + pbp(px(x, y)));
    std::string y_string = randomBasepairs(16 + pbp(py(y)));

    for (int q = 0; q < workload->batches; q++) {
        init_batch_address(&batches[q], batch_cur, workload->bx[q], workload->by[q]);
        fill_batch(&batches[q], x_string, y_string, workload->bx[q], workload->by[q], powf(2.0, initial_constant_power));
        // print_batch_info(&batches[q]);
        batch_cur = (void *) ((uint64_t) batch_cur + (uint64_t) workload->bbytes[q]);
    }
    stop = omp_get_wtime();
    t_fill_batch = stop - start;

    PairHMMPosit pairhmm_posit(workload, show_results, show_table);
    PairHMMFloat<float> pairhmm_float(workload, show_results, show_table);
    PairHMMFloat<cpp_dec_float_100> pairhmm_dec50(workload, show_results, show_table);

    if (calculate_sw) {
        DEBUG_PRINT("Calculating on host...\n");

        start = omp_get_wtime();
        pairhmm_posit.calculate(batches);
        stop = omp_get_wtime();
        t_sw = stop - start;

        start = omp_get_wtime();
        pairhmm_float.calculate(batches);
        stop = omp_get_wtime();
        t_float = stop - start;

        start = omp_get_wtime();
        pairhmm_dec50.calculate(batches);
        stop = omp_get_wtime();
        t_dec = stop - start;
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

    start = omp_get_wtime();
    while (!wed0->status) {
        usleep(1); //sleep(5);
        // for (int i = 0; i < workload->batches * PIPE_DEPTH; i++) {
        //     // Interpret 32-bit value from HW as posits and print
        //     posit<NBITS, ES> res0, res1, res2, res3;
        //     res0.set_raw_bits(result_hw[i].b[0]);
        //     res1.set_raw_bits(result_hw[i].b[1]);
        //     res2.set_raw_bits(result_hw[i].b[2]);
        //     res3.set_raw_bits(result_hw[i].b[3]);
        //
        //     cout << i << ": " << hexstring(res0.collect()) << " " << hexstring(res1.collect()) << " "
        //          << hexstring(res2.collect()) << " " << hexstring(res3.collect()) << endl;
        // }
    }
    stop = omp_get_wtime();
    t_fpga = stop - start;

    // Check for errors with SW calculation
    if (calculate_sw) {
        DebugValues<posit<NBITS, ES>> hw_debug_values;

        for (int i = 0; i < workload->batches * PIPE_DEPTH; i++) {
            // Store HW posit result for decimal accuracy calculation
            posit<NBITS, ES> res_hw;
            res_hw.set_raw_bits(result_hw[i].b[0]);
            hw_debug_values.debugValue(res_hw, "result[%d][0]", i);
        }

        writeBenchmark(pairhmm_dec50, pairhmm_float, pairhmm_posit, hw_debug_values,
                       "pairhmm_stream_es" + std::to_string(ES) + "_" + std::to_string(pairs) + "_" + std::to_string(x) + "_" + std::to_string(y) + "_" + std::to_string(initial_constant_power) + ".txt",
                       false, true);

        int errs_posit = 0;
        errs_posit = pairhmm_posit.count_errors((uint32_t *) result_hw);
        DEBUG_PRINT("Posit errors: %d\n", errs_posit);
    }

    // Release the afu
    cxl_mmio_unmap(afu);
    cxl_afu_free(afu);

    free(workload);
    free(result_hw);
    free(batch);
    free(wed0);

    float p_fpga      = ((double)workload->cups_req / (double)t_fpga)  / 1000000; // in MCUPS
    float p_sw        = ((double)workload->cups_req / (double)t_sw)    / 1000000; // in MCUPS
    float p_float     = ((double)workload->cups_req / (double)t_float) / 1000000; // in MCUPS
    float p_dec       = ((double)workload->cups_req / (double)t_dec)   / 1000000; // in MCUPS
    float utilization = ((double)workload->cups_req / (double)t_fpga)  / max_cups;
    float speedup     = t_sw / t_fpga;

    cout << "Adding timing data..." << endl;
    time_t t = chrono::system_clock::to_time_t(chrono::system_clock::now());
    ofstream outfile("pairhmm_stream_es" + std::to_string(ES) + "_" + std::to_string(pairs) + "_" + std::to_string(x) + "_" + std::to_string(y) + "_" + std::to_string(initial_constant_power) + ".txt", ios::out | ios::app);
    outfile << endl << "===================" << endl;
    outfile << ctime(&t) << endl;
    outfile << "Pairs = " << pairs << endl;
    outfile << "X = " << x << endl;
    outfile << "Y = " << y << endl;
    outfile << "Initial Constant = " << initial_constant_power << endl;
    outfile << "cups,t_fill_batch,t_fpga,p_fpga,t_sw,p_sw,t_float,p_float,t_dec,p_dec,utilization,speedup" << endl;
    outfile << setprecision(20) << fixed << workload->cups_req <<","<< t_fill_batch <<","<< t_fpga <<","<< p_fpga <<","<< t_sw <<","<< p_sw <<","<< t_float <<","<< p_float <<","<< t_dec <<","<< p_dec <<","<< utilization <<","<< speedup << endl;
    outfile.close();

    return (0);

} // main
