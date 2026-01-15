#!/usr/bin/env python3
"""
HardHack Parallel Seed Fetcher - Maximum speed with valid_math=true
Uses server's pre-computed matrices (no XOF needed!)
"""

import os
import sys
import time
import threading
import queue
import urllib.request
import json
import numpy as np

try:
    import blake3
    def blake3_hash(data: bytes) -> bytes:
        return blake3.blake3(data).digest()
except ImportError:
    print("Error: blake3 required. Install with: pip3 install blake3", file=sys.stderr)
    sys.exit(1)

try:
    import base58
except ImportError:
    os.system("pip3 install base58")
    import base58

# GPU cannot do exact int32 matmul - use CPU only
print("Using CPU for matmul (exact int32 precision)", file=sys.stderr)

RPC_URL = "https://testnet-rpc.ama.one"
M, K, N = 16, 50240, 16

# Shared state
results_queue = queue.Queue()
stop_event = threading.Event()
stats_lock = threading.Lock()
total_seeds = 0
best_bits = 0
best_solution = None


def fetch_seed_with_matrices():
    """Fetch seed + pre-computed A, B from server"""
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
    sol_b58 = base58.b58encode(solution).decode()
    req = urllib.request.Request(f"{RPC_URL}/api/upow/validate/{sol_b58}")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def check_difficulty(hash_bytes: bytes) -> int:
    hash_int = int.from_bytes(hash_bytes, 'big')
    if hash_int == 0:
        return 256
    return 256 - hash_int.bit_length()


def cpu_matmul(A: np.ndarray, B: np.ndarray) -> np.ndarray:
    """CPU matmul with exact int32 precision"""
    return np.matmul(A.astype(np.int32), B.astype(np.int32))


def worker(worker_id: int, difficulty: int):
    """Worker thread: fetch seed, compute, check"""
    global total_seeds, best_bits, best_solution
    
    while not stop_event.is_set():
        try:
            # Fetch seed with pre-computed matrices (server does XOF!)
            seed, A, B = fetch_seed_with_matrices()
            
            # CPU matmul (exact int32 precision)
            C = cpu_matmul(A, B)
            C_bytes = C.astype('<i4').tobytes()
            
            # Build solution and hash
            solution = seed + C_bytes
            h = blake3_hash(solution)
            bits = check_difficulty(h)
            
            with stats_lock:
                total_seeds += 1
                
                if bits > best_bits:
                    best_bits = bits
                    best_solution = solution
                    elapsed = time.time() - start_time if 'start_time' in globals() else 0
                    print(f"NEW BEST: {bits} bits @ solve #{total_seeds}", file=sys.stderr)
                
                if bits >= difficulty:
                    results_queue.put(("found", solution, bits))
                    return
                    
        except Exception as e:
            # Network error, retry
            time.sleep(0.1)


def main():
    global total_seeds, best_bits, best_solution
    
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, default=20, help="Number of parallel workers")
    parser.add_argument("--loop", action="store_true", help="Run continuously")
    args = parser.parse_args()
    
    print(f"Starting {args.workers} parallel workers...", file=sys.stderr)
    
    while True:
        # Reset state
        total_seeds = 0
        best_bits = 0
        best_solution = None
        stop_event.clear()
        
        # Get difficulty
        difficulty = fetch_difficulty()
        print(f"Difficulty: {difficulty} bits", file=sys.stderr)
        
        # Validate first seed
        seed, A, B = fetch_seed_with_matrices()
        C = cpu_matmul(A, B)
        solution = seed + C.astype('<i4').tobytes()
        val = submit_solution(solution)
        print(f"Validation: {val}", file=sys.stderr)
        
        # Start workers
        workers = []
        for i in range(args.workers):
            t = threading.Thread(target=worker, args=(i, difficulty))
            t.daemon = True
            t.start()
            workers.append(t)
        
        # Monitor progress
        start_time = time.time()
        last_report = start_time
        
        try:
            while True:
                # Check for solution
                try:
                    result = results_queue.get(timeout=0.1)
                    if result[0] == "found":
                        stop_event.set()
                        _, solution, bits = result
                        print(f"SOLUTION FOUND! {bits} bits", file=sys.stderr)
                        val = submit_solution(solution)
                        print(f"Validation: {val}", file=sys.stderr)
                        break
                except queue.Empty:
                    pass
                
                # Report stats every second
                now = time.time()
                if now - last_report >= 1.0:
                    elapsed = now - start_time
                    with stats_lock:
                        rate = total_seeds / elapsed if elapsed > 0 else 0
                        # Estimate time to solution (2^difficulty seeds on average)
                        expected_seeds = 2 ** difficulty
                        eta_seconds = (expected_seeds - total_seeds) / rate if rate > 0 else float('inf')
                        eta_min = eta_seconds / 60
                        eta_hr = eta_seconds / 3600
                        
                        if eta_hr > 1:
                            eta_str = f"{eta_hr:.1f}h"
                        elif eta_min > 1:
                            eta_str = f"{eta_min:.1f}m"
                        else:
                            eta_str = f"{eta_seconds:.0f}s"
                        
                        print(f"Solves: {total_seeds} | Rate: {rate:.1f}/s | Best: {best_bits}/{difficulty} bits | ETA: {eta_str}", file=sys.stderr)
                    last_report = now
                    
        except KeyboardInterrupt:
            print("\nStopping...", file=sys.stderr)
            stop_event.set()
            break
        
        if not args.loop:
            break
        
        # Wait for workers to stop
        stop_event.set()
        for t in workers:
            t.join(timeout=1)


if __name__ == "__main__":
    main()
