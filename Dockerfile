# Use standard Ubuntu as base since we are cloning manually
FROM ubuntu:22.04

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
    libhwloc-dev \
    && rm -rf /var/lib/apt/lists/*

# Install python dependencies for Agent AND tt-metal build
RUN python3 -m pip install --ignore-installed requests flask pyyaml mako

# Clone tt-metal recursively
RUN git clone --recursive https://github.com/tenstorrent/tt-metal.git /opt/tt-metal

# Clone ronin (contains reflect)
RUN git clone https://github.com/tenstorrent/ronin.git /opt/ronin

# Clone tt-logger
RUN git clone https://github.com/tenstorrent/tt-logger.git /opt/tt-logger

# FIX: Create symlink for <reflect> -> reflect.hpp
# The code expects <reflect> but the file is likely reflect.hpp
RUN find /opt/ronin -name reflect.hpp -exec ln -s {} /usr/include/reflect \;

# Debug: List the structure so we know where headers are
RUN ls -R /opt/tt-metal/tt_metal/include || true
RUN ls -R /opt/tt-metal/tt_stl || true

WORKDIR /app

# Copy project
COPY . .

# Build
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=ON && \
    make -j$(nproc)

# Expose port for health checks
EXPOSE 8000

# Entry point
ENTRYPOINT ["python3", "miner_agent.py"]
CMD ["--server"]