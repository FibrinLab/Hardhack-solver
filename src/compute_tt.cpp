#include "compute.h"
#include <iostream>
#include <vector>

#ifdef ENABLE_TT
#include <tt_stl/span.hpp>
// host_api.hpp uses stl::Span inside tt::tt_metal namespace
namespace tt {
namespace tt_metal {
    namespace stl {
        template<typename T, std::size_t Extent = tt::ttsl::dynamic_extent>
        using Span = tt::ttsl::Span<T, Extent>;
    }
}
}
#include "tt_metal/api/tt-metalium/host_api.hpp"
#include "tt_metal/api/tt-metalium/device.hpp"
#include "tt_metal/api/tt-metalium/command_queue.hpp"
#include "tt_metal/api/tt-metalium/buffer.hpp"
#include "tt_metal/common/constants.hpp"
#include "tt_metal/common/bfloat16.hpp"

using namespace tt;
using namespace tt::tt_metal;

class TTComputeDevice : public ComputeDevice {
public:
    TTComputeDevice() {
        // Initialize the device (ID 0)
        device_ = CreateDevice(0);
    }

    ~TTComputeDevice() {
        if (device_) {
            CloseDevice(device_);
        }
    }

    void matmul(const uint8_t* A, 
                const int8_t* B, 
                int32_t* C) override {
        
        // 1. Create a Program
        Program program = CreateProgram();
        CoreCoord core = {0, 0}; // Use a single core for this example
        
        // Get Command Queue
        CommandQueue& cq = device_->command_queue();

        // 2. Define Tile Constants
        // Tenstorrent works with 32x32 tiles.
        // Assuming the input data is already formatted or can be treated as tiles.
        uint32_t single_tile_size = 32 * 32; // 1024 bytes for uint8
        uint32_t num_tiles = 1; // Adjust based on actual input size if needed
        uint32_t buffer_size = single_tile_size * num_tiles;

        // 3. Create DRAM Buffers
        tt::tt_metal::InterleavedBufferConfig config{
                    .device=device_,
                    .size = buffer_size,
                    .page_size = buffer_size, 
                    .buffer_type = tt::tt_metal::BufferType::DRAM
        };

        std::shared_ptr<Buffer> src0_dram_buffer = CreateBuffer(config);
        std::shared_ptr<Buffer> src1_dram_buffer = CreateBuffer(config);
        std::shared_ptr<Buffer> dst_dram_buffer = CreateBuffer(config);

        // 4. Write Input Data to Device
        std::vector<uint8_t> src0_vec(A, A + buffer_size);
        std::vector<uint8_t> src1_vec((uint8_t*)B, (uint8_t*)B + buffer_size);

        EnqueueWriteBuffer(cq, src0_dram_buffer, src0_vec, false);
        EnqueueWriteBuffer(cq, src1_dram_buffer, src1_vec, false);

        // 5. Configure Circular Buffers (CBs)
        uint32_t cb_index_in0 = 0;
        uint32_t cb_index_in1 = 1;
        uint32_t cb_index_out = 16;
        uint32_t num_input_tiles = 2; // Double buffering
        uint32_t num_output_tiles = 2;

        CircularBufferConfig cb_src0_config = CircularBufferConfig(num_input_tiles * single_tile_size, {{cb_index_in0, tt::DataFormat::UInt8}})
            .set_page_size(cb_index_in0, single_tile_size);
        CreateCircularBuffer(program, core, cb_src0_config);

        CircularBufferConfig cb_src1_config = CircularBufferConfig(num_input_tiles * single_tile_size, {{cb_index_in1, tt::DataFormat::UInt8}}) // handling int8 as uint8 for transport
            .set_page_size(cb_index_in1, single_tile_size);
        CreateCircularBuffer(program, core, cb_src1_config);

        CircularBufferConfig cb_output_config = CircularBufferConfig(num_output_tiles * single_tile_size * 4, {{cb_index_out, tt::DataFormat::Int32}}) // Output is Int32
            .set_page_size(cb_index_out, single_tile_size * 4);
        CreateCircularBuffer(program, core, cb_output_config);

        // 6. Create Kernels
        // Reader
        std::vector<uint32_t> reader_compile_time_args = {(uint32_t)true};
        KernelHandle reader_kernel_id = CreateKernel(
            program,
            "src/kernels/reader_matmul.cpp",
            core,
            DataMovementConfig{.processor = DataMovementProcessor::RISCV_0, .noc = NOC::RISCV_0_default}
        );

        // Writer
        std::vector<uint32_t> writer_compile_time_args = {(uint32_t)true};
        KernelHandle writer_kernel_id = CreateKernel(
            program,
            "src/kernels/writer_matmul.cpp",
            core,
            DataMovementConfig{.processor = DataMovementProcessor::RISCV_1, .noc = NOC::RISCV_1_default}
        );

        // Compute
        std::vector<uint32_t> compute_compile_time_args = {};
        KernelHandle compute_kernel_id = CreateKernel(
            program,
            "src/kernels/compute_matmul.cpp",
            core,
            ComputeConfig{.compile_args = compute_compile_time_args}
        );

        // 7. Set Runtime Arguments
        SetRuntimeArgs(
            program,
            reader_kernel_id,
            core,
            {src0_dram_buffer->address(), src1_dram_buffer->address(), num_tiles}
        );

        SetRuntimeArgs(
            program,
            writer_kernel_id,
            core,
            {dst_dram_buffer->address()}
        );

        SetRuntimeArgs(
            program,
            compute_kernel_id,
            core,
            {num_tiles}
        );

        // 8. Launch Program
        EnqueueProgram(cq, program, false);
        Finish(cq);

        // 9. Read Results
        std::vector<int32_t> result_vec;
        EnqueueReadBuffer(cq, dst_dram_buffer, result_vec, true);
        
        // Copy back to output pointer
        std::memcpy(C, result_vec.data(), buffer_size * sizeof(int32_t));
    }

    std::string name() const override { return "Tenstorrent (INT32 Dot-Product)"; }

private:
    IDevice* device_;
};

std::unique_ptr<ComputeDevice> create_tt_compute() {
    return std::make_unique<TTComputeDevice>();
}
#endif
