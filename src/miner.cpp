#include "miner.h"
#include "blake3.h"
#include <cstring>
#include <chrono>
#include <omp.h>
#include <iostream>
#include <iomanip>

Miner::Miner(std::unique_ptr<ComputeDevice> device) : device_(std::move(device)) {}

inline bool check_diff_fast(const uint8_t* hash, int bits) {
    int full_bytes = bits / 8;
    for (int i = 0; i < full_bytes; ++i) if (hash[i] != 0) return false;
    if (bits % 8 > 0) {
        uint8_t mask = (0xFF << (8 - (bits % 8))) & 0xFF;
        if ((hash[full_bytes] & mask) != 0) return false;
    }
    return true;
}

MiningResult Miner::mine(const std::vector<uint8_t>& rpc_seed, int difficulty_bits, uint64_t max_iterations) {
    auto start = std::chrono::high_resolution_clock::now();
    std::vector<uint8_t> base_seed = rpc_seed;
    if (base_seed.size() != 240) base_seed.resize(240, 0);

    MiningResult final_res = {false, {}, {}, 0, 0};
    bool found_global = false;
    uint64_t total_iterations = 0;
    auto last_progress = std::chrono::high_resolution_clock::now();

    #pragma omp parallel
    {
        int thread_id = omp_get_thread_num();
        int num_threads = omp_get_num_threads();
        
        std::vector<uint8_t> xof_buf(2 * M * K);
        int32_t local_C[M * N];
        std::vector<uint8_t> local_seed = base_seed;
        
        // Use all 12 bytes of the nonce (240 - 12 = 228)
        uint64_t* n_low = reinterpret_cast<uint64_t*>(&local_seed[228]);
        uint32_t* n_high = reinterpret_cast<uint32_t*>(&local_seed[236]);
        
        // Distribute starting points
        *n_low = (uint64_t)thread_id * (0xFFFFFFFFFFFFFFFF / num_threads);
        *n_high = (uint32_t)thread_id;

        blake3_hasher hasher;
        uint8_t h_out[BLAKE3_OUT_LEN];
        uint64_t local_iterations = 0;

        for (uint64_t i = 0; i < (max_iterations / num_threads) && !found_global; ++i) {
            (*n_low)++;
            if (*n_low == 0) (*n_high)++;

            blake3_hasher_init(&hasher);
            blake3_hasher_update(&hasher, local_seed.data(), 240);
            blake3_hasher_finalize(&hasher, xof_buf.data(), xof_buf.size());
            
            device_->matmul(xof_buf.data(), reinterpret_cast<const int8_t*>(xof_buf.data() + (M * K)), local_C);

            blake3_hasher sol_hasher;
            blake3_hasher_init(&sol_hasher);
            blake3_hasher_update(&sol_hasher, local_seed.data(), 240);
            blake3_hasher_update(&sol_hasher, local_C, 1024);
            blake3_hasher_finalize(&sol_hasher, h_out, BLAKE3_OUT_LEN);

            if (check_diff_fast(h_out, difficulty_bits)) {
                #pragma omp critical
                {
                    if (!found_global) {
                        found_global = true;
                        final_res.success = true;
                        final_res.solution = local_seed;
                        const uint8_t* c_bytes = reinterpret_cast<const uint8_t*>(local_C);
                        final_res.solution.insert(final_res.solution.end(), c_bytes, c_bytes + 1024);
                        final_res.iterations = i * num_threads;
                    }
                }
            }

            local_iterations++;
            
            // Progress reporting every 1M iterations (thread 0 only)
            if (thread_id == 0 && (local_iterations % 1000000 == 0)) {
                #pragma omp critical
                {
                    total_iterations += 1000000 * num_threads;
                    auto now = std::chrono::high_resolution_clock::now();
                    auto elapsed = std::chrono::duration<double>(now - last_progress).count();
                    if (elapsed >= 5.0) {  // Report every 5 seconds
                        double total_elapsed = std::chrono::duration<double>(now - start).count();
                        double hps = total_iterations / elapsed;
                        double expected_hashes = 1ULL << difficulty_bits;
                        double progress = std::min(100.0, (total_iterations * 100.0) / expected_hashes);
                        std::cerr << "[Progress] " << (total_iterations / 1000000) << "M hashes, "
                                  << (int)hps << " H/s, ~" << std::fixed << std::setprecision(1) 
                                  << progress << "% expected" << std::endl;
                        last_progress = now;
                        total_iterations = 0;
                    }
                }
            }
        }

        #pragma omp critical
        {
            final_res.iterations += local_iterations;
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    final_res.duration_ms = std::chrono::duration<double, std::milli>(end - start).count();
    return final_res;
}