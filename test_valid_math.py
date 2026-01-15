#!/usr/bin/env python3
"""
Test what seed modifications preserve valid_math
"""

import sys
import struct
import urllib.request
import json
import numpy as np

try:
    import ttnn
    import torch
except:
    print("ERROR: ttnn not available. Install it first.", file=sys.stderr)
    sys.exit(1)

try:
    import base58
except:
    import os
    os.system("pip3 install base58")
    import base58

RPC_URL = "https://testnet-rpc.ama.one"
M, K, N = 16, 50240, 16

def fetch_seed_with_matrices():
    req = urllib.request.Request(f"{RPC_URL}/api/upow/seed_with_matrix_a_b")
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    
    seed = data[:240]
    matrix_data = data[240:]
    
    a_size = M * K
    A = np.frombuffer(matrix_data[:a_size], dtype=np.uint8).reshape(M, K)
    B = np.frombuffer(matrix_data[a_size:], dtype=np.uint8).astype(np.int8).reshape(K, N)
    
    return seed, A, B

def submit_solution(solution: bytes) -> dict:
    sol_b58 = base58.b58encode(solution).decode()
    req = urllib.request.Request(f"{RPC_URL}/api/upow/validate/{sol_b58}")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

def main():
    print("Initializing TTNN GPU...", file=sys.stderr)
    device = ttnn.open_device(device_id=0)
    print("GPU ready", file=sys.stderr)
    
    # Fetch seed + matrices
    print("\nFetching seed and matrices...", file=sys.stderr)
    seed, A, B = fetch_seed_with_matrices()
    print(f"Seed: {seed[:20].hex()}...", file=sys.stderr)
    
    # Compute C on GPU
    print("Computing C on GPU...", file=sys.stderr)
    A_t = torch.from_numpy(A.astype(np.float32)).unsqueeze(0)
    B_t = torch.from_numpy(B.astype(np.float32)).unsqueeze(0)
    A_tt = ttnn.from_torch(A_t, device=device, layout=ttnn.TILE_LAYOUT)
    B_tt = ttnn.from_torch(B_t, device=device, layout=ttnn.TILE_LAYOUT)
    C_tt = ttnn.matmul(A_tt, B_tt)
    C_t = ttnn.to_torch(C_tt)
    C = C_t.squeeze(0).numpy().astype(np.int32)
    C_bytes = C.astype('<i4').tobytes()
    print(f"C computed. Shape: {C.shape}", file=sys.stderr)
    
    # Test 1: Original seed
    print("\n=== TEST 1: Original seed ===")
    solution = seed + C_bytes
    result = submit_solution(solution)
    print(f"valid_math: {result.get('valid_math')}, valid: {result.get('valid')}")
    
    # Test 2: Modify last 8 bytes (nonce low)
    print("\n=== TEST 2: Modify nonce (bytes 228-235) ===")
    seed_mod = bytearray(seed)
    struct.pack_into('<Q', seed_mod, 228, 12345)
    solution = bytes(seed_mod) + C_bytes
    result = submit_solution(solution)
    print(f"valid_math: {result.get('valid_math')}, valid: {result.get('valid')}")
    
    # Test 3: Modify last 4 bytes (nonce high)
    print("\n=== TEST 3: Modify nonce (bytes 236-239) ===")
    seed_mod = bytearray(seed)
    struct.pack_into('<I', seed_mod, 236, 99999)
    solution = bytes(seed_mod) + C_bytes
    result = submit_solution(solution)
    print(f"valid_math: {result.get('valid_math')}, valid: {result.get('valid')}")
    
    # Test 4: Modify last 1 byte only
    print("\n=== TEST 4: Modify last byte only ===")
    seed_mod = bytearray(seed)
    seed_mod[239] = (seed_mod[239] + 1) % 256
    solution = bytes(seed_mod) + C_bytes
    result = submit_solution(solution)
    print(f"valid_math: {result.get('valid_math')}, valid: {result.get('valid')}")
    
    # Test 5: Modify epoch (bytes 0-3)
    print("\n=== TEST 5: Modify epoch (bytes 0-3) ===")
    seed_mod = bytearray(seed)
    struct.pack_into('<I', seed_mod, 0, 99999)
    solution = bytes(seed_mod) + C_bytes
    result = submit_solution(solution)
    print(f"valid_math: {result.get('valid_math')}, valid: {result.get('valid')}")
    
    # Test 6: Modify segment_vr_hash (bytes 4-35)
    print("\n=== TEST 6: Modify segment_vr_hash (byte 4) ===")
    seed_mod = bytearray(seed)
    seed_mod[4] = (seed_mod[4] + 1) % 256
    solution = bytes(seed_mod) + C_bytes
    result = submit_solution(solution)
    print(f"valid_math: {result.get('valid_math')}, valid: {result.get('valid')}")
    
    # Test 7: Modify pk (bytes 36-83)
    print("\n=== TEST 7: Modify pk (byte 36) ===")
    seed_mod = bytearray(seed)
    seed_mod[36] = (seed_mod[36] + 1) % 256
    solution = bytes(seed_mod) + C_bytes
    result = submit_solution(solution)
    print(f"valid_math: {result.get('valid_math')}, valid: {result.get('valid')}")
    
    print("\n=== CONCLUSION ===")
    print("If ANY test shows valid_math=true (except test 1),")
    print("we can modify that part of the seed for high H/s!")
    
    ttnn.close_device(device)

if __name__ == "__main__":
    main()
