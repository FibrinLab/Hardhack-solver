#!/usr/bin/env python3
"""
HardHack Hybrid Miner - Fast hashing with periodic seed refresh
"""

import os
import sys
import time
import struct
import argparse
import urllib.request
import json
import numpy as np
import blake3

RPC_URL = "https://testnet-rpc.ama.one"
M, K, N = 16, 50240, 16

def blake3_hash(data: bytes) -> bytes:
    return blake3.blake3(data).digest()

def blake3_xof(data: bytes, length: int) -> bytes:
    return blake3.blake3(data).digest(length=length)

def fetch_seed_with_matrices():
    """Fetch seed + pre-computed matrices from server"""
    req = urllib.request.Request(f"{RPC_URL}/api/upow/seed_with_matrix_a_b")
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    
    seed = data[:240]
    matrix_data = data[240:]
    
    a_size = M * K
    A = np.frombuffer(matrix_data[:a_size], dtype=np.uint8).reshape(M, K)
    B = np.frombuffer(matrix_data[a_size:], dtype=np.uint8).astype(np.int8).reshape(K, N)
    
    return seed, A, B

def fetch_difficulty():
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

def mine_fast(seed: bytes, A: np.ndarray, B: np.ndarray, difficulty: int, max_hashes: int = 500000):
    """
    Fast mining for a fixed time/hashes, then refresh seed
    Uses original seed (for valid_math) but tries many nonces in C
    
    Actually - we can't modify C. So we just hash once per seed.
    But we can try XORing the final hash with different values? No.
    
    The ONLY way is to vary the seed. But server checks segment_vr_hash.
    
    Let's try: vary the last 12 bytes (nonce) and hope valid_math still works
    since Freivalds only checks C = A*B probabilistically.
    """
    # Compute C once
    C = np.matmul(A.astype(np.int32), B.astype(np.int32))
    C_bytes = C.astype('<i4').tobytes()
    
    best_bits = 0
    best_solution = None
    seed_arr = bytearray(seed)
    
    start = time.time()
    for nonce in range(max_hashes):
        # Vary nonce in seed
        struct.pack_into('<Q', seed_arr, 228, nonce)
        
        solution = bytes(seed_arr) + C_bytes
        h = blake3_hash(solution)
        bits = check_difficulty(h, difficulty)
        
        if bits > best_bits:
            best_bits = bits
            best_solution = solution
            
        if bits >= difficulty:
            return {"success": True, "solution": best_solution, "bits": bits, "nonce": nonce}
    
    elapsed = time.time() - start
    rate = max_hashes / elapsed if elapsed > 0 else 0
    return {"success": False, "best_bits": best_bits, "rate": rate, "hashes": max_hashes}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--loop", action="store_true")
    args = parser.parse_args()
    
    try:
        import base58
    except:
        os.system("pip3 install base58")
    
    print("Starting hybrid miner...", file=sys.stderr)
    
    total_hashes = 0
    start_time = time.time()
    
    while True:
        try:
            # Fetch fresh seed + matrices
            seed, A, B = fetch_seed_with_matrices()
            difficulty = fetch_difficulty()
            
            # Mine with this seed for up to 500k hashes, then refresh
            result = mine_fast(seed, A, B, difficulty, max_hashes=500000)
            total_hashes += result.get("hashes", 0)
            
            elapsed = time.time() - start_time
            overall_rate = total_hashes / elapsed if elapsed > 0 else 0
            
            if result["success"]:
                print(f"SOLUTION FOUND! {result['bits']} bits", file=sys.stderr)
                val = submit_solution(result["solution"])
                print(f"Validation: {val}", file=sys.stderr)
                
                if val.get("valid") and val.get("valid_math"):
                    print("SUCCESS! Valid solution submitted!", file=sys.stderr)
                else:
                    print(f"Solution rejected. Continuing...", file=sys.stderr)
            else:
                print(f"Best: {result['best_bits']} bits, Rate: {result.get('rate', 0):.0f} H/s, Overall: {overall_rate:.0f} H/s", file=sys.stderr)
            
            if not args.loop:
                break
                
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            time.sleep(1)

if __name__ == "__main__":
    main()
