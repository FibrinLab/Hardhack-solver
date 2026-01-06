# Production Tenstorrent Base Image
FROM ghcr.io/tenstorrent/tt-xla/tt-xla-ird-ubuntu-22-04:latest

USER root
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential cmake git curl openssl libomp-dev \
    && rm -rf /var/lib/apt/lists/*

# Clone headers (depth 1 for speed)
RUN git clone --depth 1 https://github.com/tenstorrent/tt-metal.git /opt/tt-metal

# --- Unified Include Hack ---
# This ensures all scattered Tenstorrent headers are found by the compiler
RUN mkdir -p /app/unified_include && \
    cp -r /opt/tt-metal/tt_metal/include/* /app/unified_include/ 2>/dev/null || true && \
    cp -r /opt/tt-metal/tt_metal/api/* /app/unified_include/ 2>/dev/null || true && \
    cp -r /opt/tt-metal/tt_metal/hostdevcommon/api/* /app/unified_include/ 2>/dev/null || true && \
    cp -r /opt/tt-metal/tt_stl/* /app/unified_include/ 2>/dev/null || true

WORKDIR /app

# Step 1: Build C++ Binaries
COPY CMakeLists.txt .
COPY include/ include/
COPY src/ src/
COPY libs/ libs/
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=ON -DDISABLE_AVX512=ON && \
    make -j$(nproc)

# Step 2: Copy Agent
COPY testnet_agent.sh .
RUN chmod +x testnet_agent.sh

ENV TT_METAL_HOME=/opt/tt-metal
ENTRYPOINT ["./testnet_agent.sh"]