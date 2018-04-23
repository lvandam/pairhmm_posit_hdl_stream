#ifndef __DEFINES_H
#define __DEFINES_H

using namespace std;
using namespace sw::unum;

// POSIT
#define NBITS 32
#define ES 2

#define DEBUG              1

#ifndef DEBUG_PRECISION
#define DEBUG_PRECISION 40
#endif // DEBUG_PRECISION


#define MAX_POLLS          32000
#define REPEATS            10
#define MAX_DIFF_REPORT    50
#define MAX_CACHELINES     (1 << 22)
#define DEVICE             "/dev/cxl/afu0.0d"

// PAIRHMM Constants:

// Maximum number of basepairs in a read/haplotype pair
// MAX_BP_STRING must be an integer multiple of 128
#define MAX_BP_STRING    512
#define PES              16
#define FREQ             166666666.666666666666
#define MAX_CUPS         (double)PES * (double)FREQ

#define PASSES(Y)    1 + ((Y - 1) / PES)

// Batch size (or number of pipeline stages)
#define PIPE_DEPTH    16

// Length of pairs must be multiples of this number
// This is due to howmany bases fit in one cacheline
#define BASE_STEPS               8

// The error margin allowed
#define ERROR_MARGIN             0.0000001
#define ERR_LOWER                1.0f - ERROR_MARGIN
#define ERR_UPPER                1.0f + ERROR_MARGIN

#define APP_NAME                 "pairhmm"

#define CACHELINE_BYTES          128                // 0x80
#define MMIO_DEBUG               0x03fffff8         // 0x03fffff8 >> 2 = 0xfffffe (because the last two bits are dropped by the PSL interface)

#define MMIO_PAIRHMM_CONTROL     0x00000000 << 2
#define MMIO_PAIRHMM_SIZE        0x00000002 << 2
#define MMIO_PAIRHMM_STATUS      0x00000004 << 2
#define MMIO_PAIRHMM_REQS        0x00000006 << 2
#define MMIO_PAIRHMM_REPS        0x00000008 << 2
#define MMIO_PAIRHMM_FIFO        0x0000000A << 2
#define MMIO_PAIRHMM_FIFO_RVS    0x0000000C << 2
#define MMIO_PAIRHMM_FIFO_WAS    0x0000000E << 2

// Debug printf macro
#ifdef DEBUG
#define DEBUG_PRINT(...)    do { fprintf(stderr, __VA_ARGS__); } while (0)
#define BENCH_PRINT(...)    do { } while (0)
#else
#define DEBUG_PRINT(...)    do { } while (0)
#define BENCH_PRINT(...)    do { fprintf(stderr, __VA_ARGS__); } while (0)
#endif

struct Entry {
    string name;
    cpp_dec_float_50 value;
};

struct find_entry {
    string name;

    find_entry(string name) : name(name) {}

    bool operator()(const Entry &m) const {
        return m.name == name;
    }
};

template<size_t nbits>
std::string hexstring(bitblock<nbits> bits) {
    char str[8];
    const char *hexits = "0123456789ABCDEF";
    unsigned int max = 8;
    for (unsigned int i = 0; i < max; i++) {
        unsigned int hexit = (bits[3] << 3) + (bits[2] << 2) + (bits[1] << 1) + bits[0];
        str[max - 1 - i] = hexits[hexit];
        bits >>= 4;
    }
    return std::string(str);
}

template<size_t nbits, size_t es>
uint32_t to_uint(posit<nbits, es> number) {
    return (uint32_t) number.collect().to_ulong();
}

#endif //__DEFINES_H
