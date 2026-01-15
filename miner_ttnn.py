#!/usr/bin/env python3
"""
HardHack Miner using TTNN (Tenstorrent Neural Network) for GPU acceleration
"""

import os
import sys
import json
import time
import struct
import hashlib
import argparse
import subprocess

# Try to import ttnn
try:
    import ttnn
    import torch
    HAS_TTNN = True
except ImportError:
    HAS_TTNN = False
    print("Warning: ttnn not available, falling back to CPU", file=sys.stderr)

# Import blake3 if available, otherwise use hashlib
try:
    import blake3
    HAS_BLAKE3 = True
except ImportError:
    HAS_BLAKE3 = False


def blake3_hash(data: bytes) -> bytes:
    """Compute BLAKE3 hash of data"""
    if HAS_BLAKE3:
        return blake3.blake3(data).digest()
    else:
        # Fallback to hashlib (slower)
        return hashlib.blake3(data).digest()


def seed_to_matrices(seed: bytes):
    """Convert 240-byte seed to matrices A (32x32 uint8) and B (32x32 int8)"""
    # Hash seed to get deterministic matrix data
    h = blake3_hash(seed)
    
    # Generate matrix A (32x32 = 1024 bytes)
    a_data = bytearray()
    for i in range(32):  # Need 32 chunks of 32 bytes each
        chunk_seed = seed + struct.pack('<I', i)
        a_data.extend(blake3_hash(chunk_seed))
    A = list(a_data[:1024])
    
    # Generate matrix B (32x32 = 1024 bytes) 
    b_data = bytearray()
    for i in range(32, 64):
        chunk_seed = seed + struct.pack('<I', i)
        b_data.extend(blake3_hash(chunk_seed))
    # Convert to signed int8
    B = [x if x < 128 else x - 256 for x in b_data[:1024]]
    
    return A, B


def matmul_cpu(A: list, B: list) -> list:
    """CPU matrix multiplication: C = A @ B (32x32)"""
    C = [0] * 1024
    for i in range(32):
        for j in range(32):
            acc = 0
            for k in range(32):
                acc += A[i * 32 + k] * B[k * 32 + j]
            C[i * 32 + j] = acc
    return C


def matmul_ttnn(A: list, B: list, device) -> list:
    """TTNN GPU matrix multiplication: C = A @ B (32x32)"""
    # Convert to torch tensors
    A_tensor = torch.tensor(A, dtype=torch.float32).reshape(32, 32)
    B_tensor = torch.tensor(B, dtype=torch.float32).reshape(32, 32)
    
    # Move to TTNN device
    A_tt = ttnn.from_torch(A_tensor, device=device, layout=ttnn.TILE_LAYOUT)
    B_tt = ttnn.from_torch(B_tensor, device=device, layout=ttnn.TILE_LAYOUT)
    
    # Perform matmul on device
    C_tt = ttnn.matmul(A_tt, B_tt)
    
    # Move back to CPU
    C_tensor = ttnn.to_torch(C_tt)
    
    # Convert to list of int32
    C = C_tensor.reshape(-1).to(torch.int32).tolist()
    
    return C


def check_difficulty(hash_bytes: bytes, difficulty_bits: int) -> bool:
    """Check if hash meets difficulty requirement (leading zero bits)"""
    # Convert to integer (big-endian)
    hash_int = int.from_bytes(hash_bytes, 'big')
    # Check if top difficulty_bits are zero
    return hash_int < (1 << (256 - difficulty_bits))


