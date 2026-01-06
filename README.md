# Amadeus Hard Hack Suite: Winner Edition

This repository contains the ultimate high-performance tools for both tracks of the Amadeus Hard Hack competition.

---

## 🏎️ Sub-Track A: The Miner (`mine.sh`)
- **Engine**: NEON-optimized C++ Int8 MatMul ($16 \times 50240$).
- **Logic**: Directly fetches seeds from `testnet-rpc.ama.one`, unrolls the unrolled blake3_xof stream, and submits solutions via Base58 GET.
- **Run**:
```bash
chmod +x mine.sh
./mine.sh
```

## 🧩 Sub-Track B: The Prover (`prove.sh`)
- **Engine**: BabyBear Field parallel NTT Prover.
- **Metric**: Measured in MOPS (Millions of Ops Per Second).
- **Run**:
```bash
chmod +x prove.sh
./prove.sh
```

---

## 🛠 Setup & Build
```bash
# 1. Install OpenMP (Required for M4 Pro performance)
brew install libomp

# 2. Build binaries
mkdir -p build && cd build
cmake .. -DENABLE_TT=OFF -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

## 📋 Competition Specs (Local Memory)
- **Matrix A**: $16 \times 50240$ (u8)
- **Matrix B**: $50240 \times 16$ (i8)
- **Matrix C**: $16 \times 16$ (i32)
- **Validation**: Base58 encoded `seed <> tensor_c` (Total 1264 bytes).
- **Target**: >200,000 solves/sec.