#!/usr/bin/env python3
"""
Test TTNN int8/uint8 matmul for exact int32 correctness.
"""

import sys
import numpy as np

try:
    import ttnn
    import torch
except ImportError as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)

M, K, N = 16, 50240, 16

def list_dtypes():
    print("ttnn int-related symbols:", [n for n in dir(ttnn) if "int" in n.lower() or "uint" in n.lower()])
    if hasattr(ttnn, "DataType"):
        print("ttnn.DataType:", [n for n in dir(ttnn.DataType) if n.isupper()])

def try_dtype(dtype_name, A_np, B_np):
    print(f"\n=== Testing dtype: {dtype_name} ===")
    if not hasattr(ttnn, dtype_name):
        print(f"ttnn.{dtype_name} not available")
        return False
    dtype = getattr(ttnn, dtype_name)

    try:
        device = ttnn.open_device(device_id=0)
    except Exception as e:
        print(f"Failed to open TT device: {e}")
        return False

    try:
        # Torch tensors
        A_t = torch.from_numpy(A_np)
        B_t = torch.from_numpy(B_np)

        # Convert to TTNN tensors
        A_tt = ttnn.from_torch(A_t, device=device, dtype=dtype, layout=ttnn.TILE_LAYOUT)
        B_tt = ttnn.from_torch(B_t, device=device, dtype=dtype, layout=ttnn.TILE_LAYOUT)

        # Matmul
        C_tt = ttnn.matmul(A_tt, B_tt)
        C_t = ttnn.to_torch(C_tt)
        C_gpu = C_t.numpy()

        # CPU reference
        C_cpu = np.matmul(A_np.astype(np.int32), B_np.astype(np.int32))

        max_diff = np.max(np.abs(C_gpu.astype(np.int64) - C_cpu.astype(np.int64)))
        exact = np.array_equal(C_gpu.astype(np.int32), C_cpu.astype(np.int32))
        print(f"max_diff={max_diff}, exact={exact}")
        return exact
    except Exception as e:
        print(f"FAILED: {e}")
        return False
    finally:
        try:
            ttnn.close_device(device)
        except Exception:
            pass

def main():
    list_dtypes()

    # Small test
    A_small = np.array([[1, 2], [3, 4]], dtype=np.uint8)
    B_small = np.array([[5, 6], [7, 8]], dtype=np.int8)

    # Full-size test
    A = np.random.randint(0, 256, (M, K), dtype=np.uint8)
    B = np.random.randint(-128, 128, (K, N), dtype=np.int8)

    # Try common int dtypes
    for dtype_name in ["int8", "uint8", "int32", "uint32"]:
        print("\n-- Small test --")
        try_dtype(dtype_name, A_small, B_small)
        print("\n-- Full-size test --")
        try_dtype(dtype_name, A, B)

if __name__ == "__main__":
    main()
