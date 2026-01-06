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

int main(int argc, char* argv[]) {
    std::string seed_hex = "00000000";
    int difficulty = 10;
    uint64_t iterations = 100;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--seed" && i + 1 < argc) seed_hex = argv[++i];
        else if (arg == "--difficulty" && i + 1 < argc) difficulty = std::stoi(argv[++i]);
        else if (arg == "--iterations" && i + 1 < argc) iterations = std::stoull(argv[++i]);
    }

    std::unique_ptr<ComputeDevice> compute_device;
#ifdef ENABLE_TT
    compute_device = create_tt_compute();
#else
    compute_device = create_cpu_compute();
#endif

    Miner miner(std::move(compute_device));
    MiningResult res = miner.mine(hex_to_bytes(seed_hex), difficulty, iterations);

    double hps = (res.duration_ms > 0) ? (res.iterations / (res.duration_ms / 1000.0)) : 0;

    std::cout << "{"
              << "\"found\": " << (res.success ? "true" : "false") << ", "
              << "\"iterations\": " << res.iterations << ", "
              << "\"duration_ms\": " << res.duration_ms << ", "
              << "\"hashes_per_sec\": " << hps
              << "}" << std::endl;

    return 0;
}
