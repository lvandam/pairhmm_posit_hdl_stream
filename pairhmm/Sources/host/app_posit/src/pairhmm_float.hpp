//
// Created by laurens on 18-4-18.
//

#ifndef PAIRHMM_FLOAT_HPP
#define PAIRHMM_FLOAT_HPP

#include <iostream>
#include <vector>
#include <posit/posit>

#include "defines.hpp"
#include "utils.hpp"
#include "batch.hpp"

using namespace std;
using namespace sw::unum;

template<class T>
class PairHMMFloat {
    typedef vector<T> t_result_sw;
    typedef vector<t_result_sw> t_matrix;

private:
    std::vector<t_result_sw> result_sw;
    t_workload *workload;
    bool show_results, show_table;

public:
    PairHMMFloat(t_workload *workload, bool show_results, bool show_table) {
        workload = workload;
        show_results = show_results;
        show_table = show_table;
        result_sw.reserve(workload->batches * PIPE_DEPTH);
        for (int i = 0; i < workload->batches * PIPE_DEPTH; i++) {
            result_sw[i].reserve(3);
        }
    }

    void calculate(t_batch *batches) {
        for (int q = 0; q < workload->batches; q++) {
            int x = workload->bx[q];
            int y = workload->by[q];

            vector<vector<T>> M(x + 1, vector<T>(y + 1));
            vector<vector<T>> I(x + 1, vector<T>(y + 1));
            vector<vector<T>> D(x + 1, vector<T>(y + 1));

            // Calculate results
            for (int p = 0; p < PIPE_DEPTH; p++) {
                calculate_mids(&batches[q], p, x, y, M, I, D);

                result_sw[q * PIPE_DEPTH + p][0] = 0.0;
                for (int c = 1; c < y + 1; c++) {
                    result_sw[q * PIPE_DEPTH + p][0] += M[x][c];
                    result_sw[q * PIPE_DEPTH + p][0] += I[x][c];
                }

                if (show_table) {
                    print_mid_table(&batches[q], p, x, y, M, I, D);
                }
            }
        }

        if (show_results) {
            print_results(result_sw, workload->batches);
        }
    }

