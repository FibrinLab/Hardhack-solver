#include "compute.h"
#include <iostream>

#ifdef ENABLE_TT
#include "tt_metal/host_api.hpp"
#include "tt_metal/common/constants.hpp"

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
                const uint8_t* B, 
                uint8_t* C) override {
        
        Program program = CreateProgram();
        CoreCoord core = {0, 0};

        // Tenstorrent uses 32x32 tiles. 
        // We map our 16x50240 and 50240x16 matrices to this grid.
        uint32_t num_tiles = 1570; // 50240 / 32

        // 1. Create Buffers on the device
        auto src0_buffer = CreateBuffer({device_, 1024 * num_tiles, 1024, BufferType::DRAM});
        auto src1_buffer = CreateBuffer({device_, 1024 * num_tiles, 1024, BufferType::DRAM});
        auto dst_buffer  = CreateBuffer({device_, 1024, 1024, BufferType::DRAM});

        // 2. Upload Data (Host -> Device)
        WriteToBuffer(src0_buffer, A);
        WriteToBuffer(src1_buffer, B);

        // 3. Load Kernels
        auto reader_id = CreateKernel(program, "src/kernels/reader_matmul.cpp", core, DataMovementConfig{.processor = DataMovementProcessor::RISCV_1, .noc = NOC::RISCV_1_default});
        auto writer_id = CreateKernel(program, "src/kernels/writer_matmul.cpp", core, DataMovementConfig{.processor = DataMovementProcessor::RISCV_0, .noc = NOC::RISCV_0_default});
        auto compute_id = CreateKernel(program, "src/kernels/compute_matmul.cpp", core, ComputeConfig{});

        // 4. Set Runtime Args and Launch
        SetRuntimeArgs(program, reader_id, core, {src0_buffer->address(), src1_buffer->address(), num_tiles});
        SetRuntimeArgs(program, compute_id, core, {num_tiles});
        
        LaunchProgram(device_, program);

        // 5. Download Result (Device -> Host)
        ReadFromBuffer(dst_buffer, C);
    }

    std::string name() const override { return "Tenstorrent (Hardware Accelerated)"; }

private:
    IDevice* device_;
};

std::unique_ptr<ComputeDevice> create_tt_compute() {
    return std::make_unique<TTComputeDevice>();
}
#endif