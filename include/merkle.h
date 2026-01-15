#pragma once
#include <vector>
#include <cstdint>
#include <string>

// Merkle Proof Structure
struct MerkleProof {
    std::vector<uint8_t> leaf;          // The leaf data being proven
    uint32_t leaf_index;                // Index of the leaf in the tree
    std::vector<std::vector<uint8_t>> siblings;  // Sibling hashes from leaf to root
    std::vector<uint8_t> root_hash;     // Root hash for verification
};

// Merkle Tree optimized for RISC-V
class MerkleTree {
public:
    // Build a Merkle tree from leaves
    // Returns the root hash
    std::vector<uint8_t> build_tree(const std::vector<std::vector<uint8_t>>& leaves);
    
    // Generate a Merkle proof for a leaf at the given index
    MerkleProof generate_proof(uint32_t leaf_index) const;
    
    // Verify a Merkle proof
    static bool verify_proof(const MerkleProof& proof);
    
    // Get the root hash
    const std::vector<uint8_t>& get_root() const { return root_hash_; }
    
    // Get tree statistics
    size_t get_leaf_count() const { return leaf_count_; }
    size_t get_tree_height() const { return tree_height_; }

private:
    std::vector<std::vector<uint8_t>> tree_nodes_;  // All tree nodes (row by row)
    std::vector<uint8_t> root_hash_;                // Cached root hash
    size_t leaf_count_;                             // Number of leaves
    size_t tree_height_;                            // Height of the tree
    
    // Hash two nodes together
    static void hash_pair(const uint8_t* left, const uint8_t* right, uint8_t* output);
    
    // Hash a single node (for odd nodes at each level)
    static void hash_single(const uint8_t* node, uint8_t* output);
};

// Benchmark results
struct MerkleBenchmarkResult {
    double build_time_ms;
    double proof_generation_time_ms;
    double proof_verification_time_ms;
    size_t proof_size_bytes;
    size_t tree_size_bytes;
    uint64_t hashes_per_sec;
};
