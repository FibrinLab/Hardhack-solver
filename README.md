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

# 3. Run the Prover (Track B)
docker run -it --entrypoint ./prove.sh hardhack-miner
```

---

## 🏎️ Sub-Track A: The Miner (`mine.sh`)
- **Engine**: NEON-optimized C++ Int8 MatMul ($16 \times 50240$).
- **Logic**: Directly fetches seeds from `testnet-rpc.ama.one` and submits via Base58 GET.
- **Run Locally (No Docker)**:
```bash
./mine.sh
```

## 🧩 Sub-Track B: The Prover (`prove.sh`)
- **Engine**: BabyBear Field parallel NTT Prover ($2^{20}$ elements).
- **Run Locally (No Docker)**:
```bash
./prove.sh
```

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
Both scripts have a `LOCAL_TEST=true` flag inside. Set it to `false` to connect to the live Amadeus Testnet.
- **On Docker**: Run with `-e LOCAL_TEST=false` to override.

```
