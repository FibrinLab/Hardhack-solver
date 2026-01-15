#!/usr/bin/env python3
"""
Local-seed miner (no seed/matrix fetch).
Uses a JSON seed template file to generate local nonces and mine.

JSON format:
{
  "epoch_le": "00000000",
  "segment_vr_hash": "32-byte-hex",
  "pk": "48-byte-hex",
  "pop": "96-byte-hex"
}
"""

import argparse
import json
import os
import struct
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

# Optional TTNN GPU (float32, fast but inexact)
try:
    import ttnn
    import torch
    _HAS_TTNN = True
except Exception:
    _HAS_TTNN = False

try:
    import blake3
except ImportError:
    print("Error: blake3 required. Install with: pip3 install blake3", file=sys.stderr)
    sys.exit(1)

M, K, N = 16, 50240, 16
XOF_SIZE = M * K + K * N

_BASE_SEED = None
_DIFF = None


def _init_worker(seed: bytes, diff: int):
    global _BASE_SEED, _DIFF
    _BASE_SEED = seed
    _DIFF = diff


def _check_difficulty(hash_bytes: bytes, difficulty_bits: int) -> int:
    hash_int = int.from_bytes(hash_bytes, "big")
    if hash_int == 0:
        return 256
    return 256 - hash_int.bit_length()


def _process_nonce(nonce: int):
    local_seed = bytearray(_BASE_SEED)
    struct.pack_into("<Q", local_seed, 228, nonce)
    local_seed = bytes(local_seed)

    xof_data = blake3.blake3(local_seed).digest(length=XOF_SIZE)
    A = np.frombuffer(xof_data[: M * K], dtype=np.uint8).reshape(M, K).astype(np.int32)
    B = np.frombuffer(xof_data[M * K :], dtype=np.int8).reshape(K, N).astype(np.int32)
    C = np.dot(A, B)

    solution = local_seed + C.astype("<i4").tobytes()
    h = blake3.blake3(solution).digest()
    bits = _check_difficulty(h, _DIFF)
    return nonce, bits, solution


def _process_nonce_gpu(nonce: int):
    if not _HAS_TTNN:
        raise RuntimeError("TTNN not available for GPU mode")
    local_seed = bytearray(_BASE_SEED)
    struct.pack_into("<Q", local_seed, 228, nonce)
    local_seed = bytes(local_seed)

    xof_data = blake3.blake3(local_seed).digest(length=XOF_SIZE)
    A = np.frombuffer(xof_data[: M * K], dtype=np.uint8).reshape(M, K)
    B = np.frombuffer(xof_data[M * K :], dtype=np.int8).reshape(K, N)

    # TTNN float32 matmul (fast, may be inaccurate)
    A_t = torch.from_numpy(A.astype(np.float32))
    B_t = torch.from_numpy(B.astype(np.float32))
    A_tt = ttnn.from_torch(A_t, device=_TTNN_DEVICE, layout=ttnn.TILE_LAYOUT)
    B_tt = ttnn.from_torch(B_t, device=_TTNN_DEVICE, layout=ttnn.TILE_LAYOUT)
    C_tt = ttnn.matmul(A_tt, B_tt)
    C_t = ttnn.to_torch(C_tt)
    C = C_t.numpy().astype(np.int32)

    solution = local_seed + C.astype("<i4").tobytes()
    h = blake3.blake3(solution).digest()
    bits = _check_difficulty(h, _DIFF)
    return nonce, bits, solution


def _build_seed_from_json(data: dict) -> bytes:
    epoch_le = bytes.fromhex(data["epoch_le"])
    segment_vr_hash = bytes.fromhex(data["segment_vr_hash"])
    pk = bytes.fromhex(data["pk"])
    pop = bytes.fromhex(data["pop"])

    if len(epoch_le) != 4:
        raise ValueError("epoch_le must be 4 bytes (little-endian hex)")
    if len(segment_vr_hash) != 32:
        raise ValueError("segment_vr_hash must be 32 bytes")
    if len(pk) != 48:
        raise ValueError("pk must be 48 bytes")
    if len(pop) != 96:
        raise ValueError("pop must be 96 bytes")

    nonce = b"\x00" * 12
    return epoch_le + segment_vr_hash + pk + pop + pk + nonce


def main():
    parser = argparse.ArgumentParser(description="Local-seed miner")
    parser.add_argument("--seed-json", required=True, help="Path to seed template JSON")
    parser.add_argument("--difficulty", type=int, default=10, help="Difficulty bits")
    parser.add_argument("--iterations", type=int, default=10000000, help="Max iterations")
    parser.add_argument("--workers", type=int, default=os.cpu_count() or 1)
    parser.add_argument("--gpu", action="store_true", help="Use TTNN GPU (fast, may be invalid)")
    args = parser.parse_args()

    with open(args.seed_json, "r") as f:
        seed_json = json.load(f)
    seed = _build_seed_from_json(seed_json)

    print(f"Seed length: {len(seed)} bytes", file=sys.stderr)
    print(f"Difficulty: {args.difficulty} bits", file=sys.stderr)
    print(f"Workers: {args.workers}", file=sys.stderr)

    best_bits = 0
    total_hashes = 0
    start = time.time()
    last_report = start
    nonce = 0

    if args.gpu:
        if not _HAS_TTNN:
            raise RuntimeError("TTNN not available for GPU mode")
        print("[!] GPU mode prioritizes speed over accuracy; valid_math may be false", file=sys.stderr)
        global _TTNN_DEVICE
        _TTNN_DEVICE = ttnn.open_device(device_id=0)

    with ProcessPoolExecutor(
        max_workers=args.workers, initializer=_init_worker, initargs=(seed, args.difficulty)
    ) as executor:
        while nonce < args.iterations:
            batch = list(range(nonce, min(nonce + args.workers * 20, args.iterations)))
            if args.gpu:
                futures = {executor.submit(_process_nonce_gpu, n): n for n in batch}
            else:
                futures = {executor.submit(_process_nonce, n): n for n in batch}

            for future in as_completed(futures):
                n, bits, _ = future.result()
                total_hashes += 1
                if bits > best_bits:
                    best_bits = bits
                    elapsed = time.time() - start
                    rate = total_hashes / elapsed if elapsed > 0 else 0
                    print(f"NEW BEST: {bits} bits @ nonce {n}, Rate: {rate:.1f} H/s", file=sys.stderr)

                if bits >= args.difficulty:
                    elapsed = time.time() - start
                    rate = total_hashes / elapsed if elapsed > 0 else 0
                    print(f"SOLUTION FOUND @ {n}, Rate: {rate:.1f} H/s", file=sys.stderr)
                    if args.gpu and _HAS_TTNN:
                        ttnn.close_device(_TTNN_DEVICE)
                    return

            nonce += len(batch)

            now = time.time()
            if now - last_report >= 1.0:
                elapsed = now - start
                rate = total_hashes / elapsed if elapsed > 0 else 0
                print(f"Hashes: {total_hashes}, Rate: {rate:.1f} H/s, Best: {best_bits} bits", file=sys.stderr)
                last_report = now

    if args.gpu and _HAS_TTNN:
        ttnn.close_device(_TTNN_DEVICE)


if __name__ == "__main__":
    main()
