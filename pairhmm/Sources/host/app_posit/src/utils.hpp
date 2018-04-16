#ifndef __UTILS_H
#define __UTILS_H

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <omp.h>
#include <posit/posit>

#include "config.hpp"
#include "defines.hpp"
#include "batch.hpp"

using namespace std;
using namespace sw::unum;

typedef struct struct_workload
{
    int      pairs;
    uint32_t *hapl;
    uint32_t *read;

    int      batches;
    uint32_t *by;
    uint32_t *bx;
    size_t   *bbytes;

    size_t   bytes;

    uint64_t cups_req;
} t_workload;

const char *binstr(uint8_t x);
void print_omp_info(void);
void print_mid_table(t_batch *batch, int pair, int r, int c, t_posit_matrix& M, t_posit_matrix& I, t_posit_matrix& D);
void print_results(std::vector<t_result_sw>& results, int num_batches);
void print_batch_memory(void *batch, size_t batch_size);
void print_batch_info(t_batch *batch);
int px(int x, int y);
int pbp(int x);
int py(int y);

t_workload *load_workload(char *fname);
t_workload *gen_workload(unsigned long pairs, unsigned long fixedX, unsigned long fixedY);

template<size_t nbits>
std::string hexstring(bitblock<nbits> bits) {
    char str[8];   // plenty of room
    const char* hexits = "0123456789ABCDEF";
    unsigned int max = 8;
    for (unsigned int i = 0; i < max; i++) {
        unsigned int hexit = (bits[3] << 3) + (bits[2] << 2) + (bits[1] << 1) + bits[0];
        str[max - 1 - i] = hexits[hexit];
        bits >>= 4;
    }
    return std::string(str);
}


#endif //__UTILS_H
