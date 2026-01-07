# Use official Tenstorrent release image
FROM ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-amd64:latest-rc

USER root
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install dependencies
RUN apt-get update && apt-get install -y \
    curl xxd libomp-dev git cmake build-essential \
    && rm -rf /var/lib/apt/lists/*

# 2. BRUTE FORCE HEADERS:
# The images are missing headers, so we clone them to a local path
RUN git clone --depth 1 https://github.com/tenstorrent/tt-metal.git /tmp/tt-metal-src

# 3. Create a clean unified include directory
RUN mkdir -p /app/tt_headers && \
    cp -r /tmp/tt-metal-src/tt_metal/include/* /app/tt_headers/ 2>/dev/null || true && \
    cp -r /tmp/tt-metal-src/tt_metal/api/* /app/tt_headers/ 2>/dev/null || true && \
    cp -r /tmp/tt-metal-src/tt_metal/hostdevcommon/api/* /app/tt_headers/ 2>/dev/null || true && \
    cp -r /tmp/tt-metal-src/tt_stl/* /app/tt_headers/ 2>/dev/null || true

WORKDIR /app

# 4. Build binaries
COPY . .
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release \
             -DENABLE_TT=ON \
             -DDISABLE_AVX512=ON \
             -DTT_HEADER_DIR=/app/tt_headers && \
    make -j$(nproc)

# 5. Execution
RUN chmod +x mine.sh prove.sh
ENTRYPOINT ["./mine.sh"]