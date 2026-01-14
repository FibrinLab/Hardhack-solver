# syntax=docker/dockerfile:1
ARG TT_METAL_IMAGE=ubuntu:22.04
FROM ${TT_METAL_IMAGE}

USER root
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    xxd \
    libomp-dev \
    libfmt-dev \
    nlohmann-json3-dev \
    libhwloc-dev \
    libboost-all-dev \
    libyaml-cpp-dev \
    pkg-config \
    clang \
    libtbb-dev \
    libcapstone-dev \
    wget \
    unzip \
    zstd \
    udev \
    gcc-12 \
    g++-12 \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --upgrade pip \
    && pip3 install cmake ninja

ENV CC=gcc-12
ENV CXX=g++-12

ENV TT_METAL_HOME=/opt/tt-metal
ENV LD_LIBRARY_PATH=/opt/tt-metal/lib:/opt/tt-metal/build/lib:/usr/local/lib

ARG TT_METAL_REPO=https://github.com/tenstorrent/tt-metal.git

RUN set -eux; \
    if [ ! -f "$TT_METAL_HOME/tt_metal/api/tt-metalium/host_api.hpp" ]; then \
        git clone --recurse-submodules --shallow-submodules "$TT_METAL_REPO" "$TT_METAL_HOME"; \
        cd "$TT_METAL_HOME"; \
        cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release; \
        cmake --build build; \
    fi; \
    fmt_dir="$(find /usr/include -type d -name fmt -print -quit)"; \
    if [ -n "$fmt_dir" ] && [ ! -f "$fmt_dir/base.h" ]; then \
        printf '%s\n' '#pragma once' '#include "format.h"' '#include "core.h"' > "$fmt_dir/base.h"; \
    fi

WORKDIR /app

COPY . .

RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=ON -DDISABLE_AVX512=ON \
    && cmake --build build -j"$(nproc)"

RUN chmod +x mine.sh merkle_prove.sh

ENTRYPOINT ["./mine.sh"]
