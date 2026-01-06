#pragma once

#include <vector>
#include <cstdint>
#include <string>
#include <memory>
#include "blake3.h"
#include "compute.h"

// Structure to hold the solution components
struct Solution {
    std::vector<uint8_t> seed;
    std::vector<uint8_t> matrix_c; // Result matrix data
    std::vector<uint8_t> full_data; // seed <> matrix_c
    std::string hash_hex;
};

class HardHackMiner {
public:
    // Pass in the desired compute backend
    HardHackMiner(std::unique_ptr<ComputeDevice> compute_device);
    
    // Main mining loop for a given duration or iteration count
    void mine(int iterations, bool json_output = false);

private:
    std::unique_ptr<ComputeDevice> compute_;

    // Constants from spec
    static constexpr int MATRIX_A_ROWS = 16;

    static constexpr int MATRIX_A_COLS = 50240;
    static constexpr int MATRIX_B_ROWS = 50240;
    static constexpr int MATRIX_B_COLS = 16;
    static constexpr int RESULT_ROWS = 16;
    static constexpr int RESULT_COLS = 16;
    
    // Helper to generate deterministic seed
    std::vector<uint8_t> build_seed();

    // Generate matrices from seed using Blake3 XOF
    // Returns pointers to internal buffers or fills vectors
    void generate_matrices(const std::vector<uint8_t>& seed, 
                           std::vector<int8_t>& mat_a, 
                           std::vector<int8_t>& mat_b);

    // Check if solution is valid
    bool check_solution(const std::vector<uint8_t>& seed, 
                        const std::vector<uint8_t>& mat_c);

    // Mock constants for the "Epoch" data
    uint32_t current_epoch_ = 1;
    std::vector<uint8_t> trainer_pk_;
    std::vector<uint8_t> trainer_pop_;
    
    // Performance metrics
    size_t solutions_found_ = 0;
};