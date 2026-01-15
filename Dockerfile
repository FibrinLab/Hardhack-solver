# syntax=docker/dockerfile:1
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    curl \
    xxd \
    libomp-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

# Build without TT acceleration (CPU-only mode for now)
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=OFF \
    && cmake --build build -j"$(nproc)"

RUN chmod +x mine.sh merkle_prove.sh

ENTRYPOINT ["./mine.sh"]
