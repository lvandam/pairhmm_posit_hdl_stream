#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <omp.h>
#include "libcxl.h"

#include "defines.h"
#include "batch.h"
#include "utils.h"
#include "psl.h"

#define BILLION 1000000000L

int main (int argc, char *argv[]) {
  struct timespec hwstart, hwend;
  
  struct cxl_afu_h *afu;
  void             *batch;
  t_result         *result_hw;
  t_result         *result_sw;
  t_workload       *workload;
  t_batch          *batches;  
  
  unsigned char    show_table = 0;
  unsigned char		 show_results = 0;
  unsigned char 	 calculate_sw = 1;
  double					 clock_sw;
  double					 clock_hw;
  
  uint64_t   			 threads = 1;

  DEBUG_PRINT("Parsing input arguments...\n");
  if (argc < 5) {
    fprintf(stderr, "ERROR: Correct usage is: %s <-f = file, -m = manual> ... \n-m: <pairs> <X> <Y> ... \n-f: <input file>\n... <number of threads*> <sw solve?*> <show results?*> <show MID table?*> (* is optional)\n", APP_NAME);
    return -1;
  } 
  else {
		if (strncmp(argv[1],"-f",2)==0) {
			if ((workload = load_workload(argv[2])) == NULL) {
				fprintf(stderr, "ERROR: %s cannot be opened.\n", argv[2]);
				return -1;
			}
			if (argc >= 4) threads			= strtoul(argv[3], NULL, 0);
			if (argc >= 5) calculate_sw = strtoul(argv[4], NULL, 0);
			if (argc >= 6) show_results = strtoul(argv[5], NULL, 0);
			if (argc >= 7) show_table   = strtoul(argv[6], NULL, 0);
			
			if (threads <= 0) threads = omp_get_max_threads();
			
			BENCH_PRINT("%s, ", argv[2]);
			BENCH_PRINT("%8d, ", (int) workload->pairs);
			BENCH_PRINT("%8d, ", (int) threads);
		}
		else if (strncmp(argv[1],"-m",2)==0) {
      DEBUG_PRINT("Manual input mode selected. %d arguments supplied.\n", argc);
			int pairs = strtoul(argv[2], NULL, 0);
			int x = strtoul(argv[3], NULL, 0);
			int y = strtoul(argv[4], NULL, 0);
      
      workload = gen_workload(pairs, x, y);
      
			if (argc >= 6) threads			= strtoul(argv[5], NULL, 0);
			if (argc >= 7) calculate_sw = strtoul(argv[6], NULL, 0);
			if (argc >= 8) show_results = strtoul(argv[7], NULL, 0);
			if (argc >= 9) show_table   = strtoul(argv[8], NULL, 0);
			if (threads <= 0) threads = omp_get_max_threads();

			BENCH_PRINT("M, ");
			BENCH_PRINT("%8d, %8d, %8d, ", workload->pairs, x, y);
			BENCH_PRINT("%8d, ", (int) threads);
		}
		else
		{
			fprintf(stderr, "ERROR: Correct usage is: %s <-f = file, -m = manual> ... \n-m: <pairs> <X> <Y> ... \n-f: <input file>\n... <number of threads*> <sw solve?*> <show results?*> <show MID table?*> (* is optional)\n", APP_NAME);
			return EXIT_FAILURE;
		}
  }
  
  BENCH_PRINT("%16lu, ",workload->cups_req);
  
  DEBUG_PRINT("Total workload bytes: %17d \n", (unsigned int) workload->bytes);
  DEBUG_PRINT("CUPS required       : %17lu \n", workload->cups_req);     
  DEBUG_PRINT("Allocating memory for %d batches and %d results...\n", (unsigned int) workload->batches, (unsigned int) workload->pairs);

  if (posix_memalign( (void **) &batch, CACHELINE_BYTES, workload->bytes)) {
    perror("Could not allocate memory to store the batches.\n");
    return -1;
  }

  if (posix_memalign( (void **) &result_hw, CACHELINE_BYTES, sizeof(t_result) * workload->batches * PIPE_DEPTH)) {
    perror("Could not allocate memory to store hardware results.\n");
    return -1;
  }

  if (posix_memalign( (void **) &result_sw, CACHELINE_BYTES, sizeof(t_result) * workload->batches * PIPE_DEPTH)) {
    perror("Could not allocate memory to store software results.\n");
    return -1;
  }

  DEBUG_PRINT("Clearing batch and host result memory ...\n");
  memset(result_sw, 0xFF, sizeof(t_result)  * workload->batches * PIPE_DEPTH);
  memset(batch,     0x00, workload->bytes);



  DEBUG_PRINT("Filling batches...\n");

  clock_sw = omp_get_wtime();
  
  void * batch_cur = batch;  
  
  batches = (t_batch*) malloc(sizeof(t_batch) * workload->batches);
      
  for (int q = 0; q < workload->batches; q++) {
    init_batch_address(&batches[q], batch_cur, workload->bx[q], workload->by[q]);
    fill_batch(&batches[q], workload->bx[q], workload->by[q], 1.0);
    print_batch_info(&batches[q]);    
    batch_cur = (void*) ((uint64_t) batch_cur + (uint64_t) workload->bbytes[q]);
  }
  clock_sw = omp_get_wtime() - clock_sw;
  BENCH_PRINT("%16f,",clock_sw);  
  
  DEBUG_PRINT("Calculating on host...\n");

  clock_sw = omp_get_wtime();
  
  //print_batch_memory(batch, workload->bbytes[0] + workload->bbytes[1]);
    
  if (calculate_sw) {
	  omp_set_num_threads(threads);
		#pragma omp parallel for
		for (int q = 0; q < workload->batches; q++) {
      
      int x = workload->bx[q];
      int y = workload->by[q];
      
		  float * M = (float*)malloc(sizeof(float) * (y+1) * (x+1));
			float * I = (float*)malloc(sizeof(float) * (y+1) * (x+1));
			float * D = (float*)malloc(sizeof(float) * (y+1) * (x+1));
		       
      // Calculate results
		  for (int p = 0; p < PIPE_DEPTH; p++) {
		    calculate_mids(&batches[q], p, x, y, M, I, D);
        
        result_sw[q*PIPE_DEPTH+p].values[0] = 0.0;
        for (int c = 0; c < y+1; c++)
        {
          // WARNING: THIS IS BECAUSE FLOATING POINT ADDITION IS NOT ASSOCIATIVE
          result_sw[q*PIPE_DEPTH+p].values[0] += M[(y+1)*x+c];
          result_sw[q*PIPE_DEPTH+p].values[0] += I[(y+1)*x+c];
        }

		    if (show_table != 0) {
		      print_mid_table(&batches[q], p, x, y, M, I, D);
          fflush(stdout);
		    }
		  }
		  
		  free(M);
		  free(I);
		  free(D);
		}
  }

  clock_sw = omp_get_wtime() - clock_sw;
  
  if (calculate_sw) {
		BENCH_PRINT("%16f, ", clock_sw);
    BENCH_PRINT("%16f, ", workload->cups_req / clock_sw / 1000000);
  }
	else
  {
    BENCH_PRINT("%16f,",0.0);
    BENCH_PRINT("%16f,",0.0);
  }
    
  
  
  DEBUG_PRINT("%d %d\n",calculate_sw, show_results);
  
  if (calculate_sw && (show_results > 0)) {
  	print_results(result_sw, workload->batches);
  }
  
  DEBUG_PRINT("Clearing result memory\n");
  memset(result_hw, 0xFF, sizeof(t_result)  * workload->batches * PIPE_DEPTH);
  
  DEBUG_PRINT("Opening device: %s ...\n", DEVICE);
  afu = cxl_afu_open_dev ((char*) (DEVICE));
  if (!afu) { perror ("cxl_afu_open_dev"); return -1; }

	// Start measuring
  clock_hw = omp_get_wtime();
  clock_gettime(CLOCK_MONOTONIC, &hwstart); /* mark start time */
  

  DEBUG_PRINT("Setting up Work Element Descriptor...\n");
  struct wed *wed0 = NULL;
  if (posix_memalign ((void **) &(wed0), CACHELINE_BYTES, sizeof(struct wed))) {
    perror ("posix_memalign");
    return -1;
  }
  
  wed0->status      = 0;
  wed0->source      = (__u64*)batch;
  wed0->destination = (__u64*)result_hw;
  wed0->batch_size  = (__u32) 0;
  wed0->pair_size   = (__u32) 0;
  wed0->padded_size = (__u32) 0;
  wed0->batches     = (__u32) workload->batches;

  DEBUG_PRINT("Attaching to AFU and passing WED address...\n");
  if (cxl_afu_attach (afu, (__u64) wed0) < 0) { perror ("cxl_afu_attach"); return -1; }

  DEBUG_PRINT("Mapping MMIO...\n");
  if ((cxl_mmio_map (afu, CXL_MMIO_BIG_ENDIAN)) < 0) { perror("cxl_mmio_map"); return -1; }

	DEBUG_PRINT("Waiting for last result...\n");
  
  volatile int temp;
  while (!wed0->status)
  {
    temp++;
#ifdef DEBUG
		sleep(5);
		for (int i = 0; i < workload->batches * PIPE_DEPTH; i++)
		{
		  DEBUG_PRINT("%4d: %X" , i,result_hw[i].b[0]);
		  DEBUG_PRINT(" %X"	  	,   result_hw[i].b[1]);
		  DEBUG_PRINT(" %X" 	  ,   result_hw[i].b[2]);
		  DEBUG_PRINT(" %X\n" 	,   result_hw[i].b[3]);
		}
#endif
  }
  
  clock_gettime(CLOCK_MONOTONIC, &hwend); /* mark the end time */
  clock_hw = omp_get_wtime() - clock_hw;
  
	uint64_t diff = BILLION * (hwend.tv_sec - hwstart.tv_sec) + hwend.tv_nsec - hwstart.tv_nsec; 
   
  // Check for errors
  int errs = 0;
  
  if (calculate_sw)
  {
	  errs = count_errors((uint32_t *)result_hw,(uint32_t *)result_sw,workload->batches);
	}
  
  DEBUG_PRINT("Errors: %d\n",errs);

  // Release the afu
  cxl_mmio_unmap (afu);
  cxl_afu_free (afu);
    
  BENCH_PRINT("%16f,",clock_hw);
  BENCH_PRINT("%16llu,", (long long unsigned int) diff); 
  
  BENCH_PRINT("%16f,", ((double)workload->cups_req / (double)clock_hw) / 1000000);
  BENCH_PRINT("%16f,", 1.0 / (MAX_CUPS / ((double)workload->cups_req / (double)clock_hw))); // what the crap is this why cant i just hwcups / MAX_CUPS ?

	if (calculate_sw)
		BENCH_PRINT("%16f,",clock_sw / clock_hw);
	else
		BENCH_PRINT("%16f,",0.0);
	
	BENCH_PRINT("%16d",errs);
	BENCH_PRINT("\n");

	free(workload);
	free(result_sw);
	free(result_hw);
  free(batch);
  free(wed0);

  return 0;
}

