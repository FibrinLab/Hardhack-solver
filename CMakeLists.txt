cmake_minimum_required(VERSION 3.10)
project(hardhack_miner)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Optimization flags
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -funroll-loops -Wall")

# Find BLAS removed as we use custom Int8 implementation

include_directories(include libs/blake3/c)

option(ENABLE_TT "Enable Tenstorrent Accelerator Support" OFF)

if(ENABLE_TT)
    add_definitions(-DENABLE_TT)
    # find_package(TTMetal REQUIRED) # Uncomment when available
endif()

add_subdirectory(libs/blake3/c)

add_executable(hardhack_miner 
    src/main.cpp 
    src/miner.cpp
    src/compute_cpu.cpp
    src/compute_tt.cpp
)
target_link_libraries(hardhack_miner blake3 pthread)
