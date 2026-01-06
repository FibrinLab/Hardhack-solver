cmake_minimum_required(VERSION 3.16)
project(hardhack_kernel)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

include_directories(include)

# 1. OpenMP
find_package(OpenMP)
if(OpenMP_CXX_FOUND)
    link_libraries(OpenMP::OpenMP_CXX)
else()
    if(APPLE)
        execute_process(COMMAND brew --prefix libomp OUTPUT_VARIABLE OMP_PREFIX OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
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
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64")
    list(APPEND BLAKE3_SOURCES
        libs/blake3/c/blake3_sse2.c
        libs/blake3/c/blake3_sse41.c
        libs/blake3/c/blake3_avx2.c
        libs/blake3/c/blake3_avx512.c
    )
    set_source_files_properties(libs/blake3/c/blake3_sse2.c PROPERTIES COMPILE_FLAGS "-msse2")
    set_source_files_properties(libs/blake3/c/blake3_sse41.c PROPERTIES COMPILE_FLAGS "-msse4.1")
    set_source_files_properties(libs/blake3/c/blake3_avx2.c PROPERTIES COMPILE_FLAGS "-mavx2")
    set_source_files_properties(libs/blake3/c/blake3_avx512.c PROPERTIES COMPILE_FLAGS "-mavx512f -mavx512vl -mavx512bw -mavx512dq")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
    list(APPEND BLAKE3_SOURCES libs/blake3/c/blake3_neon.c)
endif()
add_library(blake3 STATIC ${BLAKE3_SOURCES})
target_include_directories(blake3 PUBLIC libs/blake3/c)

# 3. Tenstorrent Metal
if(ENABLE_TT)
    add_definitions(-DENABLE_TT)
    include_directories(/opt/tt-metal)
    include_directories(/opt/tt-metal/tt_metal/include)
    include_directories(/opt/tt-metal/tt_metal/api)
    link_directories(/opt/tt-metal/build/lib)
endif()

# --- TARGET A: The Miner ---
add_executable(hardhack_miner 
    src/main.cpp 
    src/miner.cpp 
    src/compute_cpu.cpp
)
if(ENABLE_TT)
    target_sources(hardhack_miner PRIVATE src/compute_tt.cpp)
    target_link_libraries(hardhack_miner PRIVATE tt_metal)
endif()
target_link_libraries(hardhack_miner PRIVATE blake3 pthread dl)

# --- TARGET B: The Succinct Prover ---
add_executable(hardhack_prover 
    src/prover_main.cpp 
)
target_link_libraries(hardhack_prover PRIVATE blake3 pthread dl)