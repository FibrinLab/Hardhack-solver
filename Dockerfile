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
    libspdlog-dev \
    gcc-12 \
    g++-12 \
    python3 \
    python3-pip \
    libhwloc-dev \
    && rm -rf /var/lib/apt/lists/*

# Set GCC 12 as default
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100 --slave /usr/bin/g++ g++ /usr/bin/g++-12

# Install python dependencies for Agent AND tt-metal build
RUN python3 -m pip install --ignore-installed requests flask pyyaml mako

# Clone tt-metal recursively
RUN git clone --recursive https://github.com/tenstorrent/tt-metal.git /opt/tt-metal

# Clone ronin (contains reflect)
RUN git clone https://github.com/tenstorrent/ronin.git /opt/ronin

# Clone tt-logger
RUN git clone https://github.com/tenstorrent/tt-logger.git /opt/tt-logger

# Clone enchantum bridge search (from before)
RUN find /opt -name xy_pair.hpp || true

# Clone tt-umd
RUN git clone https://github.com/tenstorrent/tt-umd.git /opt/tt-umd
RUN find /opt/tt-umd -name xy_pair.hpp || true
RUN find /opt/tt-metal -name common_values.hpp || true

# Clone tt-umd
RUN git clone --depth 1 --branch 11.0.2 https://github.com/fmtlib/fmt.git /opt/fmt
RUN ls -R /opt/fmt/include

# Unified Include Directory hack
RUN mkdir -p /app/unified_include
RUN cp -r /opt/tt-metal/tt_metal/api/* /app/unified_include/ || true
RUN cp -r /opt/tt-metal/tt_metal/include/* /app/unified_include/ || true
RUN cp -r /opt/tt-metal/tt_stl/* /app/unified_include/ || true
# tt-logger needs to maintain its directory name
RUN find /opt/tt-logger -name tt-logger.hpp -exec dirname {} \; | xargs -I {} cp -r {} /app/unified_include/
# enchantum bridge
RUN mkdir -p /app/unified_include/enchantum
RUN cp /opt/tt-metal/tt-train/sources/ttml/core/scoped.hpp /app/unified_include/enchantum/
# tt-umd bridge
RUN mkdir -p /app/unified_include
RUN cp -r /opt/tt-umd/device/api/umd /app/unified_include/ || true
RUN cp -r /opt/tt-umd/common/api/umd /app/unified_include/ || true
# hostdevcommon bridge
RUN cp -r /opt/tt-metal/tt_metal/hostdevcommon/api/hostdevcommon /app/unified_include/ || true
RUN cp -r /opt/ronin/jitte/src/tt_metal/tt_stl/reflect /app/unified_include/ || true
RUN cp -r /opt/fmt/include/fmt /app/unified_include/ || true

# Debug: Where is base.h?
RUN echo "FORCE RUN 1" && find /app/unified_include -name base.h

# Forwarder hacks
RUN printf "#pragma once\n#include \"reflect/reflect.hpp\"\n" > /app/unified_include/reflect

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