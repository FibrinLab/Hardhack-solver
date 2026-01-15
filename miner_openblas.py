#!/usr/bin/env python3
"""
HardHack Miner - OpenBLAS optimized with auto-submission
Uses NumPy (backed by OpenBLAS) for fast matrix multiplication
"""

import os
import sys
import time
import struct
import argparse
import urllib.request
import json

# Use OpenBLAS via NumPy
import numpy as np

# Import blake3
try:
    import blake3
    def blake3_hash(data: bytes) -> bytes:
        return blake3.blake3(data).digest()
    def blake3_xof(data: bytes, length: int) -> bytes:
        h = blake3.blake3(data)
        return h.digest(length=length)
except ImportError:
    print("Error: blake3 required. Install with: pip3 install blake3", file=sys.stderr)
    sys.exit(1)

# RPC endpoint
RPC_URL = "https://testnet-rpc.ama.one"


def fetch_seed() -> bytes:
    """Fetch seed from RPC"""
    req = urllib.request.Request(f"{RPC_URL}/api/upow/seed")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.read()


def fetch_difficulty() -> int:
    """Fetch current difficulty from RPC"""
    req = urllib.request.Request(f"{RPC_URL}/api/chain/stats")
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())
        return data.get("stats", {}).get("diff_bits", 20)


def submit_solution(solution: bytes) -> dict:
    """Submit solution to RPC for validation"""
    import base58
    sol_b58 = base58.b58encode(solution).decode()
    req = urllib.request.Request(f"{RPC_URL}/api/upow/validate/{sol_b58}")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def seed_to_matrices(seed: bytes):
    """
    Generate matrices A (16x50240) and B (50240x16) from seed using BLAKE3 XOF
    Per specs: A is u8, B is i8, C is i32
    Dimensions: 16 x 50240 x 16
    """
    # Generate matrix data using BLAKE3 XOF
    # Server uses: Blake3.finalize_xof(b, 16*50240 + 50240*16)
    a_size = 16 * 50240  # 802,840 bytes
    b_size = 50240 * 16  # 803,840 bytes
    matrix_size = a_size + b_size
    matrix_data = blake3_xof(seed, matrix_size)
    
    # Split into A and B
    a_data = matrix_data[:a_size]
    b_data = matrix_data[a_size:]
    
    # A is unsigned u8, B is signed i8
    A = np.frombuffer(a_data, dtype=np.uint8).reshape(16, 50240).astype(np.int32)
    B = np.frombuffer(b_data, dtype=np.int8).reshape(50240, 16).astype(np.int32)
    
    return A, B


def check_difficulty(hash_bytes: bytes, difficulty_bits: int) -> int:
    """Return number of leading zero bits in hash"""
    hash_int = int.from_bytes(hash_bytes, 'big')
    if hash_int == 0:
        return 256
    return 256 - hash_int.bit_length()


def build_solution(seed: bytes, C: np.ndarray) -> bytes:
    """
    Build solution bytes for submission
    Per specs: 240 bytes (seed) + 1024 bytes (C matrix) = 1264 bytes
    C is 16x16 i32 little-endian
    """
    C_bytes = C.astype('<i4').tobytes()  # Little-endian int32
    return seed + C_bytes


def mine_batch(seed: bytes, A: np.ndarray, B: np.ndarray, difficulty: int, 
               batch_size: int = 10000, max_iterations: int = 10000000):
    """
    Mine - compute C once, vary nonce in seed for different hashes
    """
    best_bits = 0
    best_solution = None
    total_hashes = 0
    start_time = time.time()
    
    # Compute C = A @ B once (16x50240 @ 50240x16 = 16x16)
    C = np.dot(A, B)
    C_bytes = C.astype('<i4').tobytes()
    
    nonce = 0
    while nonce < max_iterations:
        # Process batch
        for _ in range(batch_size):
            # Modify seed with nonce (inject into last 12 bytes - the random nonce portion)
            modified_seed = bytearray(seed)
            nonce_bytes = struct.pack('<Q', nonce)
            modified_seed[-12:-4] = nonce_bytes
            modified_seed = bytes(modified_seed)
            
            # Build solution: seed (240) + C (1024) = 1264 bytes
            solution = modified_seed + C_bytes
            solution_hash = blake3_hash(solution)
            
            leading_zeros = check_difficulty(solution_hash, difficulty)
            
            if leading_zeros > best_bits:
                best_bits = leading_zeros
                best_solution = solution
                
                if leading_zeros >= difficulty:
                    elapsed = time.time() - start_time
                    rate = total_hashes / elapsed if elapsed > 0 else 0
                    print(f"FOUND! Nonce: {nonce}, Bits: {leading_zeros}, Rate: {rate:.1f} H/s", file=sys.stderr)
                    return {
                        "success": True,
                        "nonce": nonce,
                        "leading_zeros": leading_zeros,
                        "solution": best_solution,
                        "hash_rate": rate,
                        "total_hashes": total_hashes
                    }
            
            nonce += 1
            total_hashes += 1
        
        # Progress update
        elapsed = time.time() - start_time
        rate = total_hashes / elapsed if elapsed > 0 else 0
        print(f"Hashes: {total_hashes}, Rate: {rate:.1f} H/s, Best: {best_bits} bits", file=sys.stderr)
    
    return {
        "success": False,
        "best_bits": best_bits,
        "total_hashes": total_hashes
    }


def main():
    parser = argparse.ArgumentParser(description="HardHack OpenBLAS Miner")
    parser.add_argument("--iterations", type=int, default=10000000, help="Max iterations")
    parser.add_argument("--batch-size", type=int, default=10000, help="Batch size for progress updates")
    parser.add_argument("--loop", action="store_true", help="Run continuously")
    args = parser.parse_args()
    
    # Check OpenBLAS
    print(f"NumPy config: {np.__config__.show()}", file=sys.stderr)
    
    try:
        import base58
    except ImportError:
        print("Installing base58...", file=sys.stderr)
        os.system("pip3 install base58")
        import base58
    
    while True:
        try:
            # Fetch seed and difficulty
            print("Fetching seed...", file=sys.stderr)
            seed = fetch_seed()
            print(f"Seed length: {len(seed)}", file=sys.stderr)
            
            difficulty = fetch_difficulty()
            print(f"Difficulty: {difficulty} bits", file=sys.stderr)
            
            # Generate matrices
            print("Generating matrices...", file=sys.stderr)
            A, B = seed_to_matrices(seed)
            print(f"Matrix A: {A.shape}, Matrix B: {B.shape}", file=sys.stderr)
            
            # Mine
            print("Mining...", file=sys.stderr)
            result = mine_batch(seed, A, B, difficulty, args.batch_size, args.iterations)
            
            if result["success"]:
                # Submit solution
                print("Submitting solution...", file=sys.stderr)
                validation = submit_solution(result["solution"])
                print(f"Validation result: {validation}", file=sys.stderr)
                
                if validation.get("valid"):
                    print("SUCCESS! Solution accepted!", file=sys.stderr)
                else:
                    print(f"Solution rejected: {validation}", file=sys.stderr)
            
            if not args.loop:
                break
                
        except KeyboardInterrupt:
            print("\nStopped by user", file=sys.stderr)
            break
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            if not args.loop:
                break
            time.sleep(5)
    
    print(json.dumps(result if 'result' in dir() else {"error": "No result"}))


if __name__ == "__main__":
    main()
