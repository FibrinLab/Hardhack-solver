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
    
    # Try to find headers in standard locations or /opt/tt-metal
    include_directories(
        /opt/tt-metal
        /opt/tt-metal/tt_metal
        /opt/tt-metal/tt_metal/include
        /opt/tt-metal/tt_metal/hw/inc
        /opt/tt-metal/tt_metal/api
        /opt/tt-metal/tt_metal/api/tt-metalium
        /opt/tt-metal/tt_stl
        /opt/tt-metal/tt_stl/tt_stl
        /opt/ronin/jitte/src/tt_metal/tt_stl/reflect
        /opt/ronin/include
        /usr/local/include
    )
    link_directories(/opt/tt-metal/lib /usr/local/lib)

    # Link against tt_metal and its dependencies
    # Note: You might need to adjust specific library names based on the SDK version
    # common ones: tt_metal, yaml-cpp
    set(TT_LIBS tt_metal yaml-cpp)
endif()

add_subdirectory(libs/blake3/c)

add_executable(hardhack_miner 
    src/main.cpp 
    src/miner.cpp
    src/compute_cpu.cpp
    src/compute_tt.cpp
)

if(ENABLE_TT)
    target_link_libraries(hardhack_miner blake3 pthread ${TT_LIBS})
else()
    target_link_libraries(hardhack_miner blake3 pthread)
endif()
