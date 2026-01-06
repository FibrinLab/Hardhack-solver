#include "miner.h"
#include "blake3.h"
#include <cstring>
#include <chrono>
#include <omp.h>

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

MiningResult Miner::mine(const std::vector<uint8_t>& base_seed, int difficulty_bits, uint64_t max_iterations) {
    auto start = std::chrono::high_resolution_clock::now();
    std::vector<uint8_t> seed_template = base_seed;
    if (seed_template.size() < 240) seed_template.resize(240, 0);

    blake3_hasher base_hasher;
    blake3_hasher_init(&base_hasher);
    blake3_hasher_update(&base_hasher, seed_template.data(), 228);

    MiningResult final_res = {false, {}, {}, 0, max_iterations};
    bool found_global = false;

    #pragma omp parallel
    {
        int thread_id = omp_get_thread_num();
        int num_threads = omp_get_num_threads();
        
        std::vector<uint8_t> xof_buf(M * K + K * N);
        std::vector<uint8_t> local_C(M * N);
        std::vector<uint8_t> local_seed = seed_template;
        uint64_t* nonce_ptr = reinterpret_cast<uint64_t*>(&local_seed[228]);
        *nonce_ptr = (uint64_t)thread_id * (0xFFFFFFFFFFFFFFFF / num_threads);

        blake3_hasher thread_hasher;
        uint8_t h_out[BLAKE3_OUT_LEN];

        for (uint64_t i = 0; i < (max_iterations / num_threads) && !found_global; ++i) {
            (*nonce_ptr)++;

            // Incremental hash
            std::memcpy(&thread_hasher, &base_hasher, sizeof(blake3_hasher));
            blake3_hasher_update(&thread_hasher, &local_seed[228], 12);
            
            // XOF generation is the bottleneck. We generate it in one call here, 
            // but the C++ threads are already parallelized via OMP.
            blake3_hasher_finalize(&thread_hasher, xof_buf.data(), xof_buf.size());
            
            device_->matmul(xof_buf.data(), xof_buf.data() + (M * K), local_C.data());

            blake3_hasher sol_hasher;
            blake3_hasher_init(&sol_hasher);
            blake3_hasher_update(&sol_hasher, local_seed.data(), 240);
            blake3_hasher_update(&sol_hasher, local_C.data(), M * N);
            blake3_hasher_finalize(&sol_hasher, h_out, BLAKE3_OUT_LEN);

            if (check_diff_fast(h_out, difficulty_bits)) {
                #pragma omp critical
                {
                    if (!found_global) {
                        found_global = true;
                        final_res.success = true;
                        final_res.nonce = std::vector<uint8_t>(local_seed.end() - 12, local_seed.end());
                        final_res.iterations = i * num_threads;
                    }
                }
            }
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    final_res.duration_ms = std::chrono::duration<double, std::milli>(end - start).count();
    return final_res;
}
