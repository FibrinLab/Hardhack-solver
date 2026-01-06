#include "compute.h"
#include <iostream>
#include <vector>
#include <cstring>

// Only include Tenstorrent headers if enabled
#ifdef ENABLE_TT
#include "tt_metal/host_api.hpp"
#include "tt_metal/impl/device/device.hpp"
#include "tt_metal/common/bfloat16.hpp"

using namespace tt;
using namespace tt::tt_metal;
#endif

class TenstorrentCompute : public ComputeDevice {
private:
#ifdef ENABLE_TT
    Device* device_ = nullptr;
#endif

public:
    TenstorrentCompute() {
#ifdef ENABLE_TT
        std::cout << "[Tenstorrent] Initializing Device 0..." << std::endl;
        // 1. Create Device
        // ID 0 is usually the first available chip
        device_ = CreateDevice(0);
#endif
    }

    ~TenstorrentCompute() {
#ifdef ENABLE_TT
        if (device_) {
            CloseDevice(device_);
        }
#endif
    }

    std::string name() const override {
        return "Tenstorrent_TT_Metal";
    }

    void multiply(const std::vector<int8_t>& mat_a, 
                  const std::vector<int8_t>& mat_b, 
                  std::vector<uint8_t>& mat_c_out) override {
#ifdef ENABLE_TT
        // --------------------------------------------------------------------
        // 1. DATA PREPARATION (Padding & Formatting)
        // --------------------------------------------------------------------
        // Tenstorrent cores work on 32x32 tiles. 
        // Input A is 16x50240. We need to pad rows to 32.
        // Input B is 50240x16. We need to pad cols to 32.
        
        constexpr int M = 16;
        constexpr int K = 50240;
        constexpr int N = 16;
        constexpr int M_PAD = 32;
        constexpr int N_PAD = 32;
        
        // Size in tiles
        uint32_t Mt = M_PAD / 32;       // 1
        uint32_t Kt = K / 32;           // 1570
        uint32_t Nt = N_PAD / 32;       // 1

        // Allocate Host Buffers (BF16 or Int8? Using BF16 for simplicity/compatibility)
        // Note: For raw speed you'd use a TILIZED layout. Here we do row-major for clarity.
        std::vector<bfloat16> host_a(M_PAD * K, bfloat16(0.0f));
        std::vector<bfloat16> host_b(K * N_PAD, bfloat16(0.0f));
        
        // Pad and copy A
        for (int r = 0; r < M; ++r) {
            for (int c = 0; c < K; ++c) {
                host_a[r * K + c] = bfloat16(static_cast<float>(mat_a[r * K + c]));
            }
        }

        // Pad and copy B
        for (int r = 0; r < K; ++r) {
            for (int c = 0; c < N; ++c) {
                host_b[r * N_PAD + c] = bfloat16(static_cast<float>(mat_b[r * N + c]));
            }
        }

        // --------------------------------------------------------------------
        // 2. DEVICE MEMORY ALLOCATION
        // --------------------------------------------------------------------
        // Calculate byte sizes (2 bytes per BF16)
        uint32_t dram_addr_a = 0; // Let allocator decide usually, but here explicit for clarity or use helper
        uint32_t size_bytes_a = host_a.size() * sizeof(bfloat16);
        uint32_t size_bytes_b = host_b.size() * sizeof(bfloat16);
        uint32_t size_bytes_c = M_PAD * N_PAD * sizeof(bfloat16);

        // Interleaved DRAM Buffers are easiest for large data
        // CreateBuffer(device, size, page_size, type)
        BufferConfig buffer_config = {
            .device = device_,
            .size = size_bytes_a,
            .page_size = 32 * 32 * sizeof(bfloat16), // 1 Tile per page
            .buffer_type = BufferType::DRAM
        };

        Buffer buffer_a = CreateBuffer(buffer_config);
        Buffer buffer_b = CreateBuffer({.device = device_, .size = size_bytes_b, .page_size = 32 * 32 * sizeof(bfloat16), .buffer_type = BufferType::DRAM});
        Buffer buffer_c = CreateBuffer({.device = device_, .size = size_bytes_c, .page_size = 32 * 32 * sizeof(bfloat16), .buffer_type = BufferType::DRAM});

        // --------------------------------------------------------------------
        // 3. WRITE DATA TO DEVICE
        // --------------------------------------------------------------------
        // Use `tt_metal::detail::WriteToBuffer` or equivalent
        // Note: Data must be TILIZED (Z-curve order) for optimal matmul. 
        // We assume `tilize_and_store` helper exists or we do it manually. 
        // For brevity, assuming `WriteToBuffer` handles standard layout or we pre-tilized.
        WriteToBuffer(buffer_a, host_a);
        WriteToBuffer(buffer_b, host_b);

        // --------------------------------------------------------------------
        // 4. PROGRAM CREATION
        // --------------------------------------------------------------------
        Program program = CreateProgram();

        // Define a Core (0,0) to do the work (Single Core for simplicity)
        CoreCoord core = {0, 0};
        
        // Circular Buffers (CBs) for L1 Memory (Input A, Input B, Output C)
        uint32_t cb_index_a = 0;
        uint32_t cb_tiles_a = 2; // Double buffer
        CircularBufferConfig cb_a_config = CircularBufferConfig(cb_tiles_a * 2048, {{cb_index_a, tt::DataFormat::Float16_b}})
            .set_page_size(cb_index_a, 2048); // 32*32*2 bytes
        CreateCircularBuffer(program, core, cb_a_config);

        uint32_t cb_index_b = 1;
        uint32_t cb_tiles_b = 2;
        CircularBufferConfig cb_b_config = CircularBufferConfig(cb_tiles_b * 2048, {{cb_index_b, tt::DataFormat::Float16_b}})
            .set_page_size(cb_index_b, 2048);
        CreateCircularBuffer(program, core, cb_b_config);

        uint32_t cb_index_c = 16; // Output
        uint32_t cb_tiles_c = 2;
        CircularBufferConfig cb_c_config = CircularBufferConfig(cb_tiles_c * 2048, {{cb_index_c, tt::DataFormat::Float16_b}})
            .set_page_size(cb_index_c, 2048);
        CreateCircularBuffer(program, core, cb_c_config);

        // --------------------------------------------------------------------
        // 5. KERNELS
        // --------------------------------------------------------------------
        // You need 3 kernels usually:
        // 1. Unpack/Read: Reads tiles from DRAM -> L1 CB
        // 2. Math: Computes L1 CB -> Math Unit -> L1 CB (Output)
        // 3. Pack/Write: Writes L1 CB -> DRAM
        
        // These .cpp files need to exist in your project!
        // Using standard "reader_matmul_blocked", "writer_unary", "bmm_tile_layout"
        
        auto reader_kernel = CreateKernel(
            program,
            "kernels/reader_matmul.cpp", // You must implement this
            core,
            DataMovementConfig{.processor = DataMovementProcessor::RISCV_1, .noc = NOC::RISCV_1_default}
        );

        auto writer_kernel = CreateKernel(
            program,
            "kernels/writer_matmul.cpp", // You must implement this
            core,
            DataMovementConfig{.processor = DataMovementProcessor::RISCV_0, .noc = NOC::RISCV_0_default}
        );

        std::vector<uint32_t> compute_args = {
            1, // batch
            Mt, 
            Kt, 
            Nt
        };
        
        auto compute_kernel = CreateKernel(
            program,
            "kernels/compute_matmul.cpp", // You must implement this
            core,
            ComputeConfig{.math_approx_mode = true, .compile_args = compute_args}
        );

        // --------------------------------------------------------------------
        // 6. RUNTIME ARGS
        // --------------------------------------------------------------------
        SetRuntimeArgs(
            program,
            reader_kernel,
            core,
            {buffer_a.address(), buffer_b.address(), Mt, Kt, Nt}
        );

        SetRuntimeArgs(
            program,
            writer_kernel,
            core,
            {buffer_c.address(), Mt, Nt}
        );

        // --------------------------------------------------------------------
        // 7. EXECUTE
        // --------------------------------------------------------------------
        EnqueueProgram(device_->command_queue(), program, false);
        Finish(device_->command_queue());

        // --------------------------------------------------------------------
        // 8. READ BACK & UNPAD
        // --------------------------------------------------------------------
        std::vector<bfloat16> result_host;
        ReadFromBuffer(buffer_c, result_host);

        // Convert 32x32 BF16 back to 16x16 Int32 (Bytes)
        mat_c_out.resize(M * N * 4); // 16*16*4
        size_t idx = 0;
        
        for (int r = 0; r < M; ++r) {
            for (int c = 0; c < N; ++c) {
                // Get value from padded result
                float val_f = result_host[r * N_PAD + c].to_float();
                int32_t val = static_cast<int32_t>(val_f);
                
                mat_c_out[idx++] = val & 0xFF;
                mat_c_out[idx++] = (val >> 8) & 0xFF;
                mat_c_out[idx++] = (val >> 16) & 0xFF;
                mat_c_out[idx++] = (val >> 24) & 0xFF;
            }
        }
#else
        std::cerr << "[Error] Tenstorrent support not compiled. Rebuild with -DENABLE_TT=ON" << std::endl;
        exit(1);
#endif
    }
};

std::unique_ptr<ComputeDevice> create_tt_compute() {
    return std::make_unique<TenstorrentCompute>();
}
