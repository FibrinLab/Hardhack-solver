#include "miner.h"
#include <iostream>
#include <iomanip>
#include <cstring>
#include <chrono>
#include <random>
#include <algorithm>

// Mock Data for the environment
static const uint8_t MOCK_VR_HASH[32] = {0xAA}; 
static const uint8_t MOCK_NODE_PK[48] = {0xBB};
static const uint8_t MOCK_NODE_POP[96] = {0xCC};

HardHackMiner::HardHackMiner(std::unique_ptr<ComputeDevice> compute_device) 
    : compute_(std::move(compute_device)) {
    trainer_pk_.resize(48, 0x01);
    trainer_pop_.resize(96, 0x02);
}

std::vector<uint8_t> HardHackMiner::build_seed() {
    std::vector<uint8_t> seed;
    seed.reserve(240);
    uint32_t epoch = current_epoch_;
    seed.push_back(epoch & 0xFF);
    seed.push_back((epoch >> 8) & 0xFF);
    seed.push_back((epoch >> 16) & 0xFF);
    seed.push_back((epoch >> 24) & 0xFF);
    seed.insert(seed.end(), MOCK_VR_HASH, MOCK_VR_HASH + 32);
    seed.insert(seed.end(), trainer_pk_.begin(), trainer_pk_.end());
    seed.insert(seed.end(), trainer_pop_.begin(), trainer_pop_.end());
    seed.insert(seed.end(), trainer_pk_.begin(), trainer_pk_.end());

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
    
    blake3_hasher_finalize(&hasher, reinterpret_cast<uint8_t*>(mat_a.data()), size_a);
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

    return (hash[0] == 0 && hash[1] == 0);
}

void HardHackMiner::mine(int iterations, bool json_output) {
    std::vector<int8_t> mat_a;
    std::vector<int8_t> mat_b;
    std::vector<uint8_t> mat_c;
    
    mat_a.reserve(MATRIX_A_ROWS * MATRIX_A_COLS);
    mat_b.reserve(MATRIX_B_ROWS * MATRIX_B_COLS);
    mat_c.reserve(RESULT_ROWS * RESULT_COLS * 4);

    auto start = std::chrono::high_resolution_clock::now();
    int valid_solutions = 0;

    for (int i = 0; i < iterations; ++i) {
        auto seed = build_seed();
        generate_matrices(seed, mat_a, mat_b);
        compute_->multiply(mat_a, mat_b, mat_c);
        if (check_solution(seed, mat_c)) {
            valid_solutions++;
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> diff = end - start;
    double total_time = diff.count();
    double throughput = iterations / total_time;
    
    // Calculate GOPS
    // Ops per solve = 16 * 16 * 50240 * 2 (approx)
    double ops_per_solve = (double)MATRIX_A_ROWS * RESULT_COLS * MATRIX_A_COLS * 2.0;
    double total_ops = ops_per_solve * iterations;
    double gops = (total_ops / total_time) / 1e9;

    if (json_output) {
        std::cout << "{"
                  << "\"iterations\": " << iterations << ", "
                  << "\"throughput_solves_sec\": " << std::fixed << std::setprecision(2) << throughput << ", "
                  << "\"gops\": " << std::fixed << std::setprecision(2) << gops << ", "
                  << "\"valid_found\": " << valid_solutions
                  << "}" << std::endl;
    } else {
        std::cout << "--------------------------------" << std::endl;
        std::cout << "Device: " << compute_->name() << std::endl;
        std::cout << "Solves/sec: " << std::fixed << std::setprecision(2) << throughput << std::endl;
        std::cout << "GOPS:       " << std::fixed << std::setprecision(2) << gops << std::endl;
        std::cout << "Valid:      " << valid_solutions << std::endl;
        std::cout << "--------------------------------" << std::endl;
    }
}
