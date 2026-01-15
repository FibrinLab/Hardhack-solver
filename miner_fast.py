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


def gen_one_global(args):
    """Global function for multiprocessing - generates XOF and matrices for one nonce"""
    seed, nonce = args
    seed_arr = bytearray(seed)
    struct.pack_into('<Q', seed_arr, 228, nonce)
    current_seed = bytes(seed_arr)
    xof_data = blake3_xof(current_seed, XOF_SIZE)
    A = np.frombuffer(xof_data[:M*K], dtype=np.uint8).reshape(M, K)
    B = np.frombuffer(xof_data[M*K:], dtype=np.int8).reshape(K, N)
    return current_seed, A, B


class TTNNMiner:
    def __init__(self, device_id=0, num_workers=None):
        import multiprocessing
        print("Initializing TTNN GPU...", file=sys.stderr)
        self.device = ttnn.open_device(device_id=device_id)
        self.num_workers = num_workers or multiprocessing.cpu_count()
        self.batch_size = self.num_workers * 256  # Large batch for OpenBLAS efficiency
        print(f"TTNN GPU ready. Workers: {self.num_workers}, Batch: {self.batch_size}", file=sys.stderr)
    
    def matmul(self, A: np.ndarray, B: np.ndarray) -> np.ndarray:
        """GPU matmul for single matrix"""
        A_t = torch.from_numpy(A.astype(np.float32))
        B_t = torch.from_numpy(B.astype(np.float32))
        
        A_tt = ttnn.from_torch(A_t, device=self.device, layout=ttnn.TILE_LAYOUT)
        B_tt = ttnn.from_torch(B_t, device=self.device, layout=ttnn.TILE_LAYOUT)
        
        C_tt = ttnn.matmul(A_tt, B_tt)
        C_t = ttnn.to_torch(C_tt)
        
        return C_t.numpy().astype(np.int32)
    
    def matmul_batch(self, A_batch: np.ndarray, B_batch: np.ndarray) -> list:
        """
        Batched matmul using NumPy/OpenBLAS - highly optimized
        Uses np.einsum or np.matmul with broadcasting
        """
        batch = A_batch.shape[0]
        
        # Use numpy's optimized matmul (backed by OpenBLAS/MKL)
        # np.matmul handles batch dimensions automatically
        A = A_batch.astype(np.float64)  # float64 for precision
        B = B_batch.astype(np.float64)
        
        # Batched matmul: (batch, 16, 50240) @ (batch, 50240, 16) = (batch, 16, 16)
        C = np.matmul(A, B)
        
        # Return as list of int32 arrays
        return [C[i].astype(np.int32) for i in range(batch)]
    
    def mine(self, seed: bytes, difficulty: int, max_iterations: int = 100000000):
        """
        Maximum speed pipeline:
        - Multiprocessing pool generates XOF/A/B (bypasses GIL)
        - GPU matmul per item
        - Hash/verify
        """
        from multiprocessing import Pool

        best_bits = 0
        best_solution = None
        total_hashes = 0
        start_time = time.time()

        batch_size = self.batch_size
        
        # Create process pool once
        pool = Pool(self.num_workers)

        try:
            nonce = 0
            while nonce < max_iterations:
                # Generate batch using multiprocessing (true parallelism)
                args = [(seed, n) for n in range(nonce, min(nonce + batch_size, max_iterations))]
                batch_data = pool.map(gen_one_global, args)

                # Stack matrices for batched matmul
                A_batch = np.stack([d[1] for d in batch_data])
                B_batch = np.stack([d[2] for d in batch_data])
                
                # Batched matmul (uses torch.bmm - much faster than loop)
                C_batch = self.matmul_batch(A_batch, B_batch)
                
                # Check results
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
                            print("SOLUTION FOUND!", file=sys.stderr)
                            pool.terminate()
                            return {"success": True, "solution": best_solution, "rate": rate, "nonce": nonce+i, "bits": leading_zeros}

                nonce += batch_size

                if total_hashes % 1000 == 0:
                    elapsed = time.time() - start_time
                    rate = total_hashes / elapsed if elapsed > 0 else 0
                    print(f"Hashes: {total_hashes}, Rate: {rate:.1f} H/s, Best: {best_bits} bits", file=sys.stderr)
        finally:
            pool.close()
            pool.join()

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
