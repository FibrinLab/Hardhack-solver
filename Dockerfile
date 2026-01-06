# Production Tenstorrent Base Image
FROM ghcr.io/tenstorrent/tt-xla/tt-xla-ird-ubuntu-22-04:latest

USER root
ENV DEBIAN_FRONTEND=noninteractive

# Install curl for API communication
RUN apt-get update && apt-get install -y \
    build-essential cmake git curl openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

# Build high-performance binary
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=ON && \
    make -j$(nproc)

RUN chmod +x testnet_agent.sh

ENV TT_METAL_HOME=/opt/tt-metal
ENTRYPOINT ["./testnet_agent.sh"]
