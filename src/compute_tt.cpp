#include "compute.h"
#include <iostream>

#ifdef ENABLE_TT
// Include span first to make tt::stl::Span available  
#include <tt_stl/span.hpp>
// host_api.hpp uses stl::Span inside tt::tt_metal namespace
// We need to make stl::Span available there - create nested namespace
namespace tt {
namespace tt_metal {
    namespace stl {
        template<typename T, std::size_t Extent = tt::ttsl::dynamic_extent>
        using Span = tt::ttsl::Span<T, Extent>;
    }
}
}
#include "tt_metal/api/tt-metalium/host_api.hpp"

using namespace tt;
using namespace tt::tt_metal;

class TTComputeDevice : public ComputeDevice {
public:
    TTComputeDevice() {
        // Stub: CreateDevice may not be available, use nullptr
        device_ = nullptr;
    }

    ~TTComputeDevice() {
        // Stub: CloseDevice may not be available
        if (device_) {
            // CloseDevice(device_);
        }
    }

    void matmul(const uint8_t* A, 
                const int8_t* B, 
                int32_t* C) override {
        
        // Tenstorrent uses 32x32 tiles.
        // We map 16x50240 and 16x50240 to this grid.
        
        // Host fallback for initial verification
        auto host_fallback = create_cpu_compute();
        host_fallback->matmul(A, B, C);
    }

    std::string name() const override { return "Tenstorrent (INT32 Dot-Product)"; }

private:
    tt::tt_metal::IDevice* device_;
};

std::unique_ptr<ComputeDevice> create_tt_compute() {
    return std::make_unique<TTComputeDevice>();
}
#endif
