#include <iostream>
#include <vector>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <cstring>
#include <string>
#include <cstdint>
#include "merkle.h"
#include "blake3.h"

// Helper to convert bytes to hex
std::string bytes_to_hex(const uint8_t* bytes, size_t len) {
    std::stringstream ss;
    for (size_t i = 0; i < len; ++i) {
        ss << std::hex << std::setw(2) << std::setfill('0') << (int)bytes[i];
    }
    return ss.str();
}

// Generate leaves from seed
std::vector<std::vector<uint8_t>> generate_leaves_from_seed(const std::string& seed_hex, size_t leaf_count, size_t leaf_size = 256) {
    std::vector<std::vector<uint8_t>> leaves;
    leaves.reserve(leaf_count);
    
    // Use seed to generate deterministic leaves
    uint8_t seed_hash[32];
    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, seed_hex.data(), seed_hex.size());
    blake3_hasher_finalize(&hasher, seed_hash, 32);
    
    // Generate leaves using BLAKE3 XOF
    uint8_t xof_buffer[4096];
    blake3_hasher xof_hasher;
    blake3_hasher_init(&xof_hasher);
    blake3_hasher_update(&xof_hasher, seed_hash, 32);
    blake3_hasher_finalize(&xof_hasher, xof_buffer, sizeof(xof_buffer));
    
    for (size_t i = 0; i < leaf_count; i++) {
        std::vector<uint8_t> leaf(leaf_size);
        
        // Generate leaf data deterministically
        blake3_hasher leaf_hasher;
        blake3_hasher_init(&leaf_hasher);
        blake3_hasher_update(&leaf_hasher, seed_hash, 32);
        uint32_t index = i;
        blake3_hasher_update(&leaf_hasher, &index, sizeof(index));
        blake3_hasher_finalize(&leaf_hasher, leaf.data(), leaf_size);
        
        leaves.push_back(leaf);
    }
    
    return leaves;
}

int main(int argc, char* argv[]) {
    size_t tree_size = 1024;  // Default: 1024 leaves
    std::string seed_hex = "";
    uint32_t proof_index = 0;
    bool benchmark_mode = false;
    
    // Parse arguments
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--seed" && i + 1 < argc) {
            seed_hex = argv[++i];
        } else if (arg == "--size" && i + 1 < argc) {
            tree_size = std::stoul(argv[++i]);
        } else if (arg == "--index" && i + 1 < argc) {
            proof_index = std::stoul(argv[++i]);
        } else if (arg == "--benchmark") {
            benchmark_mode = true;
        }
    }
    
    // Generate seed if not provided
    if (seed_hex.empty()) {
        uint8_t random_seed[32];
        blake3_hasher hasher;
        blake3_hasher_init(&hasher);
        blake3_hasher_update(&hasher, &tree_size, sizeof(tree_size));
        auto now = std::chrono::system_clock::now().time_since_epoch().count();
        blake3_hasher_update(&hasher, &now, sizeof(now));
        blake3_hasher_finalize(&hasher, random_seed, 32);
        seed_hex = bytes_to_hex(random_seed, 32);
    }
    
    std::cout << "[*] Challenge B: Merkle Proof on RISC-V" << std::endl;
    std::cout << "[*] Tree size: " << tree_size << " leaves" << std::endl;
    std::cout << "[*] Seed: " << seed_hex.substr(0, 16) << "..." << std::endl;
    
    // Generate leaves
    auto start_gen = std::chrono::high_resolution_clock::now();
    std::vector<std::vector<uint8_t>> leaves = generate_leaves_from_seed(seed_hex, tree_size);
    auto end_gen = std::chrono::high_resolution_clock::now();
    double gen_time = std::chrono::duration<double, std::milli>(end_gen - start_gen).count();
    
    // Build Merkle tree
    MerkleTree tree;
    auto start_build = std::chrono::high_resolution_clock::now();
    std::vector<uint8_t> root = tree.build_tree(leaves);
    auto end_build = std::chrono::high_resolution_clock::now();
    double build_time = std::chrono::duration<double, std::milli>(end_build - start_build).count();
    
    if (root.empty()) {
        std::cerr << "[!] Error: Failed to build tree" << std::endl;
        return 1;
    }
    
    // Generate proof
    proof_index = proof_index % tree_size;
    auto start_proof = std::chrono::high_resolution_clock::now();
    MerkleProof proof = tree.generate_proof(proof_index);
    auto end_proof = std::chrono::high_resolution_clock::now();
    double proof_time = std::chrono::duration<double, std::milli>(end_proof - start_proof).count();
    
    // Verify proof
    auto start_verify = std::chrono::high_resolution_clock::now();
    bool valid = MerkleTree::verify_proof(proof);
    auto end_verify = std::chrono::high_resolution_clock::now();
    double verify_time = std::chrono::duration<double, std::milli>(end_verify - start_verify).count();
    
    // Calculate statistics
    size_t proof_size = 32 + 4 + (proof.siblings.size() * 32) + 32;  // leaf + index + siblings + root
    size_t tree_size_bytes = tree.get_leaf_count() * 32 * (tree.get_tree_height() + 1);
    
    // Calculate hashes per second (approximate)
    size_t total_hashes = tree_size + tree_size - 1;  // leaves + internal nodes
    double total_time_sec = build_time / 1000.0;
    uint64_t hashes_per_sec = total_time_sec > 0 ? (total_hashes / total_time_sec) : 0;
    
    // Output JSON
    std::cout << "{"
              << "\"type\": \"merkle_proof\", "
              << "\"status\": \"" << (valid ? "success" : "failure") << "\", "
              << "\"tree_size\": " << tree_size << ", "
              << "\"tree_height\": " << tree.get_tree_height() << ", "
              << "\"proof_index\": " << proof_index << ", "
              << "\"root_hash\": \"" << bytes_to_hex(root.data(), root.size()) << "\", "
              << "\"proof_size_bytes\": " << proof_size << ", "
              << "\"tree_size_bytes\": " << tree_size_bytes << ", "
              << "\"build_time_ms\": " << std::fixed << std::setprecision(3) << build_time << ", "
              << "\"proof_generation_time_ms\": " << proof_time << ", "
              << "\"proof_verification_time_ms\": " << verify_time << ", "
              << "\"hashes_per_sec\": " << hashes_per_sec << ", "
              << "\"seed\": \"" << seed_hex << "\""
              << "}" << std::endl;
    
    if (benchmark_mode) {
        std::cout << "\n[Benchmark Results]" << std::endl;
        std::cout << "  Tree Build:      " << build_time << " ms" << std::endl;
        std::cout << "  Proof Gen:       " << proof_time << " ms" << std::endl;
        std::cout << "  Proof Verify:    " << verify_time << " ms" << std::endl;
        std::cout << "  Hashes/sec:      " << hashes_per_sec << std::endl;
        std::cout << "  Proof Size:      " << proof_size << " bytes" << std::endl;
    }
    
    return valid ? 0 : 1;
}
