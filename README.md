# Amadeus Hard Hack Suite: Winner Edition

This repository contains **high‑performance engines and helper scripts** for both tracks of the Amadeus Hard Hack competition. It includes:

- A production C++ miner (`hardhack_miner`) with **exact int32 math** for valid submissions.
- A Python OpenBLAS miner (`miner_openblas.py`) with CPU **exact mode** and GPU **fast (inexact)** mode.
- A full Merkle proof system (Challenge B) with a CLI and benchmarks.
- A seed template mining utility and a JSON performance report mode.

This README documents **exactly what we built**, **why those choices were made**, and **how to run all paths**.

---

## 🚀 Local Docker Build (Recommended)
This is the fastest way to run the miner in a production-identical environment on your Mac or Linux.

```bash
# 1. Build the image
docker build -t hardhack-miner .

# 2. Run the Miner (Track A)
docker run -it hardhack-miner

# 3. Run the Merkle Prover (Challenge B)
docker run -it --entrypoint ./merkle_prove.sh hardhack-miner
```

---

## 🏎️ Sub‑Track A: Miner Architecture and Workflow

### 1) Protocol summary (from server implementation)
The seed format is fixed and matches the server logic:

```
seed = epoch_le(4) || segment_vr_hash(32) || pk(48) || pop(96) || pk(48) || nonce(12)
```

Matrix generation:
```
matrix_a_b = blake3_xof(seed, 16*50240 + 50240*16)
```

Interpretation:
- `A` is `u8` (16×50240)
- `B` is `i8` (50240×16)
- `C` is `i32` (16×16)

Solution payload:
```
solution = seed || C_bytes (little‑endian int32)
```

Validation on the server:
- `valid` checks difficulty and `segment_vr_hash`.
- `valid_math` uses Freivalds to verify `A×B=C` from your submitted seed.

### 2) Why GPU math fails (TTNN)
TTNN matmul is **float‑only**. With K=50240, float32 errors accumulate and `C` becomes **inexact**, which fails `valid_math`. We verified this by comparing GPU float32 outputs against CPU int32 and observing large max error on real matrix sizes.

### 3) C++ Miner (`mine.sh` + `hardhack_miner`)
- C++/OpenMP miner does **exact int32** math.
- `mine.sh` is tuned for CPU throughput and prints validation results.
- `mine.sh` currently **forces diffbits=6** for a fast `valid_math=true` demonstration.

Run:
```bash
./mine.sh
```

Build:
```bash
rm -rf build && mkdir build && cd build
cmake .. -DENABLE_TT=OFF -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

### 4) Python OpenBLAS Miner (`miner_openblas.py`)
CPU exact mode:
```bash
python3 miner_openblas.py --loop
```

GPU fast mode (inexact, valid_math may be false):
```bash
python3 miner_openblas.py --gpu --loop
```

JSON performance report:
```bash
python3 miner_openblas.py --report --report-runs 50
python3 miner_openblas.py --gpu --report --report-runs 50
```

### 5) Local Seed Template Mining (no network fetch)
Use a JSON template and scan nonces locally:
```bash
python3 miner_local_seedfile.py --seed-json seed_template.json --difficulty 10 --workers 8
python3 miner_local_seedfile.py --seed-json seed_template.json --difficulty 10 --gpu
```

### 6) TTNN runtime limitations
- TTNN `matmul` requires floating‑point inputs.
- TTNN cannot do **exact int32 matmul** for this workload.
- TTNN may fail with `Failed to allocate the TLB` if hugepages are missing:
```bash
export TT_METAL_SKIP_HUGEPAGES=1
export TT_METAL_TLB_MODE=1
export TT_METAL_DISABLE_LARGE_PAGES=1
export TT_METAL_LARGE_PAGES=0
```

---

## 🧩 Challenge B: Merkle Proof on RISC‑V

### 1) What it proves
`merkle_prove.sh` runs `hardhack_merkle_prover`, which:
- builds a Merkle tree from a seed,
- generates an inclusion proof for a leaf index,
- verifies the proof **locally**.

This is a **Merkle inclusion proof**, not a ZK proof.

Run:
```bash
./merkle_prove.sh
```

### 2) RISC‑V compatibility
The prover is portable C++ (no platform SIMD). The script prints the detected arch and warns if not `riscv64`.

### 3) Direct binary usage
```bash
./build/hardhack_merkle_prover --size 1024 --index 42
./build/hardhack_merkle_prover --seed abc123... --size 512
./build/hardhack_merkle_prover --size 1024 --benchmark
```

---

## 🛠 Manual Setup (macOS M4 Pro)
```bash
brew install libomp
mkdir -p build && cd build
cmake .. -DENABLE_TT=OFF -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

---

## 🧪 Testing Mode
Scripts have a `LOCAL_TEST=true` flag inside. Set it to `false` to connect to the live API.
- On Docker: run with `-e LOCAL_TEST=false` to override.

---

## 🧭 Roadmap / Known Work
- Attempted TT‑Metal C++ int32 kernel (blocked by missing TT‑Metal headers on container)
- TTNN matmul only supports float32 → `valid_math` false
- Local seed template miner for offline nonce scanning
- JSON perf reporting for technical submissions
