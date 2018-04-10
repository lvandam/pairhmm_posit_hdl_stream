# globals
APP               = pairhmm

# dirs
PSLSE_DIR         = Sources/sim/pslse
PSLSE_COMMON_DIR  = Sources/sim/pslse/common
PSLSE_LIBCXL_DIR  = Sources/sim/pslse/libcxl
APP_DIR           = Sources/host/app
SRC_DIR           = src

# files
program_C_SRCS 				:= $(wildcard $(APP_DIR)/$(SRC_DIR)/*.cpp)
program_C_OBJS 				:= ${program_C_SRCS:.c=.o}
program_OBJS 					:= $(program_C_OBJS)

# power host libraries
program_INCLUDE_DIRS 	:= /tools/ppc_64/libcxl
program_LIBRARY_DIRS 	:= /tools/ppc_64/libcxl
program_LIBRARIES 		:=
program_STATIC_LIBS		:= /tools/ppc_64/libcxl/libcxl.a

# compilers
CPP               = c++

# flags
CFLAGS            =  -O3 -Wall -m64 -fopenmp

pslse-build:
	cd $(PSLSE_DIR)/afu_driver/src && make clean && BIT32=y make
	cd $(PSLSE_DIR)/pslse && make clean && make DEBUG=1
	cd $(PSLSE_LIBCXL_DIR) && make clean && make

pslse-run:
	cd Sources/sim && ./pslse/pslse/pslse

# $(CPP) $(APP_DIR)/$(SRC_DIR)/$(APP).c -o $(APP_DIR)/sim-build/$(APP) $(PSLSE_LIBCXL_DIR)/libcxl.a $(CFLAGS) -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -lrt -lpthread -D SIM
sim-build: $(program_OBJS)
	mkdir -p $(APP_DIR)/sim-build
	$(CPP) $(program_OBJS) -o $(APP_DIR)/sim-build/$(APP) $(PSLSE_LIBCXL_DIR)/libcxl.a $(CFLAGS) -I$(PSLSE_COMMON_DIR) -I$(PSLSE_LIBCXL_DIR) -lrt -lpthread -D SIM

sim-run:
	cd Sources/sim && ../../$(APP_DIR)/sim-build/$(APP) $(ARGS)

vsim-run:
	cd Sources/sim && vsim -do vsim.tcl

host: $(program_OBJS)
	mkdir -p $(APP_DIR)/build
	$(CPP) $(program_OBJS) -o $(APP_DIR)/build/$(APP) /tools/ppc_64/libcxl/libcxl.a $(CFLAGS) -I/tools/ppc_64/libcxl -I/tools/ppc_64/libcxl/include -lrt -lpthread