    void calculate_mids(t_batch *batch, int pair, int r, int c, t_matrix &M, t_matrix &I, t_matrix &D) {
        t_inits *init = batch->init;
        t_bbase *read = batch->read;
        t_bbase *hapl = batch->hapl;
        t_probs *prob = batch->prob;

        posit<NBITS,ES> initial;
        initial.set_raw_bits(init->initials[pair]);

        // Set to zero and intial value in the X direction
        for (int j = 0; j < c + 1; j++) {
            M[0][j] = 0.0;
            I[0][j] = 0.0;
            D[0][j] = (T)initial;
        }

        // Set to zero in Y direction
        for (int i = 1; i < r + 1; i++) {
            M[i][0] = 0.0;
            I[i][0] = 0.0;
            D[i][0] = 0.0;
        }

        for (int i = 1; i < r + 1; i++) {
            for (int j = 1; j < c + 1; j++) {
                posit<NBITS, ES> distm_simi, distm_diff, alpha, beta, delta, upsilon, zeta, eta, distm;

                distm_simi.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[7].b);
                distm_diff.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[6].b);
                alpha.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[5].b);
                beta.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[4].b);
                delta.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[3].b);
                upsilon.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[2].b);
                zeta.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[1].b);
                eta.set_raw_bits(prob[(i - 1) * PIPE_DEPTH + pair].p[0].b);

                unsigned char rb = read[i - 1].base[pair];
                unsigned char hb = hapl[j - 1].base[pair];

                if (rb == hb || rb == 'N' || hb == 'N') {
                    distm = distm_simi;
                } else {
                    distm = distm_diff;
                }

                M[i][j] = (T)distm * ((T)alpha * M[i - 1][j - 1] + (T)beta * I[i - 1][j - 1] + (T)beta * D[i - 1][j - 1]);
                I[i][j] = (T)delta * M[i - 1][j] + (T)upsilon * I[i - 1][j];
                D[i][j] = (T)eta * M[i][j - 1] + (T)zeta * D[i][j - 1];
            }
        }
    } // calculate_mids

    int count_errors(uint32_t *hr) {
        int total_errors = 0;
        T hwp, swp;

        for (int i = 0; i < workload->batches; i++) {
            for (int j = 0; j < PIPE_DEPTH; j++) {
                swp = result_sw[i * PIPE_DEPTH + j][0];
                hwp.set_raw_bits(hr[i * 4 * PIPE_DEPTH + j * 4]);

                T err = swp / hwp;

                if ((err < ERR_LOWER) || (err > ERR_UPPER)) {
                    total_errors++;
                    cout << "SW: " << hexstring(swp.collect()) << ", HW: " << hexstring(hwp.collect()) << endl;
                    exit(-1);
                }
            }
        }

        return (total_errors);
    } // count_errors

    void print_mid_table(t_batch *batch, int pair, int r, int c, t_matrix &M, t_matrix &I, t_matrix &D) {
        int w = c + 1;
        t_bbase *read = batch->read;
        t_bbase *hapl = batch->hapl;

        T res[3];

        res[0] = static_cast<T>(0.0);

        printf("════╦");
        for (uint32_t i = 0; i < c + 1; i++) {
            printf("══════════════════════════╦");
        }
        printf("\n");
        printf("    ║");
        for (uint32_t i = 0; i < c + 1; i++) {
            printf("      %5d , %c           ║", i, (i > 0) ? (hapl[i - 1].base[pair]) : '-');
        }
        printf("\n");
        printf("%3d ║", pair);
        for (uint32_t i = 0; i < c + 1; i++) {
            printf("══════════════════════════╣");
        }
        printf("\n");
        printf("    ║");
        for (uint32_t i = 0; i < c + 1; i++) {
            printf("   M        I        D    ║");
        }
        printf("\n");
        printf("════╣");
        for (uint32_t i = 0; i < c + 1; i++) {
            printf("══════════════════════════╣");
        }
        printf("\n");

        // loop over rows
        for (uint32_t j = 0; j < r + 1; j++) {
            printf("%2d,%c║", j, (j > 0) ? (read[j - 1].base[pair]) : ('-'));
            // loop over columns
            for (uint32_t i = 0; i < c + 1; i++) {
                printf("%08X %08X %08X║", (float) M[j][i], (float) I[j][i], (float) D[j][i]);
            }
            printf("\n");
        }
        printf("════╣");
        for (uint32_t i = 0; i < c + 1; i++) {
            printf("══════════════════════════╣");
        }
        printf("\n");
        // Result row
        printf("res:║");
        for (uint32_t i = 0; i < c + 1; i++) {
            res[0] += M[r][i];
            res[0] += I[r][i];

            cout << "                  " << hex << res[0] << "║";
        }
        printf("\n");
        printf("═════");
        for (uint32_t i = 0; i < c + 1; i++) {
            printf("═══════════════════════════");
        }
        printf("\n");


        fflush(stdout);
    } // print_mid_table

    void print_results(std::vector<t_result_sw> &results, int num_batches) {
        DEBUG_PRINT("╔═══════════════════════════════╗\n");
        for (int q = 0; q < num_batches; q++) {
            DEBUG_PRINT("║ RESULT FOR BATCH %3d:         ║ DECIMAL\n", q);
            DEBUG_PRINT("╠═══════════════════════════════╣\n");
            for (int p = 0; p < PIPE_DEPTH; p++) {
                printf("║%2d: ", p);
                cout << hex << results[q * PIPE_DEPTH + p][0];
                cout << " ";
                cout << hex << results[q * PIPE_DEPTH + p][1];
                cout << " ";
                cout << hex << results[q * PIPE_DEPTH + p][2];
                cout << " ║ ";
                cout << results[q * PIPE_DEPTH + p][0];
                cout << endl;
            }
            DEBUG_PRINT("╚═══════════════════════════════╝\n");
        }
        fflush(stderr);
    } // print_results
};


#endif //PAIRHMM_FLOAT_HPP
