# Use the Tenstorrent Wormhole image (N300S is Wormhole-based)
FROM ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-amd64:latest-rc

USER root
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install runtime dependencies
RUN apt-get update && apt-get install -y \
    curl xxd libomp-dev git cmake build-essential \
    python3 python3-pip \
    nlohmann-json3-dev libfmt-dev \
    && rm -rf /var/lib/apt/lists/* && \
    # Check fmt installation and create base.h if needed
    FMT_DIR=$(find /usr/include -type d -name "fmt" 2>/dev/null | head -1) && \
    if [ -n "$FMT_DIR" ]; then \
        echo "Found fmt at: $FMT_DIR" && \
        ls -la "$FMT_DIR" | head -10; \
        if [ ! -f "$FMT_DIR/base.h" ]; then \
            echo "Creating fmt/base.h wrapper..." && \
            echo '#pragma once' > "$FMT_DIR/base.h" && \
            echo '#include "format.h"' >> "$FMT_DIR/base.h" && \
            echo '#include "core.h"' >> "$FMT_DIR/base.h" 2>/dev/null || true; \
        fi; \
    fi

WORKDIR /app

# 2. Clone tt-metal headers (base image doesn't include dev headers)
RUN git clone --depth 1 https://github.com/tenstorrent/tt-metal.git /tmp/tt-metal-src && \
    mkdir -p /opt/tt-metal/tt_metal && \
    cp -r /tmp/tt-metal-src/tt_metal/include /opt/tt-metal/tt_metal/ 2>/dev/null || true && \
    cp -r /tmp/tt-metal-src/tt_metal/api /opt/tt-metal/tt_metal/ 2>/dev/null || true && \
    cp -r /tmp/tt-metal-src/tt_metal/hostdevcommon /opt/tt-metal/tt_metal/ 2>/dev/null || true && \
    cp -r /tmp/tt-metal-src/tt_stl/tt_stl /opt/tt-metal/tt_stl 2>/dev/null || true && \
    rm -rf /tmp/tt-metal-src

# 2a. Clone with submodules and copy dependencies
RUN git clone --depth 1 --recurse-submodules https://github.com/tenstorrent/tt-metal.git /tmp/tt-metal-src && \
    sleep 5 && \
    if [ -d /tmp/tt-metal-src/tt_metal/hostdevcommon ]; then \
        cp -r /tmp/tt-metal-src/tt_metal/hostdevcommon /opt/tt-metal/ && \
        echo "hostdevcommon copied to root level"; \
    fi && \
    mkdir -p /opt/tt-metal/hostdevcommon && \
    for stub_file in common_values.hpp kernel_structs.h; do \
        if [ ! -f /opt/tt-metal/hostdevcommon/$stub_file ]; then \
            echo '#pragma once' > /opt/tt-metal/hostdevcommon/$stub_file && \
            echo "// Stub for $stub_file" >> /opt/tt-metal/hostdevcommon/$stub_file; \
        fi; \
    done

# 2b. Copy umd and create stubs
RUN if [ -d /tmp/tt-metal-src/tt_metal/third_party/umd ] && [ -n "$(ls -A /tmp/tt-metal-src/tt_metal/third_party/umd 2>/dev/null)" ]; then \
        cp -r /tmp/tt-metal-src/tt_metal/third_party/umd /opt/tt-metal/ && \
        echo "umd copied from third_party"; \
    fi && \
    mkdir -p /opt/tt-metal/umd/device/types && \
    if [ ! -f /opt/tt-metal/umd/device/types/xy_pair.hpp ]; then \
        echo '#pragma once' > /opt/tt-metal/umd/device/types/xy_pair.hpp && \
        echo 'struct xy_pair { int x, y; xy_pair(int x_=0, int y_=0) : x(x_), y(y_) {} };' >> /opt/tt-metal/umd/device/types/xy_pair.hpp; \
    fi && \
    if [ ! -f /opt/tt-metal/umd/device/types/core_coordinates.hpp ]; then \
        echo '#pragma once' > /opt/tt-metal/umd/device/types/core_coordinates.hpp && \
        echo '#include "xy_pair.hpp"' >> /opt/tt-metal/umd/device/types/core_coordinates.hpp && \
        echo '// Stub for core_coordinates.hpp' >> /opt/tt-metal/umd/device/types/core_coordinates.hpp; \
    fi && \
    for stub in soc_descriptor.hpp arch.hpp device_types.hpp cluster_descriptor_types.hpp; do \
        if [ ! -f /opt/tt-metal/umd/device/types/$stub ]; then \
            echo '#pragma once' > /opt/tt-metal/umd/device/types/$stub && \
            echo "// Stub for $stub" >> /opt/tt-metal/umd/device/types/$stub; \
        fi; \
    done && \
    if [ -f /opt/tt-metal/umd/device/types/core_coordinates.hpp ]; then \
        if ! grep -q "CoreCoord" /opt/tt-metal/umd/device/types/core_coordinates.hpp; then \
            echo '' >> /opt/tt-metal/umd/device/types/core_coordinates.hpp && \
            echo 'using CoreCoord = xy_pair;' >> /opt/tt-metal/umd/device/types/core_coordinates.hpp; \
        fi; \
    fi && \
    if [ ! -f /opt/tt-metal/umd/device/types/core_coord.hpp ]; then \
        echo '#pragma once' > /opt/tt-metal/umd/device/types/core_coord.hpp && \
        echo '#include "xy_pair.hpp"' >> /opt/tt-metal/umd/device/types/core_coord.hpp && \
        echo 'using CoreCoord = xy_pair;' >> /opt/tt-metal/umd/device/types/core_coord.hpp; \
    fi && \
    if [ ! -f /opt/tt-metal/umd/device/soc_descriptor.hpp ]; then \
        echo '#pragma once' > /opt/tt-metal/umd/device/soc_descriptor.hpp && \
        echo '// Stub for soc_descriptor.hpp' >> /opt/tt-metal/umd/device/soc_descriptor.hpp; \
    fi

# 2c. Create core_type.hpp and related stubs
RUN mkdir -p /opt/tt-metal/tt_metal/api/tt-metalium && \
    if [ ! -f /opt/tt-metal/tt_metal/api/tt-metalium/core_coord_fwd.hpp ]; then \
        echo '#pragma once' > /opt/tt-metal/tt_metal/api/tt-metalium/core_coord_fwd.hpp && \
        echo '#include <umd/device/types/core_coordinates.hpp>' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_coord_fwd.hpp && \
        echo '// Forward declaration for CoreCoord' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_coord_fwd.hpp; \
    fi && \
    if [ ! -f /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp ]; then \
        echo '#pragma once' > /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '#include <umd/device/types/core_coordinates.hpp>' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo 'namespace tt {' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo 'namespace tt_metal {' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '    enum class CoreType {' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '        WORKER,' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '        ETHERNET,' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '        ETH' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '    };' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '    using ChipId = int;' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '    enum class ARCH { WORMHOLE, WORMHOLE_B0, GRAYSKULL, BLACKHOLE };' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '    struct DispatchCoreConfig {};' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '    constexpr size_t DEFAULT_L1_SMALL_SIZE = 32768;' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '    constexpr size_t DEFAULT_TRACE_REGION_SIZE = 1048576;' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '    constexpr size_t DEFAULT_WORKER_L1_SIZE = 98304;' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '    using CoreCoord = umd::device::types::CoreCoord;' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '}' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp && \
        echo '}' >> /opt/tt-metal/tt_metal/api/tt-metalium/core_type.hpp; \
    fi

# 2d. Copy enchantum
RUN if [ -d /tmp/tt-metal-src/enchantum ]; then \
        cp -r /tmp/tt-metal-src/enchantum /opt/tt-metal/ 2>/dev/null || true && \
        echo "Enchantum copied from repo"; \
    else \
        echo "Enchantum still not found, trying direct clone..." && \
        mkdir -p /opt/tt-metal/enchantum && \
        (git clone --depth 1 https://github.com/tenstorrent/enchantum.git /tmp/enchantum-tmp 2>&1 && \
         cp -r /tmp/enchantum-tmp/* /opt/tt-metal/enchantum/ 2>/dev/null && \
         rm -rf /tmp/enchantum-tmp && \
         echo "Enchantum cloned successfully" || \
         (git clone --depth 1 https://github.com/tenstorrent-ai/enchantum.git /tmp/enchantum-tmp 2>&1 && \
          cp -r /tmp/enchantum-tmp/* /opt/tt-metal/enchantum/ 2>/dev/null && \
          rm -rf /tmp/enchantum-tmp && \
          echo "Enchantum cloned from tenstorrent-ai" || \
          echo "Enchantum clone failed - creating stub header")) && \
        if [ -d /opt/tt-metal/enchantum ]; then \
            if [ ! -f /opt/tt-metal/enchantum/scoped.hpp ] && [ ! -d /opt/tt-metal/enchantum/enchantum ]; then \
                echo "Creating stub scoped.hpp..." && \
                mkdir -p /opt/tt-metal/enchantum && \
                echo '#pragma once' > /opt/tt-metal/enchantum/scoped.hpp && \
                echo '// Stub header for enchantum/scoped.hpp' >> /opt/tt-metal/enchantum/scoped.hpp; \
            fi; \
        fi; \
    fi && \
    if [ -f /opt/tt-metal/tt_stl/reflection.hpp ]; then \
        echo '#include "reflection.hpp"' > /opt/tt-metal/tt_stl/reflect; \
    fi

# 2e. Create logger and hash stubs
RUN if [ ! -f /opt/tt-metal/tt_stl/logger.hpp ]; then \
        echo '#pragma once' > /opt/tt-metal/tt_stl/logger.hpp && \
        echo '#include <iostream>' >> /opt/tt-metal/tt_stl/logger.hpp && \
        echo 'namespace tt {' >> /opt/tt-metal/tt_stl/logger.hpp && \
        echo '    enum LogLevel { LogAlways };' >> /opt/tt-metal/tt_stl/logger.hpp && \
        echo '    template<typename... Args>' >> /opt/tt-metal/tt_stl/logger.hpp && \
        echo '    void log_critical(LogLevel, const std::string& msg, Args&&...) {' >> /opt/tt-metal/tt_stl/logger.hpp && \
        echo '        std::cerr << "[CRITICAL] " << msg << std::endl;' >> /opt/tt-metal/tt_stl/logger.hpp && \
        echo '    }' >> /opt/tt-metal/tt_stl/logger.hpp && \
        echo '}' >> /opt/tt-metal/tt_stl/logger.hpp; \
    fi && \
    if [ ! -f /opt/tt-metal/tt_stl/hash.hpp ]; then \
        echo '#pragma once' > /opt/tt-metal/tt_stl/hash.hpp && \
        echo '#include <cstdint>' >> /opt/tt-metal/tt_stl/hash.hpp && \
        echo 'namespace tt {' >> /opt/tt-metal/tt_stl/hash.hpp && \
        echo 'namespace ttsl {' >> /opt/tt-metal/tt_stl/hash.hpp && \
        echo 'namespace hash {' >> /opt/tt-metal/tt_stl/hash.hpp && \
        echo '    using hash_t = uint64_t;' >> /opt/tt-metal/tt_stl/hash.hpp && \
        echo '}' >> /opt/tt-metal/tt_stl/hash.hpp && \
        echo '}' >> /opt/tt-metal/tt_stl/hash.hpp && \
        echo '}' >> /opt/tt-metal/tt_stl/hash.hpp; \
    fi

# 2f. Patch assert.hpp
RUN if [ -f /opt/tt-metal/tt_stl/assert.hpp ]; then \
        echo 'file_path = "/opt/tt-metal/tt_stl/assert.hpp"' > /tmp/patch_assert.py && \
        echo 'try:' >> /tmp/patch_assert.py && \
        echo '    with open(file_path, "r") as f:' >> /tmp/patch_assert.py && \
        echo '        content = f.read()' >> /tmp/patch_assert.py && \
        echo '    if "#include <tt_stl/logger.hpp>" not in content and "#include \\"tt_stl/logger.hpp\\"" not in content:' >> /tmp/patch_assert.py && \
        echo '        lines = content.split("\\n")' >> /tmp/patch_assert.py && \
        echo '        insert_idx = 0' >> /tmp/patch_assert.py && \
        echo '        for i, line in enumerate(lines):' >> /tmp/patch_assert.py && \
        echo '            if line.strip().startswith("#include") or line.strip().startswith("#pragma"):' >> /tmp/patch_assert.py && \
        echo '                insert_idx = i + 1' >> /tmp/patch_assert.py && \
        echo '                break' >> /tmp/patch_assert.py && \
        echo '        lines.insert(insert_idx, "#include <tt_stl/logger.hpp>")' >> /tmp/patch_assert.py && \
        echo '        content = "\\n".join(lines)' >> /tmp/patch_assert.py && \
        echo '        with open(file_path, "w") as f:' >> /tmp/patch_assert.py && \
        echo '            f.write(content)' >> /tmp/patch_assert.py && \
        echo '        print("Added logger.hpp include to assert.hpp")' >> /tmp/patch_assert.py && \
        echo '    else:' >> /tmp/patch_assert.py && \
        echo '        print("logger.hpp already included in assert.hpp")' >> /tmp/patch_assert.py && \
        echo 'except Exception as e:' >> /tmp/patch_assert.py && \
        echo '    print("Error patching assert.hpp: {}".format(e))' >> /tmp/patch_assert.py && \
        python3 /tmp/patch_assert.py; \
    fi

# 2g. Patch program_descriptors.hpp
RUN if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/program_descriptors.hpp ]; then \
        echo 'file_path = "/opt/tt-metal/tt_metal/api/tt-metalium/program_descriptors.hpp"' > /tmp/patch_program_desc.py && \
        echo 'try:' >> /tmp/patch_program_desc.py && \
        echo '    with open(file_path, "r") as f:' >> /tmp/patch_program_desc.py && \
        echo '        content = f.read()' >> /tmp/patch_program_desc.py && \
        echo '    if "#include <tt_stl/hash.hpp>" not in content and "#include \\"tt_stl/hash.hpp\\"" not in content:' >> /tmp/patch_program_desc.py && \
        echo '        lines = content.split("\\n")' >> /tmp/patch_program_desc.py && \
        echo '        insert_idx = 0' >> /tmp/patch_program_desc.py && \
        echo '        for i, line in enumerate(lines):' >> /tmp/patch_program_desc.py && \
        echo '            if line.strip().startswith("#include") or line.strip().startswith("#pragma"):' >> /tmp/patch_program_desc.py && \
        echo '                insert_idx = i + 1' >> /tmp/patch_program_desc.py && \
        echo '                break' >> /tmp/patch_program_desc.py && \
        echo '        lines.insert(insert_idx, "#include <tt_stl/hash.hpp>")' >> /tmp/patch_program_desc.py && \
        echo '        content = "\\n".join(lines)' >> /tmp/patch_program_desc.py && \
        echo '        with open(file_path, "w") as f:' >> /tmp/patch_program_desc.py && \
        echo '            f.write(content)' >> /tmp/patch_program_desc.py && \
        echo '        print("Added hash.hpp include to program_descriptors.hpp")' >> /tmp/patch_program_desc.py && \
        echo '    lines = content.split("\\n")' >> /tmp/patch_program_desc.py && \
        echo '    ns_idx = -1' >> /tmp/patch_program_desc.py && \
        echo '    for i, line in enumerate(lines):' >> /tmp/patch_program_desc.py && \
        echo '        if "namespace" in line and "tt_metal" in line:' >> /tmp/patch_program_desc.py && \
        echo '            ns_idx = i' >> /tmp/patch_program_desc.py && \
        echo '            break' >> /tmp/patch_program_desc.py && \
        echo '    has_kernel_descs = "using KernelDescriptors" in content' >> /tmp/patch_program_desc.py && \
        echo '    if ns_idx >= 0 and not has_kernel_descs:' >> /tmp/patch_program_desc.py && \
        echo '        desc_lines = ["    using KernelDescriptors = std::vector<KernelDescriptor>;", "    using SemaphoreDescriptors = std::vector<SemaphoreDescriptor>;", "    using CBDescriptors = std::vector<CBDescriptor>;"]' >> /tmp/patch_program_desc.py && \
        echo '        for i, desc_line in enumerate(desc_lines):' >> /tmp/patch_program_desc.py && \
        echo '            lines.insert(ns_idx + 1 + i, desc_line)' >> /tmp/patch_program_desc.py && \
        echo '        content = "\\n".join(lines)' >> /tmp/patch_program_desc.py && \
        echo '        print("Added descriptor using declarations")' >> /tmp/patch_program_desc.py && \
        echo '    if "ttsl::SmallVector" in content:' >> /tmp/patch_program_desc.py && \
        echo '        import re' >> /tmp/patch_program_desc.py && \
        echo '        content = re.sub(r"ttsl::SmallVector<([^,>]+),\\s*\\d+>", r"std::vector<\\1>", content)' >> /tmp/patch_program_desc.py && \
        echo '        print("Replaced ttsl::SmallVector with std::vector")' >> /tmp/patch_program_desc.py && \
        echo '    if "#include <vector>" not in content:' >> /tmp/patch_program_desc.py && \
        echo '        lines = content.split("\\n")' >> /tmp/patch_program_desc.py && \
        echo '        insert_idx = 0' >> /tmp/patch_program_desc.py && \
        echo '        for i, line in enumerate(lines):' >> /tmp/patch_program_desc.py && \
        echo '            if line.strip().startswith("#include"):' >> /tmp/patch_program_desc.py && \
        echo '                insert_idx = i + 1' >> /tmp/patch_program_desc.py && \
        echo '                break' >> /tmp/patch_program_desc.py && \
        echo '        lines.insert(insert_idx, "#include <vector>")' >> /tmp/patch_program_desc.py && \
        echo '        content = "\\n".join(lines)' >> /tmp/patch_program_desc.py && \
        echo '        print("Added vector include")' >> /tmp/patch_program_desc.py && \
        echo '    with open(file_path, "w") as f:' >> /tmp/patch_program_desc.py && \
        echo '        f.write(content)' >> /tmp/patch_program_desc.py && \
        echo '    print("Updated program_descriptors.hpp")' >> /tmp/patch_program_desc.py && \
        echo 'except Exception as e:' >> /tmp/patch_program_desc.py && \
        echo '    print("Error patching program_descriptors.hpp: {}".format(e))' >> /tmp/patch_program_desc.py && \
        python3 /tmp/patch_program_desc.py; \
    fi

# 2h. Patch device.hpp and data_types.hpp
RUN for arch_file in device.hpp data_types.hpp; do \
        if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/$arch_file ]; then \
            if ! grep -q "core_type.hpp" /opt/tt-metal/tt_metal/api/tt-metalium/$arch_file; then \
                echo "file_path = '/opt/tt-metal/tt_metal/api/tt-metalium/$arch_file'" > /tmp/patch_arch.py && \
                echo 'try:' >> /tmp/patch_arch.py && \
                echo '    with open(file_path, "r") as f:' >> /tmp/patch_arch.py && \
                echo '        lines = f.readlines()' >> /tmp/patch_arch.py && \
                echo '    insert_idx = 0' >> /tmp/patch_arch.py && \
                echo '    for i, line in enumerate(lines):' >> /tmp/patch_arch.py && \
                echo '        if line.strip().startswith("#include"):' >> /tmp/patch_arch.py && \
                echo '            insert_idx = i + 1' >> /tmp/patch_arch.py && \
                echo '    lines.insert(insert_idx, "#include <tt-metalium/core_type.hpp>\\n")' >> /tmp/patch_arch.py && \
                echo '    with open(file_path, "w") as f:' >> /tmp/patch_arch.py && \
                echo '        f.writelines(lines)' >> /tmp/patch_arch.py && \
                echo '    print("Added core_type.hpp include to {}".format("'$arch_file'"))' >> /tmp/patch_arch.py && \
                echo 'except Exception as e:' >> /tmp/patch_arch.py && \
                echo '    print("Error: {}".format(e))' >> /tmp/patch_arch.py && \
                python3 /tmp/patch_arch.py; \
            fi; \
        fi; \
    done

# 2i. Patch buffer_distribution_spec.hpp
RUN if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/buffer_distribution_spec.hpp ]; then \
        sed -i '1a#include <umd/device/types/core_coordinates.hpp>' /opt/tt-metal/tt_metal/api/tt-metalium/buffer_distribution_spec.hpp 2>/dev/null || \
        sed -i '/#pragma once/a#include <umd/device/types/core_coordinates.hpp>' /opt/tt-metal/tt_metal/api/tt-metalium/buffer_distribution_spec.hpp 2>/dev/null || true; \
        sed -i 's/return cores_\.size()/return 0/g' /opt/tt-metal/tt_metal/api/tt-metalium/buffer_distribution_spec.hpp 2>/dev/null || true; \
        sed -i 's/, cores_)/, std::vector<CoreCoord>{})/g' /opt/tt-metal/tt_metal/api/tt-metalium/buffer_distribution_spec.hpp 2>/dev/null || true; \
        sed -i 's/(cores_)/(std::vector<CoreCoord>{})/g' /opt/tt-metal/tt_metal/api/tt-metalium/buffer_distribution_spec.hpp 2>/dev/null || true; \
        sed -i '/struct BufferDistributionSpec/,/{/ { /{/a\    std::vector<CoreCoord> cores_;' /opt/tt-metal/tt_metal/api/tt-metalium/buffer_distribution_spec.hpp 2>/dev/null || \
        sed -i '/class BufferDistributionSpec/,/{/ { /{/a\    std::vector<CoreCoord> cores_;' /opt/tt-metal/tt_metal/api/tt-metalium/buffer_distribution_spec.hpp 2>/dev/null || true; \
        echo "Patched buffer_distribution_spec.hpp"; \
    fi

# 2j. Patch core_coord.hpp
RUN if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/core_coord.hpp ]; then \
        echo 'file_path = "/opt/tt-metal/tt_metal/api/tt-metalium/core_coord.hpp"' > /tmp/patch_core_coord.py && \
        echo 'try:' >> /tmp/patch_core_coord.py && \
        echo '    with open(file_path, "r") as f:' >> /tmp/patch_core_coord.py && \
        echo '        lines = f.readlines()' >> /tmp/patch_core_coord.py && \
        echo '    in_disabled_block = False' >> /tmp/patch_core_coord.py && \
        echo '    brace_count = 0' >> /tmp/patch_core_coord.py && \
        echo '    new_lines = []' >> /tmp/patch_core_coord.py && \
        echo '    i = 0' >> /tmp/patch_core_coord.py && \
        echo '    while i < len(lines):' >> /tmp/patch_core_coord.py && \
        echo '        line = lines[i]' >> /tmp/patch_core_coord.py && \
        echo '        if (("namespace" in line and "ttsl" in line and "json" in line) or' >> /tmp/patch_core_coord.py && \
        echo '            ("struct formatter<tt::tt_metal::CoreCoord>" in line) or' >> /tmp/patch_core_coord.py && \
        echo '            ("template" in line and "formatter" in line and "CoreCoord" in line) or' >> /tmp/patch_core_coord.py && \
        echo '            ("auto format" in line and "CoreCoord" in line) or' >> /tmp/patch_core_coord.py && \
        echo '            (i > 0 and "template" in lines[i-1] and "formatter" in lines[i-1] and "CoreCoord" in line) or' >> /tmp/patch_core_coord.py && \
        echo '            ("struct hash<tt::tt_metal::CoreCoord>" in line) or' >> /tmp/patch_core_coord.py && \
        echo '            ("struct hash<tt::tt_metal::CoreRange>" in line) or' >> /tmp/patch_core_coord.py && \
        echo '            ("struct hash<tt::tt_metal::CoreRangeSet>" in line) or' >> /tmp/patch_core_coord.py && \
        echo '            ("namespace std" in line)):' >> /tmp/patch_core_coord.py && \
        echo '            if not in_disabled_block:' >> /tmp/patch_core_coord.py && \
        echo '                new_lines.append("#if 0  // Disabled formatter/JSON specializations\\n")' >> /tmp/patch_core_coord.py && \
        echo '            in_disabled_block = True' >> /tmp/patch_core_coord.py && \
        echo '            brace_count = line.count("{") - line.count("}")' >> /tmp/patch_core_coord.py && \
        echo '            new_lines.append(line)' >> /tmp/patch_core_coord.py && \
        echo '        elif in_disabled_block:' >> /tmp/patch_core_coord.py && \
        echo '            brace_count += line.count("{") - line.count("}")' >> /tmp/patch_core_coord.py && \
        echo '            new_lines.append(line)' >> /tmp/patch_core_coord.py && \
        echo '            if brace_count == 0:' >> /tmp/patch_core_coord.py && \
        echo '                new_lines.append("#endif  // Disabled formatter/JSON specializations\\n")' >> /tmp/patch_core_coord.py && \
        echo '                in_disabled_block = False' >> /tmp/patch_core_coord.py && \
        echo '        else:' >> /tmp/patch_core_coord.py && \
        echo '            new_lines.append(line)' >> /tmp/patch_core_coord.py && \
        echo '        i += 1' >> /tmp/patch_core_coord.py && \
        echo '    # Ensure all #if blocks are closed' >> /tmp/patch_core_coord.py && \
        echo '    if in_disabled_block:' >> /tmp/patch_core_coord.py && \
        echo '        new_lines.append("#endif  // Close unterminated block\\n")' >> /tmp/patch_core_coord.py && \
        echo '    content = "".join(new_lines)' >> /tmp/patch_core_coord.py && \
        echo '    if "#include <tt-metalium/core_type.hpp>" not in content and "#include \\"tt-metalium/core_type.hpp\\"" not in content:' >> /tmp/patch_core_coord.py && \
        echo '        lines = content.split("\\n")' >> /tmp/patch_core_coord.py && \
        echo '        insert_idx = 0' >> /tmp/patch_core_coord.py && \
        echo '        for i, line in enumerate(lines):' >> /tmp/patch_core_coord.py && \
        echo '            if line.strip().startswith("#include") or line.strip().startswith("#pragma"):' >> /tmp/patch_core_coord.py && \
        echo '                insert_idx = i + 1' >> /tmp/patch_core_coord.py && \
        echo '                break' >> /tmp/patch_core_coord.py && \
        echo '        lines.insert(insert_idx, "#include <tt-metalium/core_type.hpp>")' >> /tmp/patch_core_coord.py && \
        echo '        content = "\\n".join(lines)' >> /tmp/patch_core_coord.py && \
        echo '        print("Added include for core_type.hpp to core_coord.hpp")' >> /tmp/patch_core_coord.py && \
        echo '        new_lines = [l + "\\n" if not l.endswith("\\n") else l for l in content.split("\\n")]' >> /tmp/patch_core_coord.py && \
        echo '    with open(file_path, "w") as f:' >> /tmp/patch_core_coord.py && \
        echo '        f.writelines(new_lines)' >> /tmp/patch_core_coord.py && \
        echo '    print("Disabled ttsl::json namespace in core_coord.hpp")' >> /tmp/patch_core_coord.py && \
        echo 'except Exception as e:' >> /tmp/patch_core_coord.py && \
        echo '    print("Error: {}".format(e))' >> /tmp/patch_core_coord.py && \
        echo '    import traceback' >> /tmp/patch_core_coord.py && \
        echo '    traceback.print_exc()' >> /tmp/patch_core_coord.py && \
        python3 /tmp/patch_core_coord.py; \
    fi

# 2j1. Stub reflection.hpp to avoid C++20 consteval issues
RUN if [ -f /opt/tt-metal/tt_stl/reflection.hpp ]; then \
        echo 'file_path = "/opt/tt-metal/tt_stl/reflection.hpp"' > /tmp/patch_reflection.py && \
        echo 'try:' >> /tmp/patch_reflection.py && \
        echo '    with open(file_path, "r") as f:' >> /tmp/patch_reflection.py && \
        echo '        lines = f.readlines()' >> /tmp/patch_reflection.py && \
        echo '    new_lines = []' >> /tmp/patch_reflection.py && \
        echo '    i = 0' >> /tmp/patch_reflection.py && \
        echo '    while i < len(lines):' >> /tmp/patch_reflection.py && \
        echo '        line = lines[i]' >> /tmp/patch_reflection.py && \
        echo '        # Disable consteval functions' >> /tmp/patch_reflection.py && \
        echo '        if "consteval" in line:' >> /tmp/patch_reflection.py && \
        echo '            new_lines.append("#if 0  // Disabled consteval C++20 feature\\n")' >> /tmp/patch_reflection.py && \
        echo '            new_lines.append(line)' >> /tmp/patch_reflection.py && \
        echo '            # Find the end of the function' >> /tmp/patch_reflection.py && \
        echo '            j = i + 1' >> /tmp/patch_reflection.py && \
        echo '            while j < len(lines) and ";" not in lines[j] and ("}" not in lines[j] or lines[j].count("}") < lines[j].count("{")):' >> /tmp/patch_reflection.py && \
        echo '                new_lines.append(lines[j])' >> /tmp/patch_reflection.py && \
        echo '                j += 1' >> /tmp/patch_reflection.py && \
        echo '            if j < len(lines):' >> /tmp/patch_reflection.py && \
        echo '                new_lines.append(lines[j])' >> /tmp/patch_reflection.py && \
        echo '            new_lines.append("#endif\\n")' >> /tmp/patch_reflection.py && \
        echo '            i = j + 1' >> /tmp/patch_reflection.py && \
        echo '        # Disable to_hash and attribute_values calls' >> /tmp/patch_reflection.py && \
        echo '        elif ".to_hash" in line or ".attribute_values" in line:' >> /tmp/patch_reflection.py && \
        echo '            new_lines.append("#if 0  // Disabled C++20 reflection feature\\n")' >> /tmp/patch_reflection.py && \
        echo '            new_lines.append(line)' >> /tmp/patch_reflection.py && \
        echo '            new_lines.append("#endif\\n")' >> /tmp/patch_reflection.py && \
        echo '            i += 1' >> /tmp/patch_reflection.py && \
        echo '        elif "ttsl::concepts" in line:' >> /tmp/patch_reflection.py && \
        echo '            new_lines.append("#if 0  // Disabled concepts\\n")' >> /tmp/patch_reflection.py && \
        echo '            new_lines.append(line)' >> /tmp/patch_reflection.py && \
        echo '            if i + 1 < len(lines):' >> /tmp/patch_reflection.py && \
        echo '                new_lines.append(lines[i + 1])' >> /tmp/patch_reflection.py && \
        echo '            new_lines.append("#endif\\n")' >> /tmp/patch_reflection.py && \
        echo '            i += 2' >> /tmp/patch_reflection.py && \
        echo '        else:' >> /tmp/patch_reflection.py && \
        echo '            new_lines.append(line)' >> /tmp/patch_reflection.py && \
        echo '            i += 1' >> /tmp/patch_reflection.py && \
        echo '    with open(file_path, "w") as f:' >> /tmp/patch_reflection.py && \
        echo '        f.writelines(new_lines)' >> /tmp/patch_reflection.py && \
        echo '    print("Patched reflection.hpp to disable C++20 features")' >> /tmp/patch_reflection.py && \
        echo 'except Exception as e:' >> /tmp/patch_reflection.py && \
        echo '    print("Error: {}".format(e))' >> /tmp/patch_reflection.py && \
        echo '    import traceback' >> /tmp/patch_reflection.py && \
        echo '    traceback.print_exc()' >> /tmp/patch_reflection.py && \
        python3 /tmp/patch_reflection.py; \
    fi

# 2k. Patch tt_backend_api_types.hpp
RUN if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/tt_backend_api_types.hpp ]; then \
        echo 'file_path = "/opt/tt-metal/tt_metal/api/tt-metalium/tt_backend_api_types.hpp"' > /tmp/patch_backend_types.py && \
        echo 'try:' >> /tmp/patch_backend_types.py && \
        echo '    with open(file_path, "r") as f:' >> /tmp/patch_backend_types.py && \
        echo '        lines = f.readlines()' >> /tmp/patch_backend_types.py && \
        echo '    new_lines = []' >> /tmp/patch_backend_types.py && \
        echo '    i = 0' >> /tmp/patch_backend_types.py && \
        echo '    in_hash_specialization = False' >> /tmp/patch_backend_types.py && \
        echo '    brace_count = 0' >> /tmp/patch_backend_types.py && \
        echo '    while i < len(lines):' >> /tmp/patch_backend_types.py && \
        echo '        line = lines[i]' >> /tmp/patch_backend_types.py && \
        echo '        if (("std::size_t operator()" in line and "DataFormat" in line) or' >> /tmp/patch_backend_types.py && \
        echo '           ("struct hash<tt::DataFormat>" in line) or' >> /tmp/patch_backend_types.py && \
        echo '           ("template" in line and i < len(lines) - 2 and ("hash<tt::DataFormat>" in lines[i+1] or "hash<tt::DataFormat>" in lines[i+2]))):' >> /tmp/patch_backend_types.py && \
        echo '            if not in_hash_specialization:' >> /tmp/patch_backend_types.py && \
        echo '                new_lines.append("#if 0  // Disabled hash specialization\\n")' >> /tmp/patch_backend_types.py && \
        echo '            in_hash_specialization = True' >> /tmp/patch_backend_types.py && \
        echo '            brace_count = line.count("{") - line.count("}")' >> /tmp/patch_backend_types.py && \
        echo '            new_lines.append(line)' >> /tmp/patch_backend_types.py && \
        echo '        elif in_hash_specialization:' >> /tmp/patch_backend_types.py && \
        echo '            brace_count += line.count("{") - line.count("}")' >> /tmp/patch_backend_types.py && \
        echo '            new_lines.append(line)' >> /tmp/patch_backend_types.py && \
        echo '            if brace_count == 0:' >> /tmp/patch_backend_types.py && \
        echo '                new_lines.append("#endif  // Disabled hash specialization\\n")' >> /tmp/patch_backend_types.py && \
        echo '                in_hash_specialization = False' >> /tmp/patch_backend_types.py && \
        echo '        else:' >> /tmp/patch_backend_types.py && \
        echo '            new_lines.append(line)' >> /tmp/patch_backend_types.py && \
        echo '        i += 1' >> /tmp/patch_backend_types.py && \
        echo '    with open(file_path, "w") as f:' >> /tmp/patch_backend_types.py && \
        echo '        f.writelines(new_lines)' >> /tmp/patch_backend_types.py && \
        echo '    print("Patched tt_backend_api_types.hpp")' >> /tmp/patch_backend_types.py && \
        echo 'except Exception as e:' >> /tmp/patch_backend_types.py && \
        echo '    print("Error: {}".format(e))' >> /tmp/patch_backend_types.py && \
        python3 /tmp/patch_backend_types.py; \
    fi

# 2l. Create span.hpp stub
RUN rm -f /opt/tt-metal/tt_stl/span.hpp && \
    if [ ! -f /opt/tt-metal/tt_stl/span.hpp ]; then \
        echo '#pragma once' > /opt/tt-metal/tt_stl/span.hpp && \
        echo '#include <cstddef>' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '#include <vector>' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '#include <array>' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '// Custom span implementation for C++17 compatibility' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo 'namespace tt {' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo 'namespace ttsl {' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '    constexpr std::size_t dynamic_extent = static_cast<std::size_t>(-1);' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '    template<typename T, std::size_t Extent = dynamic_extent>' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '    class Span {' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '    public:' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        using element_type = const T;' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        using value_type = T;' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        using size_type = std::size_t;' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        using difference_type = std::ptrdiff_t;' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        using pointer = const T*;' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        using const_pointer = const T*;' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        using reference = const T&;' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        using const_reference = const T&;' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        constexpr Span() noexcept : data_(nullptr), size_(0) {}' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        constexpr Span(const T* ptr, size_type count) : data_(ptr), size_(count) {}' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        template<std::size_t N> constexpr Span(const T (&arr)[N]) : data_(arr), size_(N) {}' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        template<class Container> constexpr Span(const Container& c) : data_(c.data()), size_(c.size()) {}' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        constexpr const T* data() const noexcept { return data_; }' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        constexpr size_type size() const noexcept { return size_; }' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        constexpr bool empty() const noexcept { return size_ == 0; }' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        constexpr const T& operator[](size_type idx) const { return data_[idx]; }' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        constexpr const T* begin() const noexcept { return data_; }' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        constexpr const T* end() const noexcept { return data_ + size_; }' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '    private:' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        const T* data_;' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '        size_type size_;' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '    };' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '    template<typename T>' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '    auto make_span(const std::vector<T>& vec) { return Span<T>(vec.data(), vec.size()); }' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '}' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo 'namespace [[deprecated("Use ttsl namespace instead")]] stl {' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '    template<typename T, std::size_t Extent = ttsl::dynamic_extent>' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '    using Span = ttsl::Span<T, Extent>;' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '}' >> /opt/tt-metal/tt_stl/span.hpp && \
        echo '}' >> /opt/tt-metal/tt_stl/span.hpp; \
    fi && \
    mkdir -p /opt/tt-metal/tt_metal/api/tt-metalium && \
    if [ ! -f /opt/tt-metal/tt_metal/api/tt-metalium/stl_forward.hpp ]; then \
        echo '#pragma once' > /opt/tt-metal/tt_metal/api/tt-metalium/stl_forward.hpp && \
        echo '#include <tt_stl/span.hpp>' >> /opt/tt-metal/tt_metal/api/tt-metalium/stl_forward.hpp && \
        echo 'namespace tt {' >> /opt/tt-metal/tt_metal/api/tt-metalium/stl_forward.hpp && \
        echo 'namespace tt_metal {' >> /opt/tt-metal/tt_metal/api/tt-metalium/stl_forward.hpp && \
        echo '    using stl::Span;' >> /opt/tt-metal/tt_metal/api/tt-metalium/stl_forward.hpp && \
        echo '}' >> /opt/tt-metal/tt_metal/api/tt-metalium/stl_forward.hpp && \
        echo '}' >> /opt/tt-metal/tt_metal/api/tt-metalium/stl_forward.hpp; \
    fi

# 2m. Patch host_api.hpp
RUN if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/host_api.hpp ]; then \
        echo 'import re' > /tmp/patch_host_api.py && \
        echo 'file_path = "/opt/tt-metal/tt_metal/api/tt-metalium/host_api.hpp"' >> /tmp/patch_host_api.py && \
        echo 'try:' >> /tmp/patch_host_api.py && \
        echo '    with open(file_path, "r") as f:' >> /tmp/patch_host_api.py && \
        echo '        content = f.read()' >> /tmp/patch_host_api.py && \
        echo '    original_content = content' >> /tmp/patch_host_api.py && \
        echo '    if "#include <tt_stl/span.hpp>" not in content and "#include \\"tt_stl/span.hpp\\"" not in content:' >> /tmp/patch_host_api.py && \
        echo '        lines = content.split("\\n")' >> /tmp/patch_host_api.py && \
        echo '        insert_idx = 0' >> /tmp/patch_host_api.py && \
        echo '        for i, line in enumerate(lines):' >> /tmp/patch_host_api.py && \
        echo '            if line.strip().startswith("#include") or line.strip().startswith("#pragma"):' >> /tmp/patch_host_api.py && \
        echo '                insert_idx = i + 1' >> /tmp/patch_host_api.py && \
        echo '                break' >> /tmp/patch_host_api.py && \
        echo '        lines.insert(insert_idx, "#include <tt_stl/span.hpp>")' >> /tmp/patch_host_api.py && \
        echo '        content = "\\n".join(lines)' >> /tmp/patch_host_api.py && \
        echo '        print("Added include for tt_stl/span.hpp at top")' >> /tmp/patch_host_api.py && \
        echo '    if "#include <tt-metalium/core_type.hpp>" not in content and "#include \\"tt-metalium/core_type.hpp\\"" not in content:' >> /tmp/patch_host_api.py && \
        echo '        lines = content.split("\\n")' >> /tmp/patch_host_api.py && \
        echo '        insert_idx = 0' >> /tmp/patch_host_api.py && \
        echo '        for i, line in enumerate(lines):' >> /tmp/patch_host_api.py && \
        echo '            if line.strip().startswith("#include") or line.strip().startswith("#pragma"):' >> /tmp/patch_host_api.py && \
        echo '                insert_idx = i + 1' >> /tmp/patch_host_api.py && \
        echo '                break' >> /tmp/patch_host_api.py && \
        echo '        lines.insert(insert_idx, "#include <tt-metalium/core_type.hpp>")' >> /tmp/patch_host_api.py && \
        echo '        content = "\\n".join(lines)' >> /tmp/patch_host_api.py && \
        echo '        print("Added include for core_type.hpp at top")' >> /tmp/patch_host_api.py && \
        echo '    if "stl::Span" in content:' >> /tmp/patch_host_api.py && \
        echo '        content = content.replace("stl::Span", "tt::ttsl::Span")' >> /tmp/patch_host_api.py && \
        echo '        print("Replaced stl::Span with tt::ttsl::Span")' >> /tmp/patch_host_api.py && \
        echo '    if content != original_content:' >> /tmp/patch_host_api.py && \
        echo '        with open(file_path, "w") as f:' >> /tmp/patch_host_api.py && \
        echo '            f.write(content)' >> /tmp/patch_host_api.py && \
        echo '        print("Updated host_api.hpp")' >> /tmp/patch_host_api.py && \
        echo 'except Exception as e:' >> /tmp/patch_host_api.py && \
        echo '    print("Error: {}".format(e))' >> /tmp/patch_host_api.py && \
        python3 /tmp/patch_host_api.py; \
    fi

# 2n. Clone tt-logger and cleanup
RUN if [ ! -d /opt/tt-metal/tt-logger ]; then \
        echo "Cloning tt-logger..." && \
        (git clone --depth 1 https://github.com/tenstorrent/tt-logger.git /tmp/tt-logger-tmp 2>&1 && \
         cp -r /tmp/tt-logger-tmp/* /opt/tt-metal/tt-logger/ 2>/dev/null && \
         rm -rf /tmp/tt-logger-tmp && \
         echo "tt-logger cloned" || \
         (mkdir -p /opt/tt-metal/tt-logger && \
          echo '#pragma once' > /opt/tt-metal/tt-logger/tt-logger.hpp && \
          echo '// Stub header for tt-logger' >> /opt/tt-metal/tt-logger/tt-logger.hpp && \
          echo "tt-logger stub created")); \
    fi && \
    rm -rf /tmp/tt-metal-src && \
    echo "Headers copied to /opt/tt-metal"

# 2o. Patch circular_buffer_config.hpp to add missing includes
RUN if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/circular_buffer_config.hpp ]; then \
        if ! grep -q "unordered_set" /opt/tt-metal/tt_metal/api/tt-metalium/circular_buffer_config.hpp; then \
            sed -i '1i#include <unordered_set>' /opt/tt-metal/tt_metal/api/tt-metalium/circular_buffer_config.hpp; \
            echo "Inserted unordered_set include into circular_buffer_config.hpp"; \
        else \
            echo "circular_buffer_config.hpp already has unordered_set include"; \
        fi; \
    else \
        echo "circular_buffer_config.hpp not found, skipping patch"; \
    fi

# 2o1. Patch mesh_coord.hpp to replace SmallVector with std::vector
RUN if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/mesh_coord.hpp ]; then \
        sed -i 's/tt::stl::SmallVector/std::vector/g' /opt/tt-metal/tt_metal/api/tt-metalium/mesh_coord.hpp 2>/dev/null || true; \
        if ! grep -q "#include <vector>" /opt/tt-metal/tt_metal/api/tt-metalium/mesh_coord.hpp; then \
            sed -i '1a#include <vector>' /opt/tt-metal/tt_metal/api/tt-metalium/mesh_coord.hpp 2>/dev/null || \
            sed -i '/#pragma once/a#include <vector>' /opt/tt-metal/tt_metal/api/tt-metalium/mesh_coord.hpp 2>/dev/null || true; \
        fi; \
        echo "Patched mesh_coord.hpp"; \
    fi

# 2p. Create stubs for missing buffer config types and DataFormat
RUN mkdir -p /opt/tt-metal/tt_metal/api/tt-metalium && \
    if [ ! -f /opt/tt-metal/tt_metal/api/tt-metalium/buffer_config_types.hpp ]; then \
        echo '#pragma once' > /opt/tt-metal/tt_metal/api/tt-metalium/buffer_config_types.hpp && \
        echo '#include <cstdint>' >> /opt/tt-metal/tt_metal/api/tt-metalium/buffer_config_types.hpp && \
        echo 'namespace tt {' >> /opt/tt-metal/tt_metal/api/tt-metalium/buffer_config_types.hpp && \
        echo 'namespace tt_metal {' >> /opt/tt-metal/tt_metal/api/tt-metalium/buffer_config_types.hpp && \
        echo '    struct InterleavedBufferConfig {};' >> /opt/tt-metal/tt_metal/api/tt-metalium/buffer_config_types.hpp && \
        echo '    struct ShardedBufferConfig {};' >> /opt/tt-metal/tt_metal/api/tt-metalium/buffer_config_types.hpp && \
        echo '    using DeviceAddr = uint64_t;' >> /opt/tt-metal/tt_metal/api/tt-metalium/buffer_config_types.hpp && \
        echo '    using SubDeviceId = int;' >> /opt/tt-metal/tt_metal/api/tt-metalium/buffer_config_types.hpp && \
        echo '}' >> /opt/tt-metal/tt_metal/api/tt-metalium/buffer_config_types.hpp && \
        echo '}' >> /opt/tt-metal/tt_metal/api/tt-metalium/buffer_config_types.hpp; \
    fi && \
    if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/tt_backend_api_types.hpp ]; then \
        if ! grep -q "Float32" /opt/tt-metal/tt_metal/api/tt-metalium/tt_backend_api_types.hpp; then \
            echo 'file_path = "/opt/tt-metal/tt_metal/api/tt-metalium/tt_backend_api_types.hpp"' > /tmp/patch_dataformat.py && \
            echo 'try:' >> /tmp/patch_dataformat.py && \
            echo '    with open(file_path, "r") as f:' >> /tmp/patch_dataformat.py && \
            echo '        content = f.read()' >> /tmp/patch_dataformat.py && \
            echo '    if "Float32" not in content:' >> /tmp/patch_dataformat.py && \
            echo '        lines = content.split("\\n")' >> /tmp/patch_dataformat.py && \
            echo '        dataformat_idx = -1' >> /tmp/patch_dataformat.py && \
            echo '        for i, line in enumerate(lines):' >> /tmp/patch_dataformat.py && \
            echo '            if ("enum" in line and "DataFormat" in line) or ("DataFormat" in line and i > 0 and "enum" in lines[i-1]):' >> /tmp/patch_dataformat.py && \
            echo '                dataformat_idx = i' >> /tmp/patch_dataformat.py && \
            echo '                break' >> /tmp/patch_dataformat.py && \
            echo '        if dataformat_idx >= 0:' >> /tmp/patch_dataformat.py && \
            echo '            # Find the opening brace and add Float32 as first value' >> /tmp/patch_dataformat.py && \
            echo '            for i in range(dataformat_idx, min(dataformat_idx + 10, len(lines))):' >> /tmp/patch_dataformat.py && \
            echo '                if "{" in lines[i]:' >> /tmp/patch_dataformat.py && \
            echo '                    # Check if enum already has values' >> /tmp/patch_dataformat.py && \
            echo '                    next_line = lines[i+1].strip() if i+1 < len(lines) else ""' >> /tmp/patch_dataformat.py && \
            echo '                    if next_line and not next_line.startswith("}"):' >> /tmp/patch_dataformat.py && \
            echo '                        # Insert Float32 as first value' >> /tmp/patch_dataformat.py && \
            echo '                        lines.insert(i + 1, "        Float32,")' >> /tmp/patch_dataformat.py && \
            echo '                    elif not next_line or next_line.startswith("}"):' >> /tmp/patch_dataformat.py && \
            echo '                        # Empty enum, add Float32' >> /tmp/patch_dataformat.py && \
            echo '                        lines.insert(i + 1, "        Float32,")' >> /tmp/patch_dataformat.py && \
            echo '                    break' >> /tmp/patch_dataformat.py && \
            echo '        else:' >> /tmp/patch_dataformat.py && \
            echo '            # Add enum if it does not exist - find tt namespace (not tt_metal)' >> /tmp/patch_dataformat.py && \
            echo '            for i, line in enumerate(lines):' >> /tmp/patch_dataformat.py && \
            echo '                if "namespace tt" in line and "{" in line and "tt_metal" not in line:' >> /tmp/patch_dataformat.py && \
            echo '                    lines.insert(i + 1, "    enum class DataFormat { Float32, Float16, Bfp8, Bfp4, Int8, UInt8, Int32, UInt32 };")' >> /tmp/patch_dataformat.py && \
            echo '                    break' >> /tmp/patch_dataformat.py && \
            echo '        content = "\\n".join(lines)' >> /tmp/patch_dataformat.py && \
            echo '        with open(file_path, "w") as f:' >> /tmp/patch_dataformat.py && \
            echo '            f.write(content)' >> /tmp/patch_dataformat.py && \
            echo '        print("Added Float32 to DataFormat enum in tt_backend_api_types.hpp")' >> /tmp/patch_dataformat.py && \
            echo '    else:' >> /tmp/patch_dataformat.py && \
            echo '        print("Float32 already in DataFormat enum")' >> /tmp/patch_dataformat.py && \
            echo 'except Exception as e:' >> /tmp/patch_dataformat.py && \
            echo '    print("Error: {}".format(e))' >> /tmp/patch_dataformat.py && \
            echo '    import traceback' >> /tmp/patch_dataformat.py && \
            echo '    traceback.print_exc()' >> /tmp/patch_dataformat.py && \
            python3 /tmp/patch_dataformat.py; \
        fi; \
    fi

# 2p1. Patch profiler_optional_metadata.hpp for ChipId
RUN if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/profiler_optional_metadata.hpp ]; then \
        sed -i 's/tt::ChipId/tt::tt_metal::ChipId/g' /opt/tt-metal/tt_metal/api/tt-metalium/profiler_optional_metadata.hpp 2>/dev/null || true; \
        if ! grep -q "#include <tt-metalium/core_type.hpp>" /opt/tt-metal/tt_metal/api/tt-metalium/profiler_optional_metadata.hpp; then \
            sed -i '1a#include <tt-metalium/core_type.hpp>' /opt/tt-metal/tt_metal/api/tt-metalium/profiler_optional_metadata.hpp 2>/dev/null || \
            sed -i '/#pragma once/a#include <tt-metalium/core_type.hpp>' /opt/tt-metal/tt_metal/api/tt-metalium/profiler_optional_metadata.hpp 2>/dev/null || true; \
        fi; \
        echo "Patched profiler_optional_metadata.hpp"; \
    fi

# 2p1a. Add missing types to device.hpp
RUN if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/device.hpp ]; then \
        echo 'file_path = "/opt/tt-metal/tt_metal/api/tt-metalium/device.hpp"' > /tmp/patch_device.py && \
        echo 'try:' >> /tmp/patch_device.py && \
        echo '    with open(file_path, "r") as f:' >> /tmp/patch_device.py && \
        echo '        content = f.read()' >> /tmp/patch_device.py && \
        echo '    if "enum.*HalMemType" not in content and "HalMemType" not in content.split("enum"):' >> /tmp/patch_device.py && \
        echo '        lines = content.split("\\n")' >> /tmp/patch_device.py && \
        echo '        insert_idx = 0' >> /tmp/patch_device.py && \
        echo '        for i, line in enumerate(lines):' >> /tmp/patch_device.py && \
        echo '            if "namespace tt" in line and "{" in line:' >> /tmp/patch_device.py && \
        echo '                insert_idx = i + 1' >> /tmp/patch_device.py && \
        echo '                break' >> /tmp/patch_device.py && \
        echo '        type_stubs = [' >> /tmp/patch_device.py && \
        echo '            "    enum class HalMemType { L1, SYSTEM };",' >> /tmp/patch_device.py && \
        echo '            "    using HalL1MemAddrType = uint32_t;",' >> /tmp/patch_device.py && \
        echo '            "    using SubDeviceManagerId = int;",' >> /tmp/patch_device.py && \
        echo '        ]' >> /tmp/patch_device.py && \
        echo '        for i, stub in enumerate(type_stubs):' >> /tmp/patch_device.py && \
        echo '            lines.insert(insert_idx + i, stub)' >> /tmp/patch_device.py && \
        echo '        content = "\\n".join(lines)' >> /tmp/patch_device.py && \
        echo '        with open(file_path, "w") as f:' >> /tmp/patch_device.py && \
        echo '            f.write(content)' >> /tmp/patch_device.py && \
        echo '        print("Added missing types to device.hpp")' >> /tmp/patch_device.py && \
        echo 'except Exception as e:' >> /tmp/patch_device.py && \
        echo '    print("Error: {}".format(e))' >> /tmp/patch_device.py && \
        python3 /tmp/patch_device.py; \
    fi

# 2p2. Create stubs for kernel_types.hpp missing types
RUN mkdir -p /opt/tt-metal/tt_metal/api/tt-metalium && \
    if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/kernel_types.hpp ]; then \
        if ! grep -q "HalProcessorClassType" /opt/tt-metal/tt_metal/api/tt-metalium/kernel_types.hpp; then \
            echo 'file_path = "/opt/tt-metal/tt_metal/api/tt-metalium/kernel_types.hpp"' > /tmp/patch_kernel_types.py && \
            echo 'try:' >> /tmp/patch_kernel_types.py && \
            echo '    with open(file_path, "r") as f:' >> /tmp/patch_kernel_types.py && \
            echo '        content = f.read()' >> /tmp/patch_kernel_types.py && \
            echo '    if "HalProcessorClassType" not in content:' >> /tmp/patch_kernel_types.py && \
            echo '        lines = content.split("\\n")' >> /tmp/patch_kernel_types.py && \
            echo '        insert_idx = 0' >> /tmp/patch_kernel_types.py && \
            echo '        for i, line in enumerate(lines):' >> /tmp/patch_kernel_types.py && \
            echo '            if "namespace tt" in line and "{" in line:' >> /tmp/patch_kernel_types.py && \
            echo '                insert_idx = i + 1' >> /tmp/patch_kernel_types.py && \
            echo '                break' >> /tmp/patch_kernel_types.py && \
            echo '        lines.insert(insert_idx, "    enum class HalProcessorClassType { NONE, ETHERNET, RISCV_0, RISCV_1, TRISC };")' >> /tmp/patch_kernel_types.py && \
            echo '        lines.insert(insert_idx + 1, "    enum class HalProgrammableCoreType { NONE, WORKER, ETHERNET };")' >> /tmp/patch_kernel_types.py && \
            echo '        content = "\\n".join(lines)' >> /tmp/patch_kernel_types.py && \
            echo '        with open(file_path, "w") as f:' >> /tmp/patch_kernel_types.py && \
            echo '            f.write(content)' >> /tmp/patch_kernel_types.py && \
            echo '        print("Added HalProcessorClassType and HalProgrammableCoreType to kernel_types.hpp")' >> /tmp/patch_kernel_types.py && \
            echo 'except Exception as e:' >> /tmp/patch_kernel_types.py && \
            echo '    print("Error: {}".format(e))' >> /tmp/patch_kernel_types.py && \
            python3 /tmp/patch_kernel_types.py; \
        fi; \
    fi

# 2p3. Patch mesh_coord.hpp for ShapeBase
RUN if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/mesh_coord.hpp ]; then \
        echo 'file_path = "/opt/tt-metal/tt_metal/api/tt-metalium/mesh_coord.hpp"' > /tmp/patch_mesh_coord.py && \
        echo 'try:' >> /tmp/patch_mesh_coord.py && \
        echo '    with open(file_path, "r") as f:' >> /tmp/patch_mesh_coord.py && \
        echo '        content = f.read()' >> /tmp/patch_mesh_coord.py && \
        echo '    if "class ShapeBase" not in content and "struct ShapeBase" not in content:' >> /tmp/patch_mesh_coord.py && \
        echo '        lines = content.split("\\n")' >> /tmp/patch_mesh_coord.py && \
        echo '        insert_idx = 0' >> /tmp/patch_mesh_coord.py && \
        echo '        # Find distributed namespace' >> /tmp/patch_mesh_coord.py && \
        echo '        for i, line in enumerate(lines):' >> /tmp/patch_mesh_coord.py && \
        echo '            if "namespace distributed" in line or ("namespace" in line and "distributed" in line and "{" in line):' >> /tmp/patch_mesh_coord.py && \
        echo '                insert_idx = i + 1' >> /tmp/patch_mesh_coord.py && \
        echo '                break' >> /tmp/patch_mesh_coord.py && \
        echo '        if insert_idx == 0:' >> /tmp/patch_mesh_coord.py && \
        echo '            # Fallback to tt_metal namespace' >> /tmp/patch_mesh_coord.py && \
        echo '            for i, line in enumerate(lines):' >> /tmp/patch_mesh_coord.py && \
        echo '                if "namespace tt_metal" in line and "{" in line:' >> /tmp/patch_mesh_coord.py && \
        echo '                    insert_idx = i + 1' >> /tmp/patch_mesh_coord.py && \
        echo '                    break' >> /tmp/patch_mesh_coord.py && \
        echo '        # Add ShapeBase with required methods' >> /tmp/patch_mesh_coord.py && \
        echo '        shapebase_lines = [' >> /tmp/patch_mesh_coord.py && \
        echo '            "    class ShapeBase {",' >> /tmp/patch_mesh_coord.py && \
        echo '            "    public:",' >> /tmp/patch_mesh_coord.py && \
        echo '            "        std::vector<unsigned int> value_;",' >> /tmp/patch_mesh_coord.py && \
        echo '            "        unsigned int operator[](size_t i) const { return value_[i]; }",' >> /tmp/patch_mesh_coord.py && \
        echo '            "        bool empty() const { return value_.empty(); }",' >> /tmp/patch_mesh_coord.py && \
        echo '            "        size_t size() const { return value_.size(); }",' >> /tmp/patch_mesh_coord.py && \
        echo '            "    };"' >> /tmp/patch_mesh_coord.py && \
        echo '        ]' >> /tmp/patch_mesh_coord.py && \
        echo '        for i, line in enumerate(shapebase_lines):' >> /tmp/patch_mesh_coord.py && \
        echo '            lines.insert(insert_idx + i, line)' >> /tmp/patch_mesh_coord.py && \
        echo '        content = "\\n".join(lines)' >> /tmp/patch_mesh_coord.py && \
        echo '        with open(file_path, "w") as f:' >> /tmp/patch_mesh_coord.py && \
        echo '            f.write(content)' >> /tmp/patch_mesh_coord.py && \
        echo '        print("Added ShapeBase stub to mesh_coord.hpp")' >> /tmp/patch_mesh_coord.py && \
        echo 'except Exception as e:' >> /tmp/patch_mesh_coord.py && \
        echo '    print("Error: {}".format(e))' >> /tmp/patch_mesh_coord.py && \
        python3 /tmp/patch_mesh_coord.py; \
    fi

# 2q. Patch host_api.hpp to include buffer_config_types.hpp
RUN if [ -f /opt/tt-metal/tt_metal/api/tt-metalium/host_api.hpp ]; then \
        if ! grep -q "#include <tt-metalium/buffer_config_types.hpp>" /opt/tt-metal/tt_metal/api/tt-metalium/host_api.hpp; then \
            sed -i '/#include <tt-metalium\/core_type.hpp>/a#include <tt-metalium/buffer_config_types.hpp>' /opt/tt-metal/tt_metal/api/tt-metalium/host_api.hpp 2>/dev/null || \
            sed -i '/#include.*core_type/a#include <tt-metalium/buffer_config_types.hpp>' /opt/tt-metal/tt_metal/api/tt-metalium/host_api.hpp 2>/dev/null || \
            (echo 'file_path = "/opt/tt-metal/tt_metal/api/tt-metalium/host_api.hpp"' > /tmp/patch_buffer_config.py && \
             echo 'try:' >> /tmp/patch_buffer_config.py && \
             echo '    with open(file_path, "r") as f:' >> /tmp/patch_buffer_config.py && \
             echo '        lines = f.readlines()' >> /tmp/patch_buffer_config.py && \
             echo '    insert_idx = 0' >> /tmp/patch_buffer_config.py && \
             echo '    for i, line in enumerate(lines):' >> /tmp/patch_buffer_config.py && \
             echo '        if "core_type.hpp" in line:' >> /tmp/patch_buffer_config.py && \
             echo '            insert_idx = i + 1' >> /tmp/patch_buffer_config.py && \
             echo '            break' >> /tmp/patch_buffer_config.py && \
             echo '    if insert_idx > 0:' >> /tmp/patch_buffer_config.py && \
             echo '        lines.insert(insert_idx, "#include <tt-metalium/buffer_config_types.hpp>\\n")' >> /tmp/patch_buffer_config.py && \
             echo '        with open(file_path, "w") as f:' >> /tmp/patch_buffer_config.py && \
             echo '            f.writelines(lines)' >> /tmp/patch_buffer_config.py && \
             echo '        print("Added buffer_config_types.hpp include to host_api.hpp")' >> /tmp/patch_buffer_config.py && \
             echo 'except Exception as e:' >> /tmp/patch_buffer_config.py && \
             echo '    print("Error: {}".format(e))' >> /tmp/patch_buffer_config.py && \
             python3 /tmp/patch_buffer_config.py); \
            echo "Patched host_api.hpp to include buffer_config_types.hpp"; \
        fi; \
    fi

# 2z. Final fallback patches for TT headers - use Python to insert includes BEFORE specific markers
RUN echo 'import os' > /tmp/fix_unordered_set.py && \
    echo 'files_to_fix = [' >> /tmp/fix_unordered_set.py && \
    echo '    ("/opt/tt-metal/tt_metal/api/tt-metalium/circular_buffer_config.hpp", "program_descriptors"),' >> /tmp/fix_unordered_set.py && \
    echo '    ("/opt/tt-metal/tt_metal/api/tt-metalium/circular_buffer.hpp", "circular_buffer_constants"),' >> /tmp/fix_unordered_set.py && \
    echo '    ("/opt/tt-metal/tt_metal/api/tt-metalium/device.hpp", "core_coordinates"),' >> /tmp/fix_unordered_set.py && \
    echo ']' >> /tmp/fix_unordered_set.py && \
    echo 'for filepath, marker in files_to_fix:' >> /tmp/fix_unordered_set.py && \
    echo '    if os.path.exists(filepath):' >> /tmp/fix_unordered_set.py && \
    echo '        with open(filepath, "r") as f: lines = f.readlines()' >> /tmp/fix_unordered_set.py && \
    echo '        if not any("#include <unordered_set>" in line for line in lines):' >> /tmp/fix_unordered_set.py && \
    echo '            insert_idx = -1' >> /tmp/fix_unordered_set.py && \
    echo '            for i, line in enumerate(lines):' >> /tmp/fix_unordered_set.py && \
    echo '                if marker in line and "#include" in line: insert_idx = i; break' >> /tmp/fix_unordered_set.py && \
    echo '            if insert_idx >= 0:' >> /tmp/fix_unordered_set.py && \
    echo '                lines.insert(insert_idx, "#include <unordered_set>\\n")' >> /tmp/fix_unordered_set.py && \
    echo '                with open(filepath, "w") as f: f.writelines(lines)' >> /tmp/fix_unordered_set.py && \
    echo '                print("Added unordered_set to", os.path.basename(filepath))' >> /tmp/fix_unordered_set.py && \
    echo '            else:' >> /tmp/fix_unordered_set.py && \
    echo '                for i, line in enumerate(lines):' >> /tmp/fix_unordered_set.py && \
    echo '                    if line.strip().startswith("#include"):' >> /tmp/fix_unordered_set.py && \
    echo '                        lines.insert(i + 1, "#include <unordered_set>\\n")' >> /tmp/fix_unordered_set.py && \
    echo '                        with open(filepath, "w") as f: f.writelines(lines)' >> /tmp/fix_unordered_set.py && \
    echo '                        print("Added unordered_set to", os.path.basename(filepath), "(fallback)")' >> /tmp/fix_unordered_set.py && \
    echo '                        break' >> /tmp/fix_unordered_set.py && \
    python3 /tmp/fix_unordered_set.py && \
    echo "Fixed unordered_set includes" && \
    echo 'import os' > /tmp/fix_headers.py && \
    echo 'import re' >> /tmp/fix_headers.py && \
    echo '' >> /tmp/fix_headers.py && \
    echo '# Fix circular_buffer_config.hpp - ensure include is BEFORE program_descriptors' >> /tmp/fix_headers.py && \
    echo 'cb_file = "/opt/tt-metal/tt_metal/api/tt-metalium/circular_buffer_config.hpp"' >> /tmp/fix_headers.py && \
    echo 'if os.path.exists(cb_file):' >> /tmp/fix_headers.py && \
    echo '    with open(cb_file, "r") as f: lines = f.readlines()' >> /tmp/fix_headers.py && \
    echo '    has_unordered_set = any("#include <unordered_set>" in line for line in lines)' >> /tmp/fix_headers.py && \
    echo '    # Find program_descriptors include line' >> /tmp/fix_headers.py && \
    echo '    prog_desc_idx = -1' >> /tmp/fix_headers.py && \
    echo '    for i, line in enumerate(lines):' >> /tmp/fix_headers.py && \
    echo '        if "program_descriptors" in line and "#include" in line:' >> /tmp/fix_headers.py && \
    echo '            prog_desc_idx = i' >> /tmp/fix_headers.py && \
    echo '            break' >> /tmp/fix_headers.py && \
    echo '    if prog_desc_idx >= 0:' >> /tmp/fix_headers.py && \
    echo '        if not has_unordered_set:' >> /tmp/fix_headers.py && \
    echo '            lines.insert(prog_desc_idx, "#include <unordered_set>\\n")' >> /tmp/fix_headers.py && \
    echo '            print("Added unordered_set BEFORE program_descriptors at line", prog_desc_idx)' >> /tmp/fix_headers.py && \
    echo '        else:' >> /tmp/fix_headers.py && \
    echo '            # Check if it is after program_descriptors - if so, move it' >> /tmp/fix_headers.py && \
    echo '            unordered_idx = next((i for i, line in enumerate(lines) if "#include <unordered_set>" in line), -1)' >> /tmp/fix_headers.py && \
    echo '            if unordered_idx > prog_desc_idx:' >> /tmp/fix_headers.py && \
    echo '                lines.pop(unordered_idx)' >> /tmp/fix_headers.py && \
    echo '                lines.insert(prog_desc_idx, "#include <unordered_set>\\n")' >> /tmp/fix_headers.py && \
    echo '                print("Moved unordered_set BEFORE program_descriptors")' >> /tmp/fix_headers.py && \
    echo '        with open(cb_file, "w") as f: f.writelines(lines)' >> /tmp/fix_headers.py && \
    echo '' >> /tmp/fix_headers.py && \
    echo '# Fix reflection.hpp' >> /tmp/fix_headers.py && \
    echo 'refl_file = "/opt/tt-metal/tt_stl/reflection.hpp"' >> /tmp/fix_headers.py && \
    echo 'if os.path.exists(refl_file):' >> /tmp/fix_headers.py && \
    echo '    with open(refl_file, "r") as f: content = f.read()' >> /tmp/fix_headers.py && \
    echo '    if "consteval" in content or "reflect::" in content:' >> /tmp/fix_headers.py && \
    echo '        stub = "#pragma once\\nnamespace reflect {\\n    template<typename T, typename F>\\n    void for_each(F&&, T&&) {}\\n}\\nnamespace ttsl {\\n    namespace concepts {\\n        template<typename T>\\n        constexpr bool is_reflectable_v = false;\\n    }\\n}\\n"' >> /tmp/fix_headers.py && \
    echo '        with open(refl_file, "w") as f: f.write(stub)' >> /tmp/fix_headers.py && \
    echo '        print("Stubbed reflection.hpp")' >> /tmp/fix_headers.py && \
    echo '' >> /tmp/fix_headers.py && \
    echo '# Fix DataFormat enum' >> /tmp/fix_headers.py && \
    echo 'df_file = "/opt/tt-metal/tt_metal/api/tt-metalium/tt_backend_api_types.hpp"' >> /tmp/fix_headers.py && \
    echo 'if os.path.exists(df_file):' >> /tmp/fix_headers.py && \
    echo '    with open(df_file, "r") as f: content = f.read()' >> /tmp/fix_headers.py && \
    echo '    if "Float32" not in content:' >> /tmp/fix_headers.py && \
    echo '        lines = content.split(chr(10))' >> /tmp/fix_headers.py && \
    echo '        insert_idx = -1' >> /tmp/fix_headers.py && \
    echo '        brace_count = 0' >> /tmp/fix_headers.py && \
    echo '        in_tt_namespace = False' >> /tmp/fix_headers.py && \
    echo '        for i, line in enumerate(lines):' >> /tmp/fix_headers.py && \
    echo '            if "namespace tt" in line and "{" in line and "tt_metal" not in line:' >> /tmp/fix_headers.py && \
    echo '                in_tt_namespace = True' >> /tmp/fix_headers.py && \
    echo '                brace_count = line.count("{") - line.count("}")' >> /tmp/fix_headers.py && \
    echo '            elif in_tt_namespace:' >> /tmp/fix_headers.py && \
    echo '                brace_count += line.count("{") - line.count("}")' >> /tmp/fix_headers.py && \
    echo '                if brace_count == 0 and line.strip() == "}":' >> /tmp/fix_headers.py && \
    echo '                    insert_idx = i' >> /tmp/fix_headers.py && \
    echo '                    break' >> /tmp/fix_headers.py && \
    echo '        if insert_idx > 0:' >> /tmp/fix_headers.py && \
    echo '            lines.insert(insert_idx, "    enum class DataFormat { Float32, Float16, Bfp8, Bfp4, Int8, UInt8, Int32, UInt32 };")' >> /tmp/fix_headers.py && \
    echo '            with open(df_file, "w") as f: f.write(chr(10).join(lines))' >> /tmp/fix_headers.py && \
    echo '            print("Added DataFormat enum")' >> /tmp/fix_headers.py && \
    echo '        else:' >> /tmp/fix_headers.py && \
    echo '            # Fallback: append at end' >> /tmp/fix_headers.py && \
    echo '            with open(df_file, "a") as f: f.write("\\nnamespace tt { enum class DataFormat { Float32, Float16, Bfp8, Bfp4, Int8, UInt8, Int32, UInt32 }; }\\n")' >> /tmp/fix_headers.py && \
    echo '            print("Added DataFormat enum (fallback)")' >> /tmp/fix_headers.py && \
    echo '' >> /tmp/fix_headers.py && \
    echo '# Fix Hal enums' >> /tmp/fix_headers.py && \
    echo 'kt_file = "/opt/tt-metal/tt_metal/api/tt-metalium/kernel_types.hpp"' >> /tmp/fix_headers.py && \
    echo 'if os.path.exists(kt_file):' >> /tmp/fix_headers.py && \
    echo '    with open(kt_file, "r") as f: content = f.read()' >> /tmp/fix_headers.py && \
    echo '    if "HalProcessorClassType" not in content:' >> /tmp/fix_headers.py && \
    echo '        lines = content.split(chr(10))' >> /tmp/fix_headers.py && \
    echo '        insert_idx = 0' >> /tmp/fix_headers.py && \
    echo '        for i, line in enumerate(lines):' >> /tmp/fix_headers.py && \
    echo '            if "namespace tt" in line and "{" in line:' >> /tmp/fix_headers.py && \
    echo '                insert_idx = i + 1' >> /tmp/fix_headers.py && \
    echo '                break' >> /tmp/fix_headers.py && \
    echo '        if insert_idx > 0:' >> /tmp/fix_headers.py && \
    echo '            lines.insert(insert_idx, "    enum class HalProcessorClassType { NONE, ETHERNET, RISCV_0, RISCV_1, TRISC };")' >> /tmp/fix_headers.py && \
    echo '            lines.insert(insert_idx + 1, "    enum class HalProgrammableCoreType { NONE, WORKER, ETHERNET };")' >> /tmp/fix_headers.py && \
    echo '            with open(kt_file, "w") as f: f.write(chr(10).join(lines))' >> /tmp/fix_headers.py && \
    echo '            print("Added Hal enums")' >> /tmp/fix_headers.py && \
    echo '' >> /tmp/fix_headers.py && \
    echo '# Fix circular_buffer.hpp' >> /tmp/fix_headers.py && \
    echo 'cb2_file = "/opt/tt-metal/tt_metal/api/tt-metalium/circular_buffer.hpp"' >> /tmp/fix_headers.py && \
    echo 'if os.path.exists(cb2_file):' >> /tmp/fix_headers.py && \
    echo '    with open(cb2_file, "r") as f: content = f.read()' >> /tmp/fix_headers.py && \
    echo '    if "#include <unordered_set>" not in content:' >> /tmp/fix_headers.py && \
    echo '        lines = content.split(chr(10))' >> /tmp/fix_headers.py && \
    echo '        insert_idx = 0' >> /tmp/fix_headers.py && \
    echo '        for i, line in enumerate(lines):' >> /tmp/fix_headers.py && \
    echo '            if line.strip().startswith("#include"): insert_idx = i + 1' >> /tmp/fix_headers.py && \
    echo '        lines.insert(insert_idx, "#include <unordered_set>")' >> /tmp/fix_headers.py && \
    echo '        with open(cb2_file, "w") as f: f.write(chr(10).join(lines))' >> /tmp/fix_headers.py && \
    echo '        print("Added unordered_set to circular_buffer.hpp")' >> /tmp/fix_headers.py && \
    echo '' >> /tmp/fix_headers.py && \
    echo '# Fix device.hpp' >> /tmp/fix_headers.py && \
    echo 'dev_file = "/opt/tt-metal/tt_metal/api/tt-metalium/device.hpp"' >> /tmp/fix_headers.py && \
    echo 'if os.path.exists(dev_file):' >> /tmp/fix_headers.py && \
    echo '    with open(dev_file, "r") as f: content = f.read()' >> /tmp/fix_headers.py && \
    echo '    if "#include <unordered_set>" not in content:' >> /tmp/fix_headers.py && \
    echo '        lines = content.split(chr(10))' >> /tmp/fix_headers.py && \
    echo '        insert_idx = 0' >> /tmp/fix_headers.py && \
    echo '        for i, line in enumerate(lines):' >> /tmp/fix_headers.py && \
    echo '            if line.strip().startswith("#include"): insert_idx = i + 1' >> /tmp/fix_headers.py && \
    echo '        lines.insert(insert_idx, "#include <unordered_set>")' >> /tmp/fix_headers.py && \
    echo '        with open(dev_file, "w") as f: f.write(chr(10).join(lines))' >> /tmp/fix_headers.py && \
    echo '        print("Added unordered_set to device.hpp")' >> /tmp/fix_headers.py && \
    echo '' >> /tmp/fix_headers.py && \
    echo 'print("All patches applied successfully")' >> /tmp/fix_headers.py && \
    python3 /tmp/fix_headers.py

# 3. Set TT_METAL_HOME
ENV TT_METAL_HOME=/opt/tt-metal

# 4. Copy and Build project
COPY . .
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=ON -DDISABLE_AVX512=ON && \
    make -j$(nproc) && \
    ls -lh hardhack_* && \
    echo "Build completed successfully"

# 5. Prepare execution
RUN chmod +x mine.sh merkle_prove.sh && \
    ls -lh build/hardhack_* 2>/dev/null || true

# Set the entry point to use the hardware-enabled miner
ENTRYPOINT ["./mine.sh"]

