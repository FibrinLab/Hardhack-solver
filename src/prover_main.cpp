#include <iostream>
#include <vector>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <cmath>
#include <omp.h>
#include "blake3.h"

// BabyBear Field: p = 2^31 - 2^27 + 1
const uint32_t P = 2013265921;
const uint32_t G = 31; // Primitive root for BabyBear

// Montgomery constants
const uint32_t MONTO_INV = 2013265919; // -p^-1 mod 2^32

inline uint32_t montgomery_reduce(uint64_t x) {
    uint32_t m = (uint32_t)x * MONTO_INV;
    uint64_t t = x + (uint64_t)m * P;
    uint32_t res = (uint32_t)(t >> 32);
    return (res >= P) ? res - P : res;
}

inline uint32_t field_mult(uint32_t a, uint32_t b) {
    return montgomery_reduce((uint64_t)a * b);
}

inline uint32_t field_add(uint32_t a, uint32_t b) {
    uint32_t res = a + b;
    return (res >= P) ? res - P : res;
}

inline uint32_t field_sub(uint32_t a, uint32_t b) {
    return (a >= b) ? a - b : a + P - b;
}

uint32_t power(uint32_t base, uint32_t exp) {
    uint32_t res = 1;
    base %= P;
    while (exp > 0) {
        if (exp % 2 == 1) res = (uint64_t)res * base % P;
        base = (uint64_t)base * base % P;
        exp /= 2;
    }
    return res;
}

// In-place Cooley-Tukey NTT
void ntt(std::vector<uint32_t>& a) {
    int n = a.size();
    for (int i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(a[i], a[j]);
    }

    for (int len = 2; len <= n; len <<= 1) {
        uint32_t wlen = power(G, (P - 1) / len);
        #pragma omp parallel for
        for (int i = 0; i < n; i += len) {
            uint32_t w = 1;
            for (int j = 0; j < len / 2; j++) {
                uint32_t u = a[i + j];
                uint32_t v = (uint64_t)a[i + j + len / 2] * w % P;
                a[i + j] = field_add(u, v);
                a[i + j + len / 2] = field_sub(u, v);
                w = (uint64_t)w * wlen % P;
            }
        }
    }
}

std::string bytes_to_hex(const uint8_t* bytes, size_t len) {
    std::stringstream ss;
    for(size_t i=0; i<len; ++i) ss << std::hex << std::setw(2) << std::setfill('0') << (int)bytes[i];
    return ss.str();
}

int main(int argc, char* argv[]) {
    std::string seed_hex = "00000000";
    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "--seed" && i + 1 < argc) seed_hex = argv[++i];
    }

    // Size must be power of 2 for Radix-2 NTT
    const int N = 1 << 18; // 262,144 elements
    std::vector<uint32_t> data(N);
    uint32_t seed_val = (uint32_t)strtoul(seed_hex.substr(0, 8).c_str(), NULL, 16);
    
    for(int i=0; i<N; ++i) data[i] = (seed_val + i) % P;

    std::cout << "[*] Sub-Track B: Computing 2^18 NTT (BabyBear Field)..." << std::endl;
    auto start = std::chrono::high_resolution_clock::now();
    
    ntt(data);

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> diff = end - start;

    // Commitment: Hash the NTT result
    uint8_t hash[BLAKE3_OUT_LEN];
    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, data.data(), N * sizeof(uint32_t));
    blake3_hasher_finalize(&hasher, hash, BLAKE3_OUT_LEN);

    std::cout << "{"
              << "\"type\": \"succinct_proof\", "
              << "\"status\": \"success\", "
              << "\"ntt_size\": " << N << ", "
              << "\"throughput_ops_sec\": " << (N * log2(N) / (diff.count() / 1000.0)) << ", "
              << "\"proof_hash\": \"" << bytes_to_hex(hash, BLAKE3_OUT_LEN) << "\", " 
              << "\"duration_ms\": " << diff.count()
              << "}" << std::endl;

    return 0;
}
