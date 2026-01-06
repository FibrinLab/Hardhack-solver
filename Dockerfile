# Use the base image suggested for Tenstorrent hardware
FROM ghcr.io/tenstorrent/tt-xla/tt-xla-ird-ubuntu-22-04:latest

USER root
ENV DEBIAN_FRONTEND=noninteractive

# Install only essential build tools and curl/openssl for the bash script
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    curl \
    openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy project
COPY . .

# Build the miner
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=ON && \
    make -j$(nproc)

# Make the bash script executable
RUN chmod +x miner.sh

# Set environment variables for Tenstorrent
ENV TT_METAL_HOME=/opt/tt-metal

# Start the bash miner
ENTRYPOINT ["./miner.sh"]