#!/usr/bin/env python3
"""
HardHack Fast Miner - TTNN GPU accelerated with correct math
"""

import os
import sys
import time
import struct
import argparse
import urllib.request
import json

import numpy as np

# Import blake3
try:
    import blake3
    def blake3_hash(data: bytes) -> bytes:
        return blake3.blake3(data).digest()
    def blake3_xof(data: bytes, length: int) -> bytes:
        return blake3.blake3(data).digest(length=length)
except ImportError:
    print("Error: blake3 required", file=sys.stderr)
    sys.exit(1)

# Try TTNN
try:
    import ttnn
    import torch
    HAS_TTNN = True
except ImportError:
    HAS_TTNN = False
    print("TTNN not available, using CPU", file=sys.stderr)

RPC_URL = "https://testnet-rpc.ama.one"
M, K, N = 16, 50240, 16


def fetch_seed() -> bytes:
    req = urllib.request.Request(f"{RPC_URL}/api/upow/seed")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.read()


def fetch_difficulty() -> int:
    req = urllib.request.Request(f"{RPC_URL}/api/chain/stats")
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())
        return data.get("stats", {}).get("diff_bits", 20)


def submit_solution(solution: bytes) -> dict:
    import base58
    sol_b58 = base58.b58encode(solution).decode()
    req = urllib.request.Request(f"{RPC_URL}/api/upow/validate/{sol_b58}")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def check_difficulty(hash_bytes: bytes, difficulty_bits: int) -> int:
    hash_int = int.from_bytes(hash_bytes, 'big')
    if hash_int == 0:
        return 256
    return 256 - hash_int.bit_length()


def matmul_ttnn(A: np.ndarray, B: np.ndarray, device) -> np.ndarray:
    """TTNN GPU matmul for 16x50240 @ 50240x16"""
    A_t = torch.from_numpy(A.astype(np.float32))
    B_t = torch.from_numpy(B.astype(np.float32))
    
    A_tt = ttnn.from_torch(A_t, device=device, layout=ttnn.TILE_LAYOUT)
    B_tt = ttnn.from_torch(B_t, device=device, layout=ttnn.TILE_LAYOUT)
    
    C_tt = ttnn.matmul(A_tt, B_tt)
    C_t = ttnn.to_torch(C_tt)
    
    return C_t.numpy().astype(np.int32)


def mine(seed: bytes, difficulty: int, device, max_iterations: int = 10000000):
    best_bits = 0
    best_solution = None
    total_hashes = 0
    start_time = time.time()
    
    xof_size = M * K + K * N
    seed_arr = bytearray(seed)
    
    for nonce in range(max_iterations):
        # Update nonce
        struct.pack_into('<Q', seed_arr, 228, nonce)
        current_seed = bytes(seed_arr)
        
        # Generate matrices via XOF
        xof_data = blake3_xof(current_seed, xof_size)
        
        A = np.frombuffer(xof_data[:M*K], dtype=np.uint8).reshape(M, K).astype(np.int32)
        B = np.frombuffer(xof_data[M*K:], dtype=np.int8).reshape(K, N).astype(np.int32)
        
        # Matmul - use TTNN if available
        if device is not None:
            C = matmul_ttnn(A, B, device)
        else:
            C = np.dot(A, B)
        
        # Build and hash solution
        solution = current_seed + C.astype('<i4').tobytes()
        solution_hash = blake3_hash(solution)
        leading_zeros = check_difficulty(solution_hash, difficulty)
        
        if leading_zeros > best_bits:
            best_bits = leading_zeros
            best_solution = solution
            print(f"Best: {leading_zeros} bits @ nonce {nonce}", file=sys.stderr)
            
            if leading_zeros >= difficulty:
                elapsed = time.time() - start_time
                rate = total_hashes / elapsed if elapsed > 0 else 0
                return {"success": True, "solution": best_solution, "rate": rate, "nonce": nonce}
        
        total_hashes += 1
        if total_hashes % 100 == 0:
            elapsed = time.time() - start_time
            rate = total_hashes / elapsed if elapsed > 0 else 0
            print(f"Hashes: {total_hashes}, Rate: {rate:.1f} H/s, Best: {best_bits}", file=sys.stderr)
    
    return {"success": False, "best_bits": best_bits}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--loop", action="store_true")
    parser.add_argument("--iterations", type=int, default=10000000)
    args = parser.parse_args()
    
    # Init TTNN
    device = None
    if HAS_TTNN:
        try:
            device = ttnn.open_device(device_id=0)
            print("Using TTNN GPU", file=sys.stderr)
        except Exception as e:
            print(f"TTNN init failed: {e}", file=sys.stderr)
    
    try:
        import base58
    except:
        os.system("pip3 install base58")
        import base58
    
    while True:
        try:
            seed = fetch_seed()
            difficulty = fetch_difficulty()
            print(f"Seed: {len(seed)} bytes, Difficulty: {difficulty}", file=sys.stderr)
            
            result = mine(seed, difficulty, device, args.iterations)
            
            if result["success"]:
                print("Submitting...", file=sys.stderr)
                val = submit_solution(result["solution"])
                print(f"Result: {val}", file=sys.stderr)
            
            if not args.loop:
                break
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            time.sleep(5)
    
    if device:
        ttnn.close_device(device)


if __name__ == "__main__":
    main()