def mine(seed_hex: str, difficulty: int, iterations: int, use_ttnn: bool = True):
    """Main mining function"""
    seed = bytes.fromhex(seed_hex)
    
    if len(seed) != 240:
        return {"success": False, "error": f"Invalid seed length: {len(seed)}, expected 240"}
    
    # Initialize TTNN device if available
    device = None
    if use_ttnn and HAS_TTNN:
        try:
            # Try with explicit dispatch mode
            os.environ.setdefault("TT_METAL_SLOW_DISPATCH_MODE", "1")
            device = ttnn.open_device(device_id=0, l1_small_size=16384)
            print("Using TTNN GPU acceleration", file=sys.stderr)
        except Exception as e:
            print(f"Failed to open TTNN device: {e}, falling back to CPU", file=sys.stderr)
            device = None
    
    start_time = time.time()
    hashes = 0
    best_difficulty = 0
    
    try:
        # Iterate through nonces
        max_iter = iterations if iterations > 0 else 2**32
        
        for nonce in range(max_iter):
            # Modify last 12 bytes of seed with nonce
            modified_seed = bytearray(seed)
            modified_seed[228:240] = struct.pack('<QI', nonce, nonce >> 32)[:12]
            modified_seed = bytes(modified_seed)
            
            # Generate matrices from seed
            A, B = seed_to_matrices(modified_seed)
            
            # Perform matrix multiplication
            if device is not None:
                C = matmul_ttnn(A, B, device)
            else:
                C = matmul_cpu(A, B)
            
            # Pack C as int32 little-endian
            c_bytes = b''.join(struct.pack('<i', x) for x in C)
            
            # Create solution: modified_seed (240) + C (4096)
            solution = modified_seed + c_bytes
            
            # Hash solution
            solution_hash = blake3_hash(solution)
            hashes += 1
            
            # Check difficulty
            if check_difficulty(solution_hash, difficulty):
                elapsed = time.time() - start_time
                hashrate = hashes / elapsed if elapsed > 0 else 0
                
                # Base58 encode solution
                solution_b58 = base58_encode(solution)
                
                result = {
                    "success": True,
                    "nonce": nonce,
                    "hash": solution_hash.hex(),
                    "solution_b58": solution_b58,
                    "hashes": hashes,
                    "elapsed_ms": int(elapsed * 1000),
                    "hashrate": hashrate
                }
                
                return result
            
            # Track best difficulty found
            hash_int = int.from_bytes(solution_hash, 'big')
            leading_zeros = 256 - hash_int.bit_length() if hash_int > 0 else 256
            if leading_zeros > best_difficulty:
                best_difficulty = leading_zeros
            
            # Progress update every 10000 hashes
            if hashes % 10000 == 0:
                elapsed = time.time() - start_time
                hashrate = hashes / elapsed if elapsed > 0 else 0
                print(f"Hashes: {hashes}, Rate: {hashrate:.1f} H/s, Best: {best_difficulty} bits", file=sys.stderr)
        
        # No solution found
        elapsed = time.time() - start_time
        return {
            "success": False,
            "error": "No solution found",
            "hashes": hashes,
            "elapsed_ms": int(elapsed * 1000),
            "best_difficulty": best_difficulty
        }
    
    finally:
        if device is not None:
            ttnn.close_device(device)


# Base58 alphabet (Bitcoin style)
BASE58_ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'


def base58_encode(data: bytes) -> str:
    """Encode bytes to base58 string"""
    # Count leading zeros
    leading_zeros = 0
    for b in data:
        if b == 0:
            leading_zeros += 1
        else:
            break
    
    # Convert to integer
    num = int.from_bytes(data, 'big')
    
    # Convert to base58
    result = []
    while num > 0:
        num, rem = divmod(num, 58)
        result.append(BASE58_ALPHABET[rem])
    
    # Add leading '1's for each leading zero byte
    return '1' * leading_zeros + ''.join(reversed(result))


def main():
    parser = argparse.ArgumentParser(description='HardHack TTNN Miner')
    parser.add_argument('--seed', required=True, help='Hex-encoded 240-byte seed')
    parser.add_argument('--difficulty', type=int, default=20, help='Difficulty in bits')
    parser.add_argument('--iterations', type=int, default=0, help='Max iterations (0 = unlimited)')
    parser.add_argument('--cpu', action='store_true', help='Force CPU mode')
    
    args = parser.parse_args()
    
    result = mine(
        seed_hex=args.seed,
        difficulty=args.difficulty,
        iterations=args.iterations,
        use_ttnn=not args.cpu
    )
    
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
