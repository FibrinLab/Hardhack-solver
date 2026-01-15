#!/usr/bin/env python3
"""
Test if TTNN supports int32 matmul
"""

import sys
import numpy as np

try:
    import ttnn
    import torch
except ImportError as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)

def test_int32_support():
    print("Opening TTNN device...", file=sys.stderr)
    device = ttnn.open_device(device_id=0)
    print("Device opened", file=sys.stderr)
    
    # Create small int32 matrices
    A = np.array([[1, 2], [3, 4]], dtype=np.int32)
    B = np.array([[5, 6], [7, 8]], dtype=np.int32)
    expected_C = np.matmul(A, B)
    
    print(f"\nA (int32):\n{A}", file=sys.stderr)
    print(f"B (int32):\n{B}", file=sys.stderr)
    print(f"Expected C:\n{expected_C}", file=sys.stderr)
    
    try:
        # Test 1: Direct int32 tensor
        print("\n=== TEST 1: Direct int32 ===", file=sys.stderr)
        A_t = torch.from_numpy(A)
        B_t = torch.from_numpy(B)
        print(f"Torch dtypes: A={A_t.dtype}, B={B_t.dtype}", file=sys.stderr)
        
        A_tt = ttnn.from_torch(A_t, device=device)
        B_tt = ttnn.from_torch(B_t, device=device)
        print(f"TTNN tensors created", file=sys.stderr)
        
        C_tt = ttnn.matmul(A_tt, B_tt)
        C_t = ttnn.to_torch(C_tt)
        C = C_t.numpy()
        
        print(f"Result C:\n{C}", file=sys.stderr)
        print(f"Match: {np.allclose(C, expected_C)}", file=sys.stderr)
        
    except Exception as e:
        print(f"TEST 1 FAILED: {e}", file=sys.stderr)
    
    try:
        # Test 2: Convert to float, then back to int
        print("\n=== TEST 2: Float32 conversion ===", file=sys.stderr)
        A_t = torch.from_numpy(A.astype(np.float32))
        B_t = torch.from_numpy(B.astype(np.float32))
        
        A_tt = ttnn.from_torch(A_t, device=device, layout=ttnn.TILE_LAYOUT)
        B_tt = ttnn.from_torch(B_t, device=device, layout=ttnn.TILE_LAYOUT)
        
        C_tt = ttnn.matmul(A_tt, B_tt)
        C_t = ttnn.to_torch(C_tt)
        C = C_t.numpy().astype(np.int32)
        
        print(f"Result C:\n{C}", file=sys.stderr)
        print(f"Match: {np.array_equal(C, expected_C)}", file=sys.stderr)
        
    except Exception as e:
        print(f"TEST 2 FAILED: {e}", file=sys.stderr)
    
    try:
        # Test 3: Large matrices (16x50240x16)
        print("\n=== TEST 3: Full size matrices ===", file=sys.stderr)
        M, K, N = 16, 50240, 16
        A_large = np.random.randint(0, 256, (M, K), dtype=np.uint8)
        B_large = np.random.randint(-128, 128, (K, N), dtype=np.int8)
        
        # CPU reference
        C_cpu = np.matmul(A_large.astype(np.int32), B_large.astype(np.int32))
        
        # GPU float32
        A_t = torch.from_numpy(A_large.astype(np.float32))
        B_t = torch.from_numpy(B_large.astype(np.float32))
        
        A_tt = ttnn.from_torch(A_t, device=device, layout=ttnn.TILE_LAYOUT)
        B_tt = ttnn.from_torch(B_t, device=device, layout=ttnn.TILE_LAYOUT)
        
        C_tt = ttnn.matmul(A_tt, B_tt)
        C_t = ttnn.to_torch(C_tt)
        C_gpu = C_t.numpy().astype(np.int32)
        
        max_diff = np.max(np.abs(C_gpu - C_cpu))
        print(f"Max difference: {max_diff}", file=sys.stderr)
        print(f"Exact match: {np.array_equal(C_gpu, C_cpu)}", file=sys.stderr)
        
        if max_diff > 0:
            print(f"ERROR: Float32 conversion loses precision!", file=sys.stderr)
            print(f"Sample differences:", file=sys.stderr)
            diff_mask = C_gpu != C_cpu
            if np.any(diff_mask):
                idx = np.argwhere(diff_mask)[0]
                print(f"  Position {idx}: CPU={C_cpu[tuple(idx)]}, GPU={C_gpu[tuple(idx)]}", file=sys.stderr)
        
    except Exception as e:
        print(f"TEST 3 FAILED: {e}", file=sys.stderr)
    
    ttnn.close_device(device)

if __name__ == "__main__":
    test_int32_support()
