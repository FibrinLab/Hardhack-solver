# Use the official Tenstorrent Metalium release image
FROM ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-amd64:latest-rc

# Ensure we have build tools and python
USER root
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libopenblas-dev \
    libyaml-cpp-dev \
    nlohmann-json3-dev \
    libfmt-dev \
    libspdlog-dev \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install python dependencies
RUN python3 -m pip install --ignore-installed requests flask

# Clone tt-metal to ensure we have headers (recursive for submodules)
RUN git clone --depth 1 --recursive https://github.com/tenstorrent/tt-metal.git /opt/tt-metal

WORKDIR /app

# Copy project
COPY . .

# Build
RUN find /opt -name reflect || true
RUN find /opt -name reflect.hpp || true
# Hack: Link reflect.hpp to reflect if needed
RUN find /opt -name reflect.hpp -exec ln -s {} /usr/include/reflect \; || true

RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=ON && \
    make -j$(nproc)

# Expose port for health checks
EXPOSE 8000

# Entry point
ENTRYPOINT ["python3", "miner_agent.py"]
CMD ["--server"]