# Use the Tenstorrent Wormhole image (N300S is Wormhole-based)
FROM ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-amd64:latest-rc

USER root
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install runtime dependencies
RUN apt-get update && apt-get install -y \
    curl xxd libomp-dev git cmake build-essential \
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

# 3. Set TT_METAL_HOME
ENV TT_METAL_HOME=/opt/tt-metal

# 4. Copy and Build project
COPY . .
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DENABLE_TT=ON -DDISABLE_AVX512=ON && \
    make -j$(nproc)

# 4. Prepare execution
RUN chmod +x mine.sh prove.sh

# Set the entry point to use the hardware-enabled miner
ENTRYPOINT ["./mine.sh"]

