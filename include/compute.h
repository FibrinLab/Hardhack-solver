#pragma once

#include <vector>
#include <cstdint>
#include <string>
#include <memory>

// Interface for Compute Backends (CPU vs Tenstorrent)
class ComputeDevice {
public:
    virtual ~ComputeDevice() = default;

    virtual void multiply(const std::vector<int8_t>& mat_a, 
                          const std::vector<int8_t>& mat_b, 
                          std::vector<uint8_t>& mat_c_out) = 0;

    virtual std::string name() const = 0;
};

// Factory functions
std::unique_ptr<ComputeDevice> create_cpu_compute();
std::unique_ptr<ComputeDevice> create_tt_compute();