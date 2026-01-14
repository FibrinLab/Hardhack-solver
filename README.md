# Amadeus Hard Hack Suite: Winner Edition

This repository contains high-performance engines for both tracks of the Amadeus Hard Hack competition.

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

## 🏎️ Sub-Track A: The Miner (`mine.sh`)
- **Engine**: NEON-optimized C++ Int8 MatMul ($16 \times 50240$).
- **Logic**: Directly fetches seeds from `testnet-rpc.ama.one` and submits via Base58 GET.
- **Run Locally (No Docker)**:
```bash
./mine.sh
```

## 🧩 Challenge B: Merkle Proof on RISC-V (`merkle_prove.sh`)
- **Engine**: High-performance Merkle tree proof generation and verification.
- **Features**: Fast Merkle proof generation, verification, and BLAKE3 hashing.
- **Run Locally (No Docker)**:
```bash
./merkle_prove.sh
```

### Challenge B Details

**Implementation**: Succinct proof system optimized for RISC-V architecture.

**Features**:
- Fast Merkle Tree Construction using BLAKE3 hashing
- Efficient Proof Generation (O(log n) time)
- Fast Proof Verification (O(log n) time)
- RISC-V Optimized: Portable C++ code
- BLAKE3 Hashing: Uses portable implementation

**Build**:
```bash
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make hardhack_merkle_prover
```

**Direct Binary Usage**:
```bash
# Basic usage
./build/hardhack_merkle_prover --size 1024 --index 42

# With seed for deterministic generation
./build/hardhack_merkle_prover --seed abc123... --size 512

# Benchmark mode
./build/hardhack_merkle_prover --size 1024 --benchmark
```

**Performance** (1024-leaf tree):
- Tree Build: ~0.3ms
- Proof Generation: ~0.001ms
- Proof Verification: ~0.001ms
- Hashes/sec: ~6.6M
- Proof Size: ~388 bytes

---

## 🛠 Manual Setup (macOS M4 Pro)
```bash
# Install dependencies
brew install libomp

# Build binaries
mkdir -p build && cd build
cmake .. -DENABLE_TT=OFF -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

## 🧪 Testing Mode
Scripts have a `LOCAL_TEST=true` flag inside. Set it to `false` to connect to the live API.
- **On Docker**: Run with `-e LOCAL_TEST=false` to override.

```
