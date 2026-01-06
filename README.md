# Amadeus Hard Hack Kernel - Miner

This project is a high-performance miner designed for the **Hard Hack RISC-V Benchmarking Competition**. It implements optimized matrix multiplication and hashing workloads required for Amadeus testnet validation.

## Architecture

The miner features a **Dual-Mode Compute Abstraction**:
- **CPU Mode**: An optimized C++ Int8 kernel designed for local development, testing, and fallback.
- **Tenstorrent Mode**: A specialized backend using the `tt-metal` Host API to dispatch workloads to Tenstorrent Tensix cores (Grayskull/Wormhole).

## Prerequisites

- **CMake** (3.10+)
- **C++17** compatible compiler (Clang/GCC)
- **Git** (to pull dependencies)
- (Optional) **Tenstorrent SDK** (for accelerator support)
- (Optional) **Docker**

## Setup

1. Clone the repository and fetch submodules/libraries:
   ```bash
   git clone <repo_url>
   cd hardhack-kernel
   # Blake3 is included in libs/
   ```

## Build Instructions

### 1. Local / CPU Mode (Default)
This builds the miner using the optimized C++ CPU implementation.
```bash
mkdir -p build && cd build
cmake .. -DENABLE_TT=OFF
make -j$(nproc)
```

### 2. Tenstorrent Accelerator Mode
This requires the Tenstorrent SDK/Environment.
```bash
mkdir -p build && cd build
cmake .. -DENABLE_TT=ON
make -j$(nproc)
```

## Running the Miner

### 1. Using the Control Script (Recommended)
We provide a helper script for easy interaction.
```bash
# Start background mining loop
./control.sh start

# Run a single benchmark (1000 iterations)
./control.sh mine

# Check status
./control.sh status

# Stop mining
./control.sh stop
```

### 2. Manual Commands
You can also use `curl` or `python3` directly.

**Start Background Loop:**
```bash
curl -X POST http://localhost:8000/start
```

**Run Single Benchmark (Python one-liner):**
```bash
python3 -c "import requests; print(requests.post('http://localhost:8000/mine', json={'iterations': 1000}).text)"
```

### 3. CLI Direct Mode (Legacy)
Execute the binary directly (useful for debugging).

```bash
# Basic run (1000 iterations)
./build/hardhack_miner -n 1000

# JSON output for monitoring/automation
./build/hardhack_miner -n 100 --json

# Force CPU mode (if compiled with ENABLE_TT=ON)
./build/hardhack_miner -n 100 --cpu
```

### CLI Flags
- `-n <N>`: Number of iterations (default 1000)
- `--json`: Output metrics in JSON format
- `--cpu`: Force use of the CPU backend

## Docker Usage

The project is containerized for reproducibility, using the Tenstorrent-optimized base image.

```bash
# Build the image
docker build -t hardhack_miner .

# Run the miner
docker run --rm hardhack_miner -n 5000
```

## Workload Specification

Based on the Amadeus spec:
- **Seed**: 240-byte binary structure (Epoch, VR Hash, PK, Nonce).
- **Matrices**: Generated via Blake3 XOF.
  - Matrix A: 16 x 50,240 (Int8)
  - Matrix B: 50,240 x 16 (Int8)
- **Result**: Matrix C (16 x 16 Int32).
- **Correctness**: Validated against `seed <> result` hash with leading zero difficulty.

## Submission Rules Reminder
- **No modification** of workload shapes (16x50240, 50240x16).
- **Padding** for hardware alignment (32x32 tiles) is allowed.
- **Caching** of inputs is allowed.
- **Target Performance**: ~200k-300k solves per second.
