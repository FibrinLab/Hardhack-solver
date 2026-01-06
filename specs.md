# Amadeus Hard Hack: Final Specification

## 1. Sub-Track A (MatMul) - VERIFIED
- **Logic**: Standard Matrix Multiplication ($A 	imes B$).
- **Precision**: $A$ (unsigned `u8`), $B$ (signed `i8`), $C$ (signed `i32`).
- **Endianness**: **Little-Endian** (Native).
- **Dimensions**: $16 	imes 50240 	imes 16$.
- **Solution Payload**: 240 bytes (Seed) + 1024 bytes (Matrix C). Total: **1264 bytes**.
- **Submission**: Base58 encoded payload via GET to `/validate/<base58>`.

## 2. Sub-Track B (Succinct Prover)
- **Field**: BabyBear Field ($p = 2^{31} - 2^{27} + 1$).
- **Engine**: Parallel Radix-2 NTT ($2^{20}$ elements).
- **Metric**: Millions of Operations Per Second (MOPS).

## 3. Implementation Details
- **Architecture**: C++ Core + Bash Agent.
- **Optimizations**: ARM NEON SIMD, OpenMP Multi-threading, Zero-Allocation loops.
- **Deployment**: Standard Ubuntu 22.04 Docker with `libomp-dev`.
- **Target**: >200,000 solves/sec.