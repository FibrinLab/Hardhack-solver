# Use the Tenstorrent base image as suggested
FROM ghcr.io/tenstorrent/tt-xla/tt-xla-ird-ubuntu-22-04:latest

# Ensure we have build tools and python
USER root
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libopenblas-dev \
    libyaml-cpp-dev \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install python dependencies
RUN python3 -m pip install --ignore-installed requests flask

WORKDIR /app

# Copy project
COPY . .

# Build
RUN find /opt /usr -name host_api.hpp || true
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=ON && \
    make -j$(nproc)

# Expose port for health checks
EXPOSE 8000

# Entry point
ENTRYPOINT ["python3", "miner_agent.py"]
CMD ["--server"]