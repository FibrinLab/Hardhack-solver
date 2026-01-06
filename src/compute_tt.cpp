#include "compute.h"
#include <iostream>

#ifdef ENABLE_TT
#include "tt_metal/host_api.hpp"

using namespace tt;
using namespace tt::tt_metal;

class TTComputeDevice : public ComputeDevice {
public:
    TTComputeDevice() {
        device_ = CreateDevice(0);
    }

    ~TTComputeDevice() {
        CloseDevice(device_);
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
    IDevice* device_;
};

std::unique_ptr<ComputeDevice> create_tt_compute() {
    return std::make_unique<TTComputeDevice>();
}
#endif
