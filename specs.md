# Amadeus Hard Hack: Master Specification & Local Memory

This document synthesizes the competition requirements, protocol specifications, and hardware architecture for the Amadeus Hard Hack RISC-V Benchmarking Competition.

---

## 1. Competition Overview
**Goal:** Low-level performance engineering using RISC-V workloads and Tenstorrent compute primitives.
- **Target Hardware:** Tenstorrent Grayskull/Wormhole (RISC-V with AI Acceleration).
- **Primary Metrics:** Solves per second (Throughput) and Latency.
- **Performance Target:** >200,000 solves/sec (Sub-Track A).

### Sub-Tracks:
- **Sub-Track A (MatMul Miner):** Optimize $16 \times 50240$ Int8 matrix multiplication.
- **Sub-Track B (Succinct Prover):** Optimize ZK-proof primitives (NTT, Finite Field math) on RISC-V.

---

## 2. Protocol Specifications (Sub-Track A)

### Seed Construction (240 Bytes Binary)
The miner receives/generates a seed used to derive the workload.
| Field | Size | Description |
| :--- | :--- | :--- |
| Epoch | 4 Bytes | uint32, Little-endian |
| VRF Hash | 32 Bytes | Segment VRF binary |
| Node PK | 48 Bytes | Validator Public Key (BLS) |
| Node POP | 96 Bytes | Proof of Possession |
| Solver PK | 48 Bytes | Usually same as Node PK |
| Nonce | 12 Bytes | Incremented internally by miner |

### Data Generation (Blake3 XOF)
1.  Initialize Blake3 hasher with the 240-byte seed.
2.  Use XOF (Extendable Output Function) to generate $16 \times 50240 + 50240 \times 16$ bytes.
3.  **Matrix A:** First $16 \times 50240$ bytes (Int8).
4.  **Matrix B:** Next $50240 \times 16$ bytes (Int8).

### Computation & Correctness
- **Task:** Perform $C = A \times B$ where $C$ is a $16 \times 16$ Int8 matrix.
- **Solution Binary:** `Seed (240 bytes) <> Result Matrix C (256 bytes)`.
- **Target Hash:** `Blake3(Solution Binary)` must have `difficulty_bits` leading zeros.

---

## 3. Succinct Proof Primitives (Sub-Track B)

### Mathematical Basis
- **Field:** BabyBear Field ($p = 2^{31} - 2^{27} + 1$).
- **Primitive Root:** $g = 31$.
- **Bottleneck:** Number Theoretic Transform (NTT) and Montgomery Multiplication.
- **Target:** Maximize modular operations per second (MOPS) via SIMD and parallel butterflies.

---

## 4. Hardware Architecture: Tenstorrent (Metalium)

### Compute Model
- **SPMD (Single Program, Multiple Data):** Static parallelism across Tensix cores.
- **Tiles:** Hardware natively processes $32 \times 32$ tiles.
- **Memory Layout:** DRAM -> L1 Cache (Local to core) -> Regs.

### Kernel Pipeline
1.  **Reader Kernel (RISCV_1):** Fetches data from DRAM to L1 Circular Buffers.
2.  **Compute Kernel:** Performs tile-based MatMul using Tensix math engine.
3.  **Writer Kernel (RISCV_0):** Moves result tiles from L1 back to DRAM.

---

## 5. Optimized Implementation Memory (LLM Context)

### Current CPU Optimizations (M4 Pro)
- **ARM NEON:** Uses `vmlal_u16` to process 16 columns simultaneously.
- **Incremental Hashing:** Caches Blake3 state after the first 228 bytes to skip redundant work.
- **Zero-Allocation:** All thread-local buffers ($A, B, C, XOF$) are pre-allocated outside the hot loop.
- **Loop Ordering:** Matrix B is accessed contiguously to maximize L1 cache hits.

### Deployment Environment
- **Docker Image:** `ghcr.io/tenstorrent/tt-xla/tt-xla-ird-ubuntu-22-04:latest`.
- **Koyeb Port:** `8000`.
- **Dual-Submission:** Agent must post to Admin `/validate` (scoring) and Testnet RPC `submit_sol` (on-chain).

---

## 6. Environment Endpoints
- **Testnet RPC:** `https://testnet.ama.one/` (or `46.4.179.184`).
- **Explorer:** `ama-explorer.ddns.net`.
- **Wallet:** `wallet.ama.one`.
- **Admin API:** Managed endpoint for workloads and scoring validation.

---

## 7. Operational Guidelines
- **Local Testing:** Set `LOCAL_TEST=true` in `testnet_agent.sh` to iterate offline.
- **Building:** Always use `-DCMAKE_BUILD_TYPE=Release` and `-march=native`.
- **Mac Users:** Requires `libomp` via Homebrew for multi-threaded performance.
