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

# Try to use GPU for matmul
USE_GPU = False
try:
    import torch
    if torch.cuda.is_available():
        USE_GPU = True
        GPU_DEVICE = torch.device('cuda')
        print("Using CUDA GPU for matmul", file=sys.stderr)
    else:
        # Try TTNN but with chunked approach for precision
        try:
            import ttnn
            USE_GPU = True
            GPU_DEVICE = "ttnn"
            TTNN_DEVICE = ttnn.open_device(device_id=0)
            print("Using TTNN GPU for matmul (chunked for precision)", file=sys.stderr)
        except:
            print("No GPU available, using CPU", file=sys.stderr)
except ImportError:
    print("PyTorch not available, using CPU", file=sys.stderr)

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


# Lock for GPU access (TTNN is not thread-safe)
gpu_lock = threading.Lock()

def gpu_matmul(A: np.ndarray, B: np.ndarray) -> np.ndarray:
    """GPU matmul with int32 precision"""
    global TTNN_DEVICE
    
    if GPU_DEVICE == "ttnn":
        # Use chunked approach for TTNN to maintain precision
        CHUNK_SIZE = 32  # Very small for precision
        num_chunks = (K + CHUNK_SIZE - 1) // CHUNK_SIZE
        C_total = np.zeros((M, N), dtype=np.int64)
        
        with gpu_lock:
            for i in range(num_chunks):
                k_start = i * CHUNK_SIZE
                k_end = min((i + 1) * CHUNK_SIZE, K)
                
                A_chunk = A[:, k_start:k_end].astype(np.float32)
                B_chunk = B[k_start:k_end, :].astype(np.float32)
                
                A_t = torch.from_numpy(A_chunk)
                B_t = torch.from_numpy(B_chunk)
                
                A_tt = ttnn.from_torch(A_t, device=TTNN_DEVICE, layout=ttnn.TILE_LAYOUT)
                B_tt = ttnn.from_torch(B_t, device=TTNN_DEVICE, layout=ttnn.TILE_LAYOUT)
                
                C_tt = ttnn.matmul(A_tt, B_tt)
                C_t = ttnn.to_torch(C_tt)
                C_chunk = C_t.numpy()
                
                C_total += C_chunk.astype(np.int64)
        
        return C_total.astype(np.int32)
    else:
        # PyTorch CUDA - can do int32 directly
        with gpu_lock:
            A_t = torch.from_numpy(A.astype(np.int32)).to(GPU_DEVICE)
            B_t = torch.from_numpy(B.astype(np.int32)).to(GPU_DEVICE)
            C_t = torch.matmul(A_t, B_t)
            return C_t.cpu().numpy()


def cpu_matmul(A: np.ndarray, B: np.ndarray) -> np.ndarray:
    """CPU matmul with exact int32 precision"""
    return np.matmul(A.astype(np.int32), B.astype(np.int32))


def worker(worker_id: int, difficulty: int, use_gpu: bool):
    """Worker thread: fetch seed, compute, check"""
    global total_seeds, best_bits, best_solution
    
    while not stop_event.is_set():
        try:
            # Fetch seed with pre-computed matrices (server does XOF!)
            seed, A, B = fetch_seed_with_matrices()
            
            # Matmul (GPU or CPU)
            if use_gpu and USE_GPU:
                C = gpu_matmul(A, B)
            else:
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
                    print(f"[Worker {worker_id}] NEW BEST: {bits} bits", file=sys.stderr)
                
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
    parser.add_argument("--gpu", action="store_true", help="Use GPU for matmul")
    args = parser.parse_args()
    
    if args.gpu and USE_GPU:
        print(f"Starting {args.workers} parallel workers with GPU matmul...", file=sys.stderr)
    else:
        print(f"Starting {args.workers} parallel workers with CPU matmul...", file=sys.stderr)
    
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
        if args.gpu and USE_GPU:
            C = gpu_matmul(A, B)
        else:
            C = cpu_matmul(A, B)
        solution = seed + C.astype('<i4').tobytes()
        val = submit_solution(solution)
        print(f"Validation: {val}", file=sys.stderr)
        
        # Start workers
        workers = []
        for i in range(args.workers):
            t = threading.Thread(target=worker, args=(i, difficulty, args.gpu))
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
                        print(f"Seeds: {total_seeds}, Rate: {rate:.1f}/s, Best: {best_bits} bits", file=sys.stderr)
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
