FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    curl \
    xxd \
    libomp-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 2. Copy source code and libraries
COPY CMakeLists.txt .
COPY include/ include/
COPY src/ src/
COPY libs/ libs/

# 3. Build optimized binaries
# ENABLE_TT=OFF for standard Linux builds
# DISABLE_AVX512=ON ensures compatibility with virtualized cloud environments
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=OFF -DDISABLE_AVX512=ON && \
    make -j$(nproc)

# 4. Final preparation
COPY mine.sh .
COPY prove.sh .
RUN chmod +x mine.sh prove.sh

# Default to mining track
ENTRYPOINT ["./mine.sh"]
