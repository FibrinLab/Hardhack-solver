# Use the Tenstorrent base image as suggested
FROM ghcr.io/tenstorrent/tt-xla/tt-xla-ird-ubuntu-22-04:latest

# Ensure we have build tools
USER root
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy project
COPY . .

# Build
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc)

# Entry point
ENTRYPOINT ["./build/hardhack_miner"]
CMD ["-n", "1000"]