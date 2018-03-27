# globals
APP               = pairhmm
APP_SIM           = pairhmm_sim

# dirs
PSLSE_DIR         = Sources/sim/pslse
PSLSE_COMMON_DIR  = Sources/sim/pslse/common
PSLSE_LIBCXL_DIR  = Sources/sim/pslse/libcxl
SRC_DIR           = src

# files
APP_DIR           = Sources/host/app
APP_BUILD_DIR     = $(APP_DIR)/build
APP_SIM_BUILD_DIR = $(APP_DIR)/sim-build

program_C_SRCS         := $(wildcard $(APP_DIR)/$(SRC_DIR)/*.cpp)
program_C_OBJS         := ${program_C_SRCS:.c=.o}
program_OBJS           := $(program_C_OBJS)


# files posit
APP_POSIT_DIR           = Sources/host/app_posit
APP_POSIT_BUILD_DIR     = $(APP_POSIT_DIR)/build
APP_POSIT_SIM_BUILD_DIR = $(APP_POSIT_DIR)/sim-build

program_posit_C_SRCS   := $(wildcard $(APP_POSIT_DIR)/$(SRC_DIR)/*.cpp)
program_posit_C_OBJS   := ${program_posit_C_SRCS:.c=.o}
program_posit_OBJS     := $(program_posit_C_OBJS)

# power host libraries
program_INCLUDE_DIRS   := /tools/ppc_64/libcxl
program_LIBRARY_DIRS   := /tools/ppc_64/libcxl
program_LIBRARIES      :=
program_STATIC_LIBS    := /tools/ppc_64/libcxl/libcxl.a

# compilers
CPP              	   = c++

# flags
CFLAGS                 = -O3 -Wall -m64 -fopenmp

# PSL
pslse-build:
	cd $(PSLSE_DIR)/afu_driver/src && make clean && BIT32=y make
	cd $(PSLSE_DIR)/pslse && make clean && make DEBUG=1
	cd $(PSLSE_LIBCXL_DIR) && make clean && make

pslse-run:
	cd Sources/sim && ./pslse/pslse/pslse

# Float
sim: $(program_OBJS)
	mkdir -p $(APP_DIR)/sim-build
	$(CPP) $(program_OBJS) -o $(APP_DIR)/sim-build/$(APP) $(PSLSE_LIBCXL_DIR)/libcxl.a $(CFLAGS) -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -lrt -lpthread -D SIM

sim-run:
	cd Sources/sim && ../../$(APP_DIR)/sim-build/$(APP) $(ARGS)

vsim-run:
	cd Sources/sim && vsim -do vsim.tcl

host: $(program_OBJS)
	mkdir -p $(APP_DIR)/build
	$(CPP) $(program_OBJS) -o $(APP_DIR)/build/$(APP) /tools/ppc_64/libcxl/libcxl.a $(CFLAGS) -I/tools/ppc_64/libcxl -I/tools/ppc_64/libcxl/include -lrt -lpthread

host-run:
	$(APP_DIR)/build/$(APP) $(ARGS)


# Posit
sim-posit:
	mkdir -p $(APP_POSIT_DIR)/sim-build
	cd $(APP_POSIT_DIR)/sim-build && cmake .. && make pairhmm_sim

sim-run-posit:
	cd Sources/sim && ../../$(APP_POSIT_DIR)/sim-build/$(APP_SIM) $(ARGS)

vsim-run-posit:
	cd Sources/sim && vsim -do vsim.tcl

host-posit: $(program_posit_OBJS)
	mkdir -p $(APP_POSIT_DIR)/build
	cd $(APP_POSIT_DIR)/build && cmake .. && make pairhmm_host

host-run-posit:
	$(APP_POSIT_DIR)/build/$(APP)_host $(ARGS)


# Clean targets
clean:
	rm -rf $(APP_BUILD_DIR) $(APP_SIM_BUILD_DIR) $(APP_DIR)/src/*.o $(APP_POSIT_BUILD_DIR) $(APP_POSIT_SIM_BUILD_DIR) $(APP_POSIT_DIR)/src/*.o

clean-logs:
	rm -rf *.log
