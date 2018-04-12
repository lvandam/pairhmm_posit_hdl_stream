cmake_minimum_required(VERSION 3.0)
project(pairhmm)

set(SOURCES_DIR ${CMAKE_SOURCE_DIR}/../..)
# PSL
set(PSLSE_LIBCXL_DIR ${SOURCES_DIR}/sim/pslse/libcxl)
set(PSLSE_COMMON_DIR ${SOURCES_DIR}/sim/pslse/common)
set(PSLSE_LIBCXL_DIR ${SOURCES_DIR}/sim/pslse/libcxl)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_FLAGS "-O3 -Wall -m64 -fopenmp -DPOSIT_VERBOSE_OUTPUT")# -DDEBUG_VALUES -DDEBUG_VERBOSE #-DPOSIT_TRACE_DECODE -DPOSIT_TRACE_CONVERSION -DPOSIT_TRACE_ROUNDING")

set(EXTERNAL_INSTALL_LOCATION ${CMAKE_BINARY_DIR}/external)

include(ExternalProject)
ExternalProject_Add(universal
        GIT_REPOSITORY https://github.com/lvandam/universal
        GIT_TAG master
        PREFIX ${EXTERNAL_INSTALL_LOCATION}
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${EXTERNAL_INSTALL_LOCATION}
        CONFIGURE_COMMAND ""
        BUILD_COMMAND ""
        INSTALL_COMMAND ""
        )

include_directories(${EXTERNAL_INSTALL_LOCATION}/src/universal)

file(GLOB pairhmm_SRC
        "src/*.hpp"
        "src/*.cpp"
        )

# Host (CAPI)
add_executable(pairhmm_host ${pairhmm_SRC})
add_dependencies(pairhmm_host universal)
target_link_libraries(pairhmm_host /tools/ppc_64/libcxl/libcxl.a)
target_include_directories(pairhmm_host PRIVATE /tools/ppc_64/libcxl)
target_include_directories(pairhmm_host PRIVATE /tools/ppc_64/libcxl/include)
target_compile_options(pairhmm_host PRIVATE -lrt -lpthread)

# Sim (local)
add_executable(pairhmm_sim ${pairhmm_SRC})
add_dependencies(pairhmm_sim universal)
target_link_libraries(pairhmm_sim ${PSLSE_LIBCXL_DIR}/libcxl.a)
target_include_directories(pairhmm_sim PRIVATE ${PSLSE_COMMON_DIR})
target_include_directories(pairhmm_sim PRIVATE ${PSLSE_LIBCXL_DIR})
target_compile_options(pairhmm_sim PRIVATE -lrt -lpthread -D SIM)
