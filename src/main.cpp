#include <iostream>
#include <string>
#include <vector>
#include <memory>
#include "miner.h"
#include "compute.h"

std::vector<uint8_t> hex_to_bytes(const std::string& hex) {
    std::vector<uint8_t> bytes;
    for (unsigned int i = 0; i < hex.length(); i += 2) {
        std::string byteString = hex.substr(i, 2);
        uint8_t byte = (uint8_t) strtol(byteString.c_str(), NULL, 16);
        bytes.push_back(byte);
    }
    return bytes;
}

std::string bytes_to_hex(const std::vector<uint8_t>& bytes) {
    std::string res;
    for (auto b : bytes) {
        char buf[3];
        snprintf(buf, 3, "%02x", b);
        res += buf;
    }
    return res;
}

int main(int argc, char* argv[]) {
    std::string seed_hex = "";
    int difficulty = 10;
    uint64_t iterations = 0; // Default to infinite

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--seed" && i + 1 < argc) seed_hex = argv[++i];
        else if (arg == "--difficulty" && i + 1 < argc) difficulty = std::stoi(argv[++i]);
        else if (arg == "--iterations" && i + 1 < argc) iterations = std::stoull(argv[++i]);
    }

    if (seed_hex.empty()) return 1;

    std::unique_ptr<ComputeDevice> compute_device;
#ifdef ENABLE_TT
    compute_device = create_tt_compute();
#else
    compute_device = create_cpu_compute();
#endif

    Miner miner(std::move(compute_device));
    
    // If iterations is 0, we loop forever in C++ until found
    uint64_t limit = (iterations == 0) ? 0xFFFFFFFFFFFFFFFF : iterations;
    
    MiningResult res = miner.mine(hex_to_bytes(seed_hex), difficulty, limit);

    double hps = (res.duration_ms > 0) ? (res.iterations / (res.duration_ms / 1000.0)) : 0;

    std::cout << "{" 
              << "\"found\": " << (res.success ? "true" : "false") << ", "
              << "\"iterations\": " << res.iterations << ", "
              << "\"hashes_per_sec\": " << hps << ", "
              << "\"solution_hex\": \"" << (res.success ? bytes_to_hex(res.solution) : "") << "\""
              << "}" << std::endl;

    return 0;
}