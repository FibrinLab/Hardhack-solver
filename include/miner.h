#pragma once
#include <string>
#include <vector>
#include <cstdint>
#include <memory>
#include "compute.h"

struct MiningResult {
    bool success;
    std::vector<uint8_t> nonce;
    std::vector<uint8_t> solution;
    double duration_ms;
    uint64_t iterations;
};

class Miner {
public:
    Miner(std::unique_ptr<ComputeDevice> device);

    // Iterates nonces internally for maximum speed
    MiningResult mine(const std::vector<uint8_t>& base_seed, int difficulty_bits, uint64_t max_iterations);

private:
    std::unique_ptr<ComputeDevice> device_;

    void generate_matrices(const std::vector<uint8_t>& seed, 
                          std::vector<uint8_t>& A, 
                          std::vector<uint8_t>& B);
    
    bool check_difficulty(const std::vector<uint8_t>& solution, int bits);
};
