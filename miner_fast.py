#!/usr/bin/env python3
"""
HardHack GPU Miner - TTNN accelerated, correct math, maximum speed
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
import blake3

def blake3_hash(data: bytes) -> bytes:
    return blake3.blake3(data).digest()

def blake3_xof(data: bytes, length: int) -> bytes:
    return blake3.blake3(data).digest(length=length)

# TTNN is REQUIRED
import ttnn
import torch

RPC_URL = "https://testnet-rpc.ama.one"
M, K, N = 16, 50240, 16
XOF_SIZE = M * K + K * N


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


class TTNNMiner:
    def __init__(self, device_id=0):
        print("Initializing TTNN GPU...", file=sys.stderr)
        self.device = ttnn.open_device(device_id=device_id)
        print(f"TTNN GPU ready on device {device_id}", file=sys.stderr)
        
        # Pre-allocate tensors on device for batched operations
        self.batch_size = 64  # Process multiple nonces at once
    
    def matmul_batch(self, A_batch: np.ndarray, B_batch: np.ndarray) -> np.ndarray:
        """
        Batched GPU matmul: (batch, 16, 50240) @ (batch, 50240, 16) = (batch, 16, 16)
        """
        batch = A_batch.shape[0]
        
        # Flatten batch for single large matmul
        # Stack all A matrices vertically: (batch*16, 50240)
        A_stacked = A_batch.reshape(batch * M, K).astype(np.float32)
        # B is same for conceptual batching, but we need block diagonal approach
        # For now, process individually but keep tensors on GPU
        
        results = []
        for i in range(batch):
            A_t = torch.from_numpy(A_batch[i].astype(np.float32))
            B_t = torch.from_numpy(B_batch[i].astype(np.float32))
            
            A_tt = ttnn.from_torch(A_t, device=self.device, layout=ttnn.TILE_LAYOUT)
            B_tt = ttnn.from_torch(B_t, device=self.device, layout=ttnn.TILE_LAYOUT)
            
            C_tt = ttnn.matmul(A_tt, B_tt)
            C_t = ttnn.to_torch(C_tt)
            results.append(C_t.numpy().astype(np.int32))
        
        return np.array(results)
    
    def mine(self, seed: bytes, difficulty: int, max_iterations: int = 100000000):
        from concurrent.futures import ThreadPoolExecutor
        import threading
        
        best_bits = 0
        best_solution = None
        total_hashes = 0
        start_time = time.time()
        lock = threading.Lock()
        
        def generate_xof_batch(seed_base, start_nonce, count):
            """Generate XOF data for a batch of nonces in parallel"""
            results = []
            for i in range(count):
                nonce = start_nonce + i
                seed_arr = bytearray(seed_base)
                struct.pack_into('<Q', seed_arr, 228, nonce)
                current_seed = bytes(seed_arr)
                xof_data = blake3_xof(current_seed, XOF_SIZE)
                A = np.frombuffer(xof_data[:M*K], dtype=np.uint8).reshape(M, K)
                B = np.frombuffer(xof_data[M*K:], dtype=np.int8).reshape(K, N)
                results.append((current_seed, A, B))
            return results
        
        nonce = 0
        batch_size = self.batch_size
        
        while nonce < max_iterations:
            # Generate batch of XOF data (CPU bound, could parallelize)
            batch_data = generate_xof_batch(seed, nonce, batch_size)
            
            # Stack for batched GPU processing
            A_batch = np.array([d[1] for d in batch_data])
            B_batch = np.array([d[2] for d in batch_data])
            
            # Batched GPU matmul
            C_batch = self.matmul_batch(A_batch, B_batch)
            
            # Check all results
            for i, (current_seed, _, _) in enumerate(batch_data):
                C = C_batch[i]
                solution = current_seed + C.astype('<i4').tobytes()
                solution_hash = blake3_hash(solution)
                leading_zeros = check_difficulty(solution_hash, difficulty)
                
                total_hashes += 1
                
                if leading_zeros > best_bits:
                    best_bits = leading_zeros
                    best_solution = solution
                    elapsed = time.time() - start_time
                    rate = total_hashes / elapsed if elapsed > 0 else 0
                    print(f"NEW BEST: {leading_zeros} bits @ nonce {nonce+i}, Rate: {rate:.1f} H/s", file=sys.stderr)
                    
                    if leading_zeros >= difficulty:
                        print(f"SOLUTION FOUND!", file=sys.stderr)
                        return {"success": True, "solution": best_solution, "rate": rate, "nonce": nonce+i, "bits": leading_zeros}
            
            nonce += batch_size
            
            if total_hashes % 1000 == 0:
                elapsed = time.time() - start_time
                rate = total_hashes / elapsed if elapsed > 0 else 0
                print(f"Hashes: {total_hashes}, Rate: {rate:.1f} H/s, Best: {best_bits} bits", file=sys.stderr)
        
        return {"success": False, "best_bits": best_bits, "total_hashes": total_hashes}
    
    def close(self):
        ttnn.close_device(self.device)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--loop", action="store_true")
    parser.add_argument("--iterations", type=int, default=100000000)
    args = parser.parse_args()
    
    # Install base58 if needed
    try:
        import base58
    except:
        os.system("pip3 install base58")
        import base58
    
    # Initialize GPU miner
    miner = TTNNMiner(device_id=0)
    
    try:
        while True:
            seed = fetch_seed()
            difficulty = fetch_difficulty()
            print(f"Seed: {len(seed)} bytes, Difficulty: {difficulty} bits", file=sys.stderr)
            
            result = miner.mine(seed, difficulty, args.iterations)
            
            if result["success"]:
                print("Submitting solution...", file=sys.stderr)
                val = submit_solution(result["solution"])
                print(f"Validation: {val}", file=sys.stderr)
            
            if not args.loop:
                break
    except KeyboardInterrupt:
        print("\nStopped", file=sys.stderr)
    finally:
        miner.close()


if __name__ == "__main__":
    main()
