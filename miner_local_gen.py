#!/usr/bin/env python3
"""
HardHack Local Generator - Generate seeds locally, no network bottleneck!
Uses multiprocessing for maximum CPU parallelism on BLAKE3 XOF.
valid_math=true guaranteed.
"""

import os
import sys
import time
import struct
import multiprocessing as mp
import urllib.request
import json
import numpy as np

try:
    import blake3
except ImportError:
    print("Error: blake3 required. Install with: pip3 install blake3", file=sys.stderr)
    sys.exit(1)

try:
    import base58
except ImportError:
    os.system("pip3 install base58")
    import base58

RPC_URL = "https://testnet-rpc.ama.one"
M, K, N = 16, 50240, 16
XOF_SIZE = M * K + K * N  # 1,606,400 bytes


def fetch_seed_template():
    """Fetch one seed to get epoch, segment_vr_hash, pk, pop"""
    req = urllib.request.Request(f"{RPC_URL}/api/upow/seed")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.read()


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


def worker_process(worker_id: int, seed_template: bytes, difficulty: int, 
                   result_queue: mp.Queue, stats_queue: mp.Queue, stop_event):
    """
    Worker process: generate local nonces, compute XOF, matmul, hash.
    """
    # Each worker starts at different nonce range
    nonce_base = worker_id * (2**40)  # Huge range per worker
    local_seed = bytearray(seed_template)
    
    count = 0
    best_bits = 0
    start_time = time.time()
    
    while not stop_event.is_set():
        # Generate random nonce (12 bytes)
        nonce = nonce_base + count
        struct.pack_into('<Q', local_seed, 228, nonce & 0xFFFFFFFFFFFFFFFF)
        struct.pack_into('<I', local_seed, 236, (nonce >> 64) & 0xFFFFFFFF)
        
        current_seed = bytes(local_seed)
        
        # BLAKE3 XOF - this is the bottleneck
        h = blake3.blake3(current_seed)
        xof_data = h.digest(length=XOF_SIZE)
        
        # Parse matrices
        A = np.frombuffer(xof_data[:M*K], dtype=np.uint8).reshape(M, K)
        B = np.frombuffer(xof_data[M*K:], dtype=np.int8).reshape(K, N)
        
        # CPU int32 matmul (exact precision)
        C = np.matmul(A.astype(np.int32), B.astype(np.int32))
        
        # Build solution and hash
        C_bytes = C.astype('<i4').tobytes()
        solution = current_seed + C_bytes
        solution_hash = blake3.blake3(solution).digest()
        bits = check_difficulty(solution_hash)
        
        count += 1
        
        if bits > best_bits:
            best_bits = bits
            stats_queue.put(("best", worker_id, bits, count))
        
        if bits >= difficulty:
            result_queue.put(("found", solution, bits))
            return
        
        # Report stats every 100 hashes
        if count % 100 == 0:
            elapsed = time.time() - start_time
            rate = count / elapsed if elapsed > 0 else 0
            stats_queue.put(("stats", worker_id, count, rate))


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, default=mp.cpu_count(), help="Number of worker processes")
    parser.add_argument("--loop", action="store_true", help="Run continuously")
    args = parser.parse_args()
    
    print(f"HardHack Local Generator", file=sys.stderr)
    print(f"Workers: {args.workers}", file=sys.stderr)
    
    while True:
        # Fetch seed template and difficulty
        print("Fetching seed template...", file=sys.stderr)
        seed_template = fetch_seed_template()
        difficulty = fetch_difficulty()
        print(f"Difficulty: {difficulty} bits", file=sys.stderr)
        print(f"Seed template: {len(seed_template)} bytes", file=sys.stderr)
        
        # Validate first solution
        h = blake3.blake3(seed_template)
        xof_data = h.digest(length=XOF_SIZE)
        A = np.frombuffer(xof_data[:M*K], dtype=np.uint8).reshape(M, K)
        B = np.frombuffer(xof_data[M*K:], dtype=np.int8).reshape(K, N)
        C = np.matmul(A.astype(np.int32), B.astype(np.int32))
        solution = seed_template + C.astype('<i4').tobytes()
        val = submit_solution(solution)
        print(f"Validation: {val}", file=sys.stderr)
        
        # Start worker processes
        result_queue = mp.Queue()
        stats_queue = mp.Queue()
        stop_event = mp.Event()
        
        workers = []
        for i in range(args.workers):
            p = mp.Process(target=worker_process, 
                          args=(i, seed_template, difficulty, result_queue, stats_queue, stop_event))
            p.start()
            workers.append(p)
        
        print(f"Started {len(workers)} workers", file=sys.stderr)
        
        # Monitor progress
        start_time = time.time()
        total_hashes = 0
        best_bits = 0
        worker_counts = {}
        last_report = start_time
        
        try:
            while True:
                # Check for solution
                try:
                    result = result_queue.get(timeout=0.1)
                    if result[0] == "found":
                        stop_event.set()
                        _, solution, bits = result
                        print(f"\nSOLUTION FOUND! {bits} bits", file=sys.stderr)
                        val = submit_solution(solution)
                        print(f"Validation: {val}", file=sys.stderr)
                        break
                except:
                    pass
                
                # Process stats
                while True:
                    try:
                        stat = stats_queue.get_nowait()
                        if stat[0] == "stats":
                            _, worker_id, count, rate = stat
                            worker_counts[worker_id] = count
                        elif stat[0] == "best":
                            _, worker_id, bits, count = stat
                            if bits > best_bits:
                                best_bits = bits
                                print(f"NEW BEST: {bits} bits @ hash #{sum(worker_counts.values())}", file=sys.stderr)
                    except:
                        break
                
                # Report every second
                now = time.time()
                if now - last_report >= 1.0:
                    elapsed = now - start_time
                    total_hashes = sum(worker_counts.values())
                    rate = total_hashes / elapsed if elapsed > 0 else 0
                    
                    expected = 2 ** difficulty
                    eta_sec = (expected - total_hashes) / rate if rate > 0 else float('inf')
                    eta_hr = eta_sec / 3600
                    
                    print(f"Hashes: {total_hashes} | Rate: {rate:.1f}/s | Best: {best_bits}/{difficulty} bits | ETA: {eta_hr:.1f}h", file=sys.stderr)
                    last_report = now
                    
        except KeyboardInterrupt:
            print("\nStopping...", file=sys.stderr)
            stop_event.set()
        
        # Cleanup
        for p in workers:
            p.terminate()
            p.join(timeout=1)
        
        if not args.loop:
            break


if __name__ == "__main__":
    main()
