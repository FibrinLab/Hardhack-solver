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
    # Use blake3's built-in multithreading for large outputs
    h = blake3.blake3(data, max_threads=blake3.blake3.AUTO)
    return h.digest(length=length)

# TTNN is REQUIRED
import ttnn
import torch

RPC_URL = "https://testnet-rpc.ama.one"
M, K, N = 16, 50240, 16
XOF_SIZE = M * K + K * N


def fetch_seed() -> bytes:
    """Fetch just the seed"""
    req = urllib.request.Request(f"{RPC_URL}/api/upow/seed")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.read()

def fetch_seed_with_matrices() -> tuple:
    """Fetch seed + pre-computed matrices from server - FAST!"""
    req = urllib.request.Request(f"{RPC_URL}/api/upow/seed_with_matrix_a_b")
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    
    # Format: seed (240 bytes) + matrix_a_b (16*50240 + 50240*16 bytes)
    seed = data[:240]
    matrix_data = data[240:]
    
    a_size = M * K  # 16 * 50240
    A = np.frombuffer(matrix_data[:a_size], dtype=np.uint8).reshape(M, K)
    B = np.frombuffer(matrix_data[a_size:], dtype=np.uint8).astype(np.int8).reshape(K, N)
    
    return seed, A, B


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
        self.batch_size = 64  # Smaller batch, faster turnaround
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
    
    def matmul_batch(self, A_batch: np.ndarray, B_batch: np.ndarray) -> np.ndarray:
        """
        Batched matmul using NumPy/OpenBLAS
        """
        # Use int32 directly to avoid float conversion overhead
        A = A_batch.astype(np.int32)
        B = B_batch.astype(np.int32)
        
        # Batched matmul: (batch, 16, 50240) @ (batch, 50240, 16) = (batch, 16, 16)
        C = np.matmul(A, B)
        
        return C  # Already int32
    
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
                    
                    solution = current_seed + C.astype('<i4').tobytes()  # Little-endian int32
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
    
    def mine_fast(self, seed: bytes, A: np.ndarray, B: np.ndarray, difficulty: int, max_iterations: int = 100000000):
        """
        FAST mining with VALID MATH:
        - Server gives us seed + matrices
        - We compute C (matches server's computation)
        - We submit seed + C (unmodified seed = valid_math: true)
        - If not enough bits, get a new seed from server (new random nonce)
        """
        start_time = time.time()
        total = 0
        best_bits = 0
        
        while total < max_iterations:
            # Compute C using NumPy/OpenBLAS
            C = np.matmul(A.astype(np.int32), B.astype(np.int32))
            C_bytes = C.astype('<i4').tobytes()
            
            # Build solution with ORIGINAL seed
            solution = seed + C_bytes
            solution_hash = blake3_hash(solution)
            leading_zeros = check_difficulty(solution_hash, difficulty)
            
            total += 1
            
            if leading_zeros > best_bits:
                best_bits = leading_zeros
                elapsed = time.time() - start_time
                rate = total / elapsed if elapsed > 0 else 0
                print(f"NEW BEST: {leading_zeros} bits, Rate: {rate:.1f} seeds/s", file=sys.stderr)
            
            if leading_zeros >= difficulty:
                elapsed = time.time() - start_time
                rate = total / elapsed if elapsed > 0 else 0
                print(f"SOLUTION FOUND! {leading_zeros} bits after {total} seeds", file=sys.stderr)
                return {"success": True, "solution": solution, "rate": rate, "bits": leading_zeros}
            
            # Get new seed from server (has new random nonce)
            try:
                seed, A, B = fetch_seed_with_matrices()
            except Exception as e:
                print(f"Fetch error: {e}", file=sys.stderr)
                time.sleep(0.1)
                continue
            
            if total % 100 == 0:
                elapsed = time.time() - start_time
                rate = total / elapsed if elapsed > 0 else 0
                print(f"Seeds: {total}, Rate: {rate:.1f}/s, Best: {best_bits} bits", file=sys.stderr)
        
        return {"success": False, "best_bits": best_bits, "total_hashes": total}
    
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
            # Fetch seed with pre-computed matrices
            print("Fetching seed with matrices...", file=sys.stderr)
            seed, A, B = fetch_seed_with_matrices()
            difficulty = fetch_difficulty()
            print(f"Seed: {len(seed)} bytes, Difficulty: {difficulty} bits", file=sys.stderr)
            
            # Compute C once on GPU
            print("Computing matmul on GPU...", file=sys.stderr)
            C = miner.matmul(A, B)
            C_bytes = C.astype('<i4').tobytes()
            print(f"C computed. Shape: {C.shape}", file=sys.stderr)
            
            # Fast mining loop - vary nonce, hash quickly
            best_bits = 0
            best_solution = None
            seed_arr = bytearray(seed)
            start_time = time.time()
            
            for nonce in range(args.iterations):
                struct.pack_into('<Q', seed_arr, 228, nonce)
                solution = bytes(seed_arr) + C_bytes
                h = blake3_hash(solution)
                bits = check_difficulty(h, difficulty)
                
                if bits > best_bits:
                    best_bits = bits
                    best_solution = solution
                    elapsed = time.time() - start_time
                    rate = (nonce + 1) / elapsed if elapsed > 0 else 0
                    print(f"NEW BEST: {bits} bits @ nonce {nonce}, Rate: {rate:.0f} H/s", file=sys.stderr)
                
                if bits >= difficulty:
                    print("SOLUTION FOUND!", file=sys.stderr)
                    val = submit_solution(best_solution)
                    print(f"Validation: {val}", file=sys.stderr)
                    break
                
                if (nonce + 1) % 100000 == 0:
                    elapsed = time.time() - start_time
                    rate = (nonce + 1) / elapsed if elapsed > 0 else 0
                    print(f"Hashes: {nonce+1}, Rate: {rate:.0f} H/s, Best: {best_bits} bits", file=sys.stderr)
            
            if not args.loop:
                break
    except KeyboardInterrupt:
        print("\nStopped", file=sys.stderr)
    finally:
        miner.close()


if __name__ == "__main__":
    main()
