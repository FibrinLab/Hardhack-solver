# Amadeus Hard Hack Kernel: RISC-V Miner

This repository contains a high-performance C++ miner optimized for the Amadeus Hard Hack competition.

## Architecture
- **Miner (C++)**: Core logic using Blake3 and high-speed matrix multiplication ($16 \times 50240$). Optimized with ARM NEON for local dev and `tt-metal` for production hardware.
- **Agent (Bash)**: Zero-overhead mining loop and performance tracker.
- **Hardware Acceleration**: Full integration with Tenstorrent Grayskull/Wormhole Tensix cores.

---

## Local Build & Stress Test (CPU Only)
Optimized for Apple Silicon (M4 Pro).
```bash
# 1. Install OpenMP (macOS)
brew install libomp

# 2. Build
rm -rf build && mkdir build && cd build
cmake .. -DENABLE_TT=OFF
make -j$(nproc)

# 3. Run Stress Test (100 batches)
cd ..
./miner.sh 100
```

---

## Docker Build (Production Hardware)
Use this for deployment to Tenstorrent-enabled environments or Koyeb.
```bash
docker build -t hardhack-miner .
docker run hardhack-miner
```

## Deployment to Koyeb
1. Connect this GitHub repo to Koyeb.
2. Port: `8000`.
3. The container will automatically use CPU fallback if Tenstorrent hardware is not detected, allowing you to test the agent logic in the cloud.

## Competition Specs
- **Matrix A**: $16 \times 50240$ (Int8)
- **Matrix B**: $50240 \times 16$ (Int8)
- **Target**: $>200,000$ solved matrices per second.