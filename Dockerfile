# Production Tenstorrent Base Image
FROM ghcr.io/tenstorrent/tt-xla/tt-xla-ird-ubuntu-22-04:latest

USER root
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies (This layer is cached)
RUN apt-get update && apt-get install -y \
    build-essential cmake git curl openssl libomp-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Step 1: Copy ONLY source code and build (This layer is cached unless C++ code changes)
COPY CMakeLists.txt .
COPY include/ include/
COPY src/ src/
COPY libs/ libs/
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=ON && \
    make -j$(nproc)

# Step 2: Copy the agent script (This is the only part that re-runs when you edit the script!)
COPY testnet_agent.sh .
RUN chmod +x testnet_agent.sh

ENV TT_METAL_HOME=/opt/tt-metal
ENTRYPOINT ["./testnet_agent.sh"]