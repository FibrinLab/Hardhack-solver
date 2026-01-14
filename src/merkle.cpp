#include "merkle.h"
#include "blake3.h"
#include <algorithm>
#include <cstring>
#include <cmath>

#define HASH_SIZE 32  // BLAKE3_OUT_LEN

void MerkleTree::hash_pair(const uint8_t* left, const uint8_t* right, uint8_t* output) {
    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, left, HASH_SIZE);
    blake3_hasher_update(&hasher, right, HASH_SIZE);
    blake3_hasher_finalize(&hasher, output, HASH_SIZE);
}

void MerkleTree::hash_single(const uint8_t* node, uint8_t* output) {
    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, node, HASH_SIZE);
    blake3_hasher_finalize(&hasher, output, HASH_SIZE);
}

std::vector<uint8_t> MerkleTree::build_tree(const std::vector<std::vector<uint8_t>>& leaves) {
    if (leaves.empty()) {
        root_hash_.clear();
        leaf_count_ = 0;
        tree_height_ = 0;
        return root_hash_;
    }
    
    leaf_count_ = leaves.size();
    
    // Calculate tree height (log2 of leaf count, rounded up)
    tree_height_ = 0;
    size_t temp = leaf_count_;
    while (temp > 1) {
        temp = (temp + 1) / 2;
        tree_height_++;
    }
    
    // Hash all leaves first
    tree_nodes_.clear();
    tree_nodes_.resize(tree_height_ + 1);
    
    std::vector<uint8_t> current_level;
    current_level.reserve(leaf_count_ * HASH_SIZE);
    
    // Hash each leaf
    for (const auto& leaf : leaves) {
        uint8_t hash[HASH_SIZE];
        blake3_hasher hasher;
        blake3_hasher_init(&hasher);
        blake3_hasher_update(&hasher, leaf.data(), leaf.size());
        blake3_hasher_finalize(&hasher, hash, HASH_SIZE);
        current_level.insert(current_level.end(), hash, hash + HASH_SIZE);
    }
    
    tree_nodes_[0] = current_level;
    
    // Build tree level by level
    std::vector<uint8_t> next_level;
    for (size_t level = 0; level < tree_height_; level++) {
        const std::vector<uint8_t>& level_nodes = tree_nodes_[level];
        size_t node_count = level_nodes.size() / HASH_SIZE;
        next_level.clear();
        next_level.reserve(((node_count + 1) / 2) * HASH_SIZE);
        
        // Hash pairs
        for (size_t i = 0; i < node_count; i += 2) {
            const uint8_t* left = level_nodes.data() + i * HASH_SIZE;
            uint8_t hash[HASH_SIZE];
            
            if (i + 1 < node_count) {
                // Pair of nodes
                const uint8_t* right = level_nodes.data() + (i + 1) * HASH_SIZE;
                hash_pair(left, right, hash);
            } else {
                // Odd node, hash with itself
                hash_single(left, hash);
            }
            
            next_level.insert(next_level.end(), hash, hash + HASH_SIZE);
        }
        
        tree_nodes_[level + 1] = next_level;
    }
    
    // Root hash is the only node at the top level
    root_hash_ = tree_nodes_[tree_height_];
    
    return root_hash_;
}

MerkleProof MerkleTree::generate_proof(uint32_t leaf_index) const {
    MerkleProof proof;
    
    if (leaf_index >= leaf_count_ || tree_nodes_.empty()) {
        return proof;  // Invalid index
    }
    
    // Get the leaf hash
    const std::vector<uint8_t>& leaf_level = tree_nodes_[0];
    proof.leaf.assign(leaf_level.begin() + leaf_index * HASH_SIZE, 
                     leaf_level.begin() + (leaf_index + 1) * HASH_SIZE);
    proof.leaf_index = leaf_index;
    proof.root_hash = root_hash_;
    
    // Build proof path from leaf to root
    uint32_t current_index = leaf_index;
    for (size_t level = 0; level < tree_height_; level++) {
        const std::vector<uint8_t>& level_nodes = tree_nodes_[level];
        uint32_t sibling_index = (current_index % 2 == 0) ? current_index + 1 : current_index - 1;
        size_t node_count = level_nodes.size() / HASH_SIZE;
        
        if (sibling_index < node_count) {
            // Sibling exists
            std::vector<uint8_t> sibling(HASH_SIZE);
            std::memcpy(sibling.data(), 
                       level_nodes.data() + sibling_index * HASH_SIZE, 
                       HASH_SIZE);
            proof.siblings.push_back(sibling);
        } else {
            // No sibling (odd node), use the node itself
            std::vector<uint8_t> sibling(HASH_SIZE);
            std::memcpy(sibling.data(), 
                       level_nodes.data() + current_index * HASH_SIZE, 
                       HASH_SIZE);
            proof.siblings.push_back(sibling);
        }
        
        current_index /= 2;
    }
    
    return proof;
}

bool MerkleTree::verify_proof(const MerkleProof& proof) {
    if (proof.siblings.empty()) {
        return false;
    }
    
    // Start with leaf hash
    uint8_t current_hash[HASH_SIZE];
    std::memcpy(current_hash, proof.leaf.data(), HASH_SIZE);
    
    // Recompute path to root
    uint32_t current_index = proof.leaf_index;
    for (size_t i = 0; i < proof.siblings.size(); i++) {
        const uint8_t* sibling = proof.siblings[i].data();
        uint8_t parent_hash[HASH_SIZE];
        
        if (current_index % 2 == 0) {
            // Current is left child
            hash_pair(current_hash, sibling, parent_hash);
        } else {
            // Current is right child
            hash_pair(sibling, current_hash, parent_hash);
        }
        
        std::memcpy(current_hash, parent_hash, HASH_SIZE);
        current_index /= 2;
    }
    
    // Compare with root hash
    return std::memcmp(current_hash, proof.root_hash.data(), HASH_SIZE) == 0;
}
