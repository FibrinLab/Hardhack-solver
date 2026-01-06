#include <iostream>
#include <string>
#include <vector>
#include <memory>
#include "miner.h"
#include "compute.h"

// Base58 Alphabet
const char* B58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

std::string to_base58(const std::vector<uint8_t>& data) {
    std::vector<uint8_t> digits(data.size() * 138 / 100 + 1, 0);
    size_t size = 0;
    for (uint8_t b : data) {
        int carry = b;
        for (size_t i = 0; i < size || carry; ++i) {
            carry += 58 * digits[i];
            digits[i] = carry % 256;
            carry /= 256;
            size = std::max(size, i + 1);
        }
    }
    std::string res;
    for (uint8_t b : data) if (b == 0) res += B58_ALPHABET[0]; else break;
    for (size_t i = size; i-- > 0; ) {
        int carry = digits[i];
        for (size_t j = 0; j < res.size() || carry; ++j) {
            // This is a simplified B58, for the competition we use a standard lib-style approach
        }
    }
    // For the sake of the competition, we'll output raw hex and use 'openssl' or 'xxd' in bash 
    // to handle the binary POST which is the organizers' preferred method.
    return ""; 
}

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
    uint64_t iterations = 0;

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
    MiningResult res = miner.mine(hex_to_bytes(seed_hex), difficulty, iterations == 0 ? 0xFFFFFFFFFFFFFFFF : iterations);

    double hps = (res.duration_ms > 0) ? (res.iterations / (res.duration_ms / 1000.0)) : 0;

    std::cout << "{"
              << "\"found\": " << (res.success ? "true" : "false") << ", "
              << "\"iterations\": " << res.iterations << ", "
              << "\"hashes_per_sec\": " << hps << ", "
              << "\"solution_hex\": \"" << (res.success ? bytes_to_hex(res.solution) : "") << "\""
              << "}" << std::endl;

    return 0;
}
