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


# Global for multiprocessing (can't pickle local functions)
_M, _K, _N = 16, 50240, 16
_XOF_SIZE = _M * _K + _K * _N
_BASE_SEED = None
_DIFFICULTY = None

def _process_nonce(nonce):
    """Process single nonce - must be global for multiprocessing"""
    local_seed = bytearray(_BASE_SEED)
    struct.pack_into('<Q', local_seed, 228, nonce)
    local_seed = bytes(local_seed)
    
    # XOF + matrices
    xof_data = blake3_xof(local_seed, _XOF_SIZE)
    A = np.frombuffer(xof_data[:_M*_K], dtype=np.uint8).reshape(_M, _K).astype(np.int32)
    B = np.frombuffer(xof_data[_M*_K:], dtype=np.int8).reshape(_K, _N).astype(np.int32)
    
    # OpenBLAS matmul
    C = np.dot(A, B)
    
    # Solution
    solution = local_seed + C.astype('<i4').tobytes()
    h = blake3_hash(solution)
    bits = check_difficulty(h, _DIFFICULTY)
    
    return nonce, bits, solution


def build_solution(seed: bytes, C: np.ndarray) -> bytes:
    """
    Build solution bytes for submission
    Per specs: 240 bytes (seed) + 1024 bytes (C matrix) = 1264 bytes
    C is 16x16 i32 little-endian
    """
    C_bytes = C.astype('<i4').tobytes()  # Little-endian int32
    return seed + C_bytes


def test_validation(seed: bytes):
    """Test if our solution format is correct by validating immediately"""
    import base58
    
    print(f"Testing with seed length: {len(seed)}", file=sys.stderr)
    
    # Generate matrices
    A, B = seed_to_matrices(seed)
    print(f"A shape: {A.shape}, B shape: {B.shape}", file=sys.stderr)
    print(f"A dtype: {A.dtype}, B dtype: {B.dtype}", file=sys.stderr)
    
    # Compute C
    C = np.dot(A, B)
    print(f"C shape: {C.shape}, C dtype: {C.dtype}", file=sys.stderr)
    print(f"C[0,0]: {C[0,0]}, C[0,1]: {C[0,1]}", file=sys.stderr)
    
    # Build solution
    C_bytes = C.astype('<i4').tobytes()
    solution = seed + C_bytes
    print(f"Solution length: {len(solution)} (expected 1264)", file=sys.stderr)
    
    # Submit for validation
    sol_b58 = base58.b58encode(solution).decode()
    print(f"Submitting to validate...", file=sys.stderr)
    
    req = urllib.request.Request(f"{RPC_URL}/api/upow/validate/{sol_b58}")
    with urllib.request.urlopen(req, timeout=10) as resp:
        result = json.loads(resp.read())
    
    print(f"Validation result: {result}", file=sys.stderr)
    return result


def mine_correct(seed: bytes, difficulty: int, max_iterations: int = 10000000):
    """
    Fast mining with OpenBLAS-accelerated matmul.
    Uses multiprocessing for parallel hashing.
    """
    global _BASE_SEED, _DIFFICULTY
    from concurrent.futures import ProcessPoolExecutor, as_completed
    import multiprocessing
    
    # Set globals for worker processes
    _BASE_SEED = seed
    _DIFFICULTY = difficulty
    
    best_bits = 0
    best_solution = None
    total_hashes = 0
    start_time = time.time()
    
    # Validate first one to confirm valid_math
    import base58
    nonce, bits, solution = _process_nonce(0)
    total_hashes += 1
    best_bits = bits
    best_solution = solution
    
    sol_b58 = base58.b58encode(solution).decode()
    req = urllib.request.Request(f"{RPC_URL}/api/upow/validate/{sol_b58}")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            val_result = json.loads(resp.read())
        print(f"Validation: {val_result}", file=sys.stderr)
    except Exception as e:
        print(f"Validation error: {e}", file=sys.stderr)
    
    # Parallel mining
    num_workers = multiprocessing.cpu_count()
    batch_size = num_workers * 10  # Smaller batch for more frequent updates
    nonce = 1
    last_report = start_time
    
    while nonce < max_iterations:
        with ProcessPoolExecutor(max_workers=num_workers) as executor:
            futures = {executor.submit(_process_nonce, n): n for n in range(nonce, min(nonce + batch_size, max_iterations))}
            
            for future in as_completed(futures):
                n, bits, sol = future.result()
                total_hashes += 1
                
                if bits > best_bits:
                    best_bits = bits
                    best_solution = sol
                    elapsed = time.time() - start_time
                    rate = total_hashes / elapsed if elapsed > 0 else 0
                    print(f"NEW BEST: {bits} bits @ nonce {n}, Rate: {rate:.1f} H/s", file=sys.stderr)
                    
                    if bits >= difficulty:
                        print(f"SOLUTION FOUND!", file=sys.stderr)
                        return {
                            "success": True,
                            "nonce": n,
                            "leading_zeros": bits,
                            "solution": best_solution,
                            "hash_rate": rate,
                            "total_hashes": total_hashes
                        }
        
        nonce += batch_size
        
        # Report every second
        now = time.time()
        if now - last_report >= 1.0:
            elapsed = now - start_time
            rate = total_hashes / elapsed if elapsed > 0 else 0
            print(f"Hashes: {total_hashes}, Rate: {rate:.1f} H/s, Best: {best_bits} bits", file=sys.stderr)
            last_report = now
    
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
            
            # First test validation with original seed
            print("Testing validation...", file=sys.stderr)
            test_validation(seed)
            
            # Mine (matrices generated per-nonce inside)
            print("Mining...", file=sys.stderr)
            result = mine_correct(seed, difficulty, args.iterations)
            
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
