FROM ubuntu:22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install Essential Build Tools & Dependencies
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

# 3. Build the Miner and Prover (Production Release)
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=OFF -DDISABLE_AVX512=ON && \
    make -j$(nproc)

# 4. Copy and prepare the execution scripts
COPY mine.sh .
COPY prove.sh .
RUN chmod +x mine.sh prove.sh

# Set the default entry point to the Miner
# You can override this to ./prove.sh in Koyeb if needed
ENTRYPOINT ["./mine.sh"]