#include "miner.h"
#include <iostream>
#include <iomanip>
#include <cstring>
#include <chrono>
#include <random>
#include <algorithm>

// Mock Data for the environment
static const uint8_t MOCK_VR_HASH[32] = {0xAA}; // Fill with something
static const uint8_t MOCK_NODE_PK[48] = {0xBB};
static const uint8_t MOCK_NODE_POP[96] = {0xCC};

HardHackMiner::HardHackMiner(std::unique_ptr<ComputeDevice> compute_device) 
    : compute_(std::move(compute_device)) {
    // Initialize random mock keys
    trainer_pk_.resize(48, 0x01);
    trainer_pop_.resize(96, 0x02);
}

std::vector<uint8_t> HardHackMiner::build_seed() {
    // Total size: 4 + 32 + 48 + 96 + 48 + 12 = 240 bytes
    std::vector<uint8_t> seed;
    seed.reserve(240);

    // 1. Epoch (32-bit little endian)
    uint32_t epoch = current_epoch_;
    seed.push_back(epoch & 0xFF);
    seed.push_back((epoch >> 8) & 0xFF);
    seed.push_back((epoch >> 16) & 0xFF);
    seed.push_back((epoch >> 24) & 0xFF);

    // 2. Chain Segment VR Hash (32 bytes)
    seed.insert(seed.end(), MOCK_VR_HASH, MOCK_VR_HASH + 32);

    // 3. Trainer PK (48 bytes)
    seed.insert(seed.end(), trainer_pk_.begin(), trainer_pk_.end());

    // 4. Trainer POP (96 bytes)
    seed.insert(seed.end(), trainer_pop_.begin(), trainer_pop_.end());

    // 5. Trainer PK (Again, per spec? "Application.fetch_env!(:ama, :trainer_pk)::48-binary")
    // The spec lists it twice? "Application.fetch_env!(:ama, :trainer_pk)::48-binary" then "Application.fetch_env!(:ama, :trainer_pk)::48-binary" 
    // Wait, the spec snippet:
    // seed = << epoch, vr_hash, trainer_pk, trainer_pop, trainer_pk, rand(12) >>
    // Yes, it appears twice.
    seed.insert(seed.end(), trainer_pk_.begin(), trainer_pk_.end());

    // 6. Nonce (12 bytes random)
    // We use a thread-local random device or just a static one for now
    static std::random_device rd;
    static std::mt19937 gen(rd());
    std::uniform_int_distribution<uint8_t> dis(0, 255);
    
    for (int i = 0; i < 12; ++i) {
        seed.push_back(dis(gen));
    }

    return seed;
}

void HardHackMiner::generate_matrices(const std::vector<uint8_t>& seed, 
                                      std::vector<int8_t>& mat_a, 
                                      std::vector<int8_t>& mat_b) {
    size_t size_a = MATRIX_A_ROWS * MATRIX_A_COLS;
    size_t size_b = MATRIX_B_ROWS * MATRIX_B_COLS;
    
    mat_a.resize(size_a);
    mat_b.resize(size_b);

    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, seed.data(), seed.size());
    
    // XOF Output
    // We can output directly into the vectors since they are contiguous
    // Check if vector storage is guaranteed contiguous (Yes in C++11+)
    
    // Output A
    blake3_hasher_finalize(&hasher, reinterpret_cast<uint8_t*>(mat_a.data()), size_a);
    
    // Output B
    // We want bytes from offset size_a to size_a + size_b
    blake3_hasher_finalize_seek(&hasher, size_a, reinterpret_cast<uint8_t*>(mat_b.data()), size_b);
}

bool HardHackMiner::check_solution(const std::vector<uint8_t>& seed, 
                                   const std::vector<uint8_t>& mat_c) {
    std::vector<uint8_t> solution;
    solution.reserve(seed.size() + mat_c.size());
    solution.insert(solution.end(), seed.begin(), seed.end());
    solution.insert(solution.end(), mat_c.begin(), mat_c.end());

    uint8_t hash[BLAKE3_OUT_LEN];
    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, solution.data(), solution.size());
    blake3_hasher_finalize(&hasher, hash, BLAKE3_OUT_LEN);

    // Check leading zeros
    // Spec says "diff_bits". 
    // We'll mock a difficulty check. e.g. 2 leading zero bytes for test
    if (hash[0] == 0 && hash[1] == 0) {
        // Found one!
        return true;
    }
    return false;
}

void HardHackMiner::mine(int iterations, bool json_output) {
    std::vector<int8_t> mat_a;
    std::vector<int8_t> mat_b;
    std::vector<uint8_t> mat_c;
    
    // Pre-allocate to avoid thrashing (though resize handles this mostly)
    mat_a.reserve(MATRIX_A_ROWS * MATRIX_A_COLS);
    mat_b.reserve(MATRIX_B_ROWS * MATRIX_B_COLS);
    mat_c.reserve(RESULT_ROWS * RESULT_COLS * 4);

    if (!json_output) {
        std::cout << "Starting Hard Hack Miner on " << compute_->name() << "..." << std::endl;
        std::cout << "Batch Size: " << iterations << std::endl;
    }

    auto start = std::chrono::high_resolution_clock::now();
    int valid_solutions = 0;

    for (int i = 0; i < iterations; ++i) {
        // 1. Build Seed
        auto seed = build_seed();
        
        // 2. Generate
        generate_matrices(seed, mat_a, mat_b);
        
        // 3. Multiply
        compute_->multiply(mat_a, mat_b, mat_c);
        
        // 4. Check
        if (check_solution(seed, mat_c)) {
            valid_solutions++;
            if (!json_output) {
                std::cout << "[!] Solution Found!" << std::endl;
            }
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> diff = end - start;
    double total_time = diff.count();
    double throughput = iterations / total_time;

    if (json_output) {
        std::cout << "{"
                  << "\"iterations\": " << iterations << ", "
                  << "\"time_sec\": " << total_time << ", "
                  << "\"throughput\": " << throughput << ", "
                  << "\"valid_found\": " << valid_solutions
                  << "}" << std::endl;
    } else {
        std::cout << "--------------------------------"
                  << "Mining Finished." << std::endl;
        std::cout << "Time: " << std::fixed << std::setprecision(4) << total_time << "s" << std::endl;
        std::cout << "Throughput: " << std::fixed << std::setprecision(2) << throughput << " hashes/sec" << std::endl;
        std::cout << "Valid Solutions: " << valid_solutions << std::endl;
        std::cout << "--------------------------------" << std::endl;
    }
}