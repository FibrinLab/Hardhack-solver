cmake_minimum_required(VERSION 3.16)
project(hardhack_kernel)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Optimization Flags
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -funroll-loops -ffast-math")

# Global Include Directories
include_directories(include)

# 1. OpenMP (Critical for multi-threaded performance)
find_package(OpenMP)
if(OpenMP_CXX_FOUND)
    link_libraries(OpenMP::OpenMP_CXX)
else()
    # Manual check for Homebrew libomp on macOS
    if(APPLE)
        execute_process(COMMAND brew --prefix libomp OUTPUT_VARIABLE OMP_PREFIX OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(OMP_PREFIX)
            include_directories("${OMP_PREFIX}/include")
            link_directories("${OMP_PREFIX}/lib")
            set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Xpreprocessor -fopenmp")
            link_libraries(omp)
        endif()
    endif()
endif()

# 2. Blake3
set(BLAKE3_SOURCES
    libs/blake3/c/blake3.c 
    libs/blake3/c/blake3_dispatch.c 
    libs/blake3/c/blake3_portable.c
)
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64")
    list(APPEND BLAKE3_SOURCES
        libs/blake3/c/blake3_sse2_x86-64_unix.S
        libs/blake3/c/blake3_sse41_x86-64_unix.S
        libs/blake3/c/blake3_avx2_x86-64_unix.S
        libs/blake3/c/blake3_avx512_x86-64_unix.S
    )
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
    list(APPEND BLAKE3_SOURCES libs/blake3/c/blake3_neon.c)
endif()
add_library(blake3 STATIC ${BLAKE3_SOURCES})
target_include_directories(blake3 PUBLIC libs/blake3/c)

# 3. Source Files
set(SOURCES
    src/main.cpp
    src/miner.cpp
    src/compute_cpu.cpp
)

add_executable(hardhack_miner ${SOURCES})
target_link_libraries(hardhack_miner PRIVATE blake3 pthread dl)