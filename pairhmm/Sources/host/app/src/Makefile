program_NAME 					:= pairhmm
program_C_SRCS 				:= $(wildcard *.c)
program_C_OBJS 				:= ${program_C_SRCS:.c=.o}
program_OBJS 					:= $(program_C_OBJS)
program_INCLUDE_DIRS 	:= /tools/ppc_64/libcxl
program_LIBRARY_DIRS 	:= /tools/ppc_64/libcxl
program_LIBRARIES 		:= 
program_STATIC_LIBS		:= /tools/ppc_64/libcxl/libcxl.a

CFLAGS 	+= $(foreach includedir,$(program_INCLUDE_DIRS),-I$(includedir)) 
CFLAGS	+= -std=c99 -Wall -m64 -lrt -lpthread -fopenmp 
LDFLAGS += $(foreach librarydir,$(program_LIBRARY_DIRS),-L$(librarydir))
LDFLAGS += $(foreach library,$(program_LIBRARIES),-l$(library))

.PHONY: all clean distclean

all: $(program_NAME)

debug: CFLAGS += -DDEBUG
debug: $(program_OBJS)
	gcc -o $(program_NAME) $(program_OBJS) $(program_STATIC_LIBS) $(LDFLAGS) $(CFLAGS)
	
$(program_NAME): $(program_OBJS)
	gcc -o $(program_NAME) $(program_OBJS) $(program_STATIC_LIBS) $(LDFLAGS) $(CFLAGS)

clean:
	@- $(RM) $(program_NAME)
	@- $(RM) $(program_OBJS)

distclean: clean

