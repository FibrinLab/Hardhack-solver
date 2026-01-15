#!/usr/bin/env python3
"""
Test chunked matmul for int32 precision with GPU
"""

import sys
import time
import numpy as np

try:
    import ttnn
    import torch
except ImportError as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)

M, K, N = 16, 50240, 16
CHUNK_SIZE = 500  # Safe for float32 precision

def chunked_matmul_gpu(device, A: np.ndarray, B: np.ndarray) -> np.ndarray:
    """
    Chunked matmul: split K into chunks, compute partial results on GPU,
    sum with int64 on CPU to maintain precision.
    """
    num_chunks = (K + CHUNK_SIZE - 1) // CHUNK_SIZE
    C_total = np.zeros((M, N), dtype=np.int64)
    
    for i in range(num_chunks):
        k_start = i * CHUNK_SIZE
        k_end = min((i + 1) * CHUNK_SIZE, K)
        
        # Extract chunks
        A_chunk = A[:, k_start:k_end].astype(np.float32)
        B_chunk = B[k_start:k_end, :].astype(np.float32)
        
        # GPU matmul
        A_t = torch.from_numpy(A_chunk)
        B_t = torch.from_numpy(B_chunk)
        
        A_tt = ttnn.from_torch(A_t, device=device, layout=ttnn.TILE_LAYOUT)
        B_tt = ttnn.from_torch(B_t, device=device, layout=ttnn.TILE_LAYOUT)
        
        C_tt = ttnn.matmul(A_tt, B_tt)
        C_t = ttnn.to_torch(C_tt)
        C_chunk = C_t.numpy()
        
        # Accumulate in int64
        C_total += C_chunk.astype(np.int64)
    
    return C_total.astype(np.int32)

def cpu_matmul(A: np.ndarray, B: np.ndarray) -> np.ndarray:
    """Reference CPU matmul with int32"""
    return np.matmul(A.astype(np.int32), B.astype(np.int32))

def main():
    print("Opening TTNN device...", file=sys.stderr)
    device = ttnn.open_device(device_id=0)
    print("Device ready", file=sys.stderr)
    
    # Generate test matrices
    print(f"\nGenerating random matrices ({M}x{K} @ {K}x{N})...", file=sys.stderr)
    A = np.random.randint(0, 256, (M, K), dtype=np.uint8)
    B = np.random.randint(-128, 128, (K, N), dtype=np.int8)
    
    # CPU reference
    print("Computing CPU reference...", file=sys.stderr)
    start = time.time()
    C_cpu = cpu_matmul(A, B)
    cpu_time = time.time() - start
    print(f"CPU time: {cpu_time*1000:.1f}ms", file=sys.stderr)
    
    # Single GPU matmul (known to lose precision)
    print("\nComputing single GPU matmul...", file=sys.stderr)
    start = time.time()
    A_t = torch.from_numpy(A.astype(np.float32))
    B_t = torch.from_numpy(B.astype(np.float32))
    A_tt = ttnn.from_torch(A_t, device=device, layout=ttnn.TILE_LAYOUT)
    B_tt = ttnn.from_torch(B_t, device=device, layout=ttnn.TILE_LAYOUT)
    C_tt = ttnn.matmul(A_tt, B_tt)
    C_t = ttnn.to_torch(C_tt)
    C_gpu_single = C_t.numpy().astype(np.int32)
    single_time = time.time() - start
    print(f"Single GPU time: {single_time*1000:.1f}ms", file=sys.stderr)
    
    single_diff = np.max(np.abs(C_gpu_single.astype(np.int64) - C_cpu.astype(np.int64)))
    print(f"Single GPU max error: {single_diff}", file=sys.stderr)
    print(f"Single GPU exact match: {np.array_equal(C_gpu_single, C_cpu)}", file=sys.stderr)
    
    # Chunked GPU matmul
    print(f"\nComputing chunked GPU matmul (chunk_size={CHUNK_SIZE})...", file=sys.stderr)
    start = time.time()
    C_gpu_chunked = chunked_matmul_gpu(device, A, B)
    chunked_time = time.time() - start
    print(f"Chunked GPU time: {chunked_time*1000:.1f}ms", file=sys.stderr)
    
    chunked_diff = np.max(np.abs(C_gpu_chunked.astype(np.int64) - C_cpu.astype(np.int64)))
    print(f"Chunked GPU max error: {chunked_diff}", file=sys.stderr)
    print(f"Chunked GPU exact match: {np.array_equal(C_gpu_chunked, C_cpu)}", file=sys.stderr)
    
    print("\n=== RESULTS ===")
    print(f"CPU:          {cpu_time*1000:.1f}ms, exact")
    print(f"Single GPU:   {single_time*1000:.1f}ms, max_error={single_diff}")
    print(f"Chunked GPU:  {chunked_time*1000:.1f}ms, max_error={chunked_diff}")
    
    if chunked_diff == 0:
        print("\n✅ CHUNKED GPU ACHIEVES EXACT INT32 PRECISION!")
        print("This can be used for valid_math=true mining!")
    else:
        print(f"\n⚠️ Chunked GPU still has errors. Try smaller chunk size.")
    
    ttnn.close_device(device)

if __name__ == "__main__":
    main()
