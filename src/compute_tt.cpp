#include "compute.h"
#include <iostream>
#include <vector>
#include <algorithm>

#ifdef ENABLE_TT
#if __has_include(<tt_stl/span.hpp>)
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
#endif
#if __has_include(<tt-metalium/host_api.hpp>)
#include <tt-metalium/host_api.hpp>
#include <tt-metalium/device.hpp>
#include <tt-metalium/command_queue.hpp>
#include <tt-metalium/buffer.hpp>
#include <tt-metalium/constants.hpp>
#include <tt-metalium/bfloat16.hpp>
#elif __has_include(<tt_metal/host_api.hpp>)
#include <tt_metal/host_api.hpp>
#include <tt_metal/device.hpp>
#include <tt_metal/command_queue.hpp>
#include <tt_metal/buffer.hpp>
#include <tt_metal/constants.hpp>
#include <tt_metal/bfloat16.hpp>
#else
#error "TT-Metal headers not found (tt-metalium or tt_metal). Set TT_METAL_HOME/include path."
#endif

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

        // 2. Define Tile Constants (32x32 tiles)
        constexpr uint32_t tile_hw = 32;
        uint32_t single_tile_size = tile_hw * tile_hw; // 1024 bytes per tile (uint8/int8)

        // K dimension is 50240 -> 50240 / 32 = 1570 tiles
        uint32_t num_tiles = (K + tile_hw - 1) / tile_hw; // 1570
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

        // 4. Pack input into tiles (32x32)
        // A is 16x50240 (u8) -> pad to 32 rows
        // B is 50240x16 (i8) -> pad to 32 cols
        std::vector<uint8_t> src0_vec(buffer_size, 0);
        std::vector<uint8_t> src1_vec(buffer_size, 0);

        for (uint32_t tile_idx = 0; tile_idx < num_tiles; ++tile_idx) {
            uint32_t k_start = tile_idx * tile_hw;
            uint32_t k_end = std::min(k_start + tile_hw, (uint32_t)K);

            // A tile: rows 0-15 (pad 16-31), cols k_start..k_end
            for (uint32_t i = 0; i < 16; ++i) {
                for (uint32_t k = k_start; k < k_end; ++k) {
                    uint32_t tile_row = i;
                    uint32_t tile_col = k - k_start;
                    uint32_t tile_offset = tile_idx * single_tile_size + tile_row * tile_hw + tile_col;
                    src0_vec[tile_offset] = A[i * K + k];
                }
            }

            // B tile: rows k_start..k_end, cols 0-15 (pad 16-31)
            for (uint32_t k = k_start; k < k_end; ++k) {
                for (uint32_t j = 0; j < 16; ++j) {
                    uint32_t tile_row = k - k_start;
                    uint32_t tile_col = j;
                    uint32_t tile_offset = tile_idx * single_tile_size + tile_row * tile_hw + tile_col;
                    // Preserve signed bit pattern in uint8 container
                    src1_vec[tile_offset] = static_cast<uint8_t>(B[k * N + j]);
                }
            }
        }

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

        CircularBufferConfig cb_src1_config = CircularBufferConfig(num_input_tiles * single_tile_size, {{cb_index_in1, tt::DataFormat::Int8}})
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

        // 9. Read Results (one 32x32 tile)
        std::vector<int32_t> result_vec((tile_hw * tile_hw), 0);
        EnqueueReadBuffer(cq, dst_dram_buffer, result_vec, true);

        // Copy back top-left 16x16 into C
        for (uint32_t i = 0; i < 16; ++i) {
            for (uint32_t j = 0; j < 16; ++j) {
                C[i * N + j] = result_vec[i * tile_hw + j];
            }
        }
    }

    std::string name() const override { return "Tenstorrent (INT32 Dot-Product)"; }

private:
    IDevice* device_;
};

std::unique_ptr<ComputeDevice> create_tt_compute() {
    return std::make_unique<TTComputeDevice>();
}
#endif
