#include "compute.h"
#include <iostream>
#include <vector>
#include <cmath>

#ifdef ENABLE_TT
#include <tt-metalium/host_api.hpp>
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
        device_ = CreateDevice(0);
#endif
    }

    ~TenstorrentCompute() {
#ifdef ENABLE_TT
        if (device_) CloseDevice(device_);
#endif
    }

    std::string name() const override {
        return "Tenstorrent_TT_Metal";
    }

    // Helper: Convert Row-Major Matrix to Tiled Layout (32x32 tiles)
    // Pads dimensions to multiples of 32
#ifdef ENABLE_TT
    std::vector<bfloat16> tilize(const std::vector<int8_t>& src, int rows, int cols, int rows_pad, int cols_pad) {
        std::vector<bfloat16> tiled(rows_pad * cols_pad, bfloat16(0.0f));
        
        // Tenstorrent Layout:
        // A Tile is 32x32.
        // It consists of 4 "Faces" of 16x16.
        // Face 0: Top-Left
        // Face 1: Top-Right
        // Face 2: Bottom-Left
        // Face 3: Bottom-Right
        // Within a Face, data is Row-Major.
        
        int tiles_r = rows_pad / 32;
        int tiles_c = cols_pad / 32;

        for (int tr = 0; tr < tiles_r; ++tr) {
            for (int tc = 0; tc < tiles_c; ++tc) {
                // Process one 32x32 tile at (tr, tc)
                int base_idx = (tr * tiles_c + tc) * (32 * 32); // Start of this tile in result vector
                
                // Iterate over 4 faces
                for (int face = 0; face < 4; ++face) {
                    int face_r_offset = (face / 2) * 16; // 0 or 16
                    int face_c_offset = (face % 2) * 16; // 0 or 16
                    int face_base_idx = base_idx + face * (16 * 16);

                    for (int i = 0; i < 16; ++i) {
                        for (int j = 0; j < 16; ++j) {
                            int r = tr * 32 + face_r_offset + i;
                            int c = tc * 32 + face_c_offset + j;

                            float val = 0.0f;
                            if (r < rows && c < cols) {
                                val = static_cast<float>(src[r * cols + c]);
                            }
                            
                            tiled[face_base_idx + i * 16 + j] = bfloat16(val);
                        }
                    }
                }
            }
        }
        return tiled;
    }

    // Helper: Convert Tiled Layout back to Row-Major (Extracting top-left 16x16)
    std::vector<uint8_t> untilize_result(const std::vector<bfloat16>& src_tiled) {
        // We only care about the first 16x16 face of the first tile.
        // Result C is 16x16. One tile is 32x32.
        // Face 0 is exactly what we want.
        
        std::vector<uint8_t> result(16 * 16 * 4); // 4 bytes per int32
        int idx = 0;
        
        // Face 0 is the first 256 elements
        for (int i = 0; i < 256; ++i) {
            float val_f = src_tiled[i].to_float();
            int32_t val = static_cast<int32_t>(val_f);
            
            result[idx++] = val & 0xFF;
            result[idx++] = (val >> 8) & 0xFF;
            result[idx++] = (val >> 16) & 0xFF;
            result[idx++] = (val >> 24) & 0xFF;
        }
        return result;
    }
#endif

    void multiply(const std::vector<int8_t>& mat_a, 
                  const std::vector<int8_t>& mat_b, 
                  std::vector<uint8_t>& mat_c_out) override {
#ifdef ENABLE_TT
        // Dimensions
        constexpr int M = 16, K = 50240, N = 16;
        constexpr int M_PAD = 32, K_PAD = 50240, N_PAD = 32;
        
        // 1. Host Preparation (Tilize)
        auto host_a = tilize(mat_a, M, K, M_PAD, K_PAD);
        auto host_b = tilize(mat_b, K, N, K_PAD, N_PAD); // B is KxN

        uint32_t src0_size = host_a.size() * sizeof(bfloat16);
        uint32_t src1_size = host_b.size() * sizeof(bfloat16);
        uint32_t dst_size  = M_PAD * N_PAD * sizeof(bfloat16);

        // 2. Device Buffers
        BufferConfig buf_cfg = {.device=device_, .page_size=2048, .buffer_type=BufferType::DRAM};
        
        buf_cfg.size = src0_size;
        Buffer src0_buf = CreateBuffer(buf_cfg);
        
        buf_cfg.size = src1_size;
        Buffer src1_buf = CreateBuffer(buf_cfg);
        
        buf_cfg.size = dst_size;
        Buffer dst_buf = CreateBuffer(buf_cfg);

        // 3. Write Data
        WriteToBuffer(src0_buf, host_a);
        WriteToBuffer(src1_buf, host_b);

        // 4. Create Program
        Program program = CreateProgram();
        CoreCoord core = {0, 0}; // Single Core
        
        // Circular Buffers (CBs)
        uint32_t cb_tiles = 2; // Double buffered
        uint32_t tile_size = 2048;
        
        // Input 0 (A)
        CircularBufferConfig cb0_cfg(cb_tiles * tile_size, {{tt::CBIndex::c_0, tt::DataFormat::Float16_b}});
        cb0_cfg.set_page_size(tt::CBIndex::c_0, tile_size);
        CreateCircularBuffer(program, core, cb0_cfg);

        // Input 1 (B)
        CircularBufferConfig cb1_cfg(cb_tiles * tile_size, {{tt::CBIndex::c_1, tt::DataFormat::Float16_b}});
        cb1_cfg.set_page_size(tt::CBIndex::c_1, tile_size);
        CreateCircularBuffer(program, core, cb1_cfg);

        // Output (C)
        CircularBufferConfig cb16_cfg(cb_tiles * tile_size, {{tt::CBIndex::c_16, tt::DataFormat::Float16_b}});
        cb16_cfg.set_page_size(tt::CBIndex::c_16, tile_size);
        CreateCircularBuffer(program, core, cb16_cfg);

        // 5. Create Kernels
        // Reader
        std::vector<uint32_t> reader_args = {src0_buf.address(), src1_buf.address(), (uint32_t)(K_PAD / 32)};
        auto reader_k = CreateKernel(program, "src/kernels/reader_matmul.cpp", core, 
            DataMovementConfig{.processor = DataMovementProcessor::RISCV_1, .noc = NOC::RISCV_1_default});

        // Writer
        std::vector<uint32_t> writer_args = {dst_buf.address()};
        auto writer_k = CreateKernel(program, "src/kernels/writer_matmul.cpp", core, 
            DataMovementConfig{.processor = DataMovementProcessor::RISCV_0, .noc = NOC::RISCV_0_default});

        // Compute
        std::vector<uint32_t> compute_args_rt = {(uint32_t)(K_PAD / 32)}; // Runtime args for compute
        auto compute_k = CreateKernel(program, "src/kernels/compute_matmul.cpp", core, 
            ComputeConfig{.math_fidelity = MathFidelity::HiFi4, .compile_args = {}}); // Empty compile args

        // 6. Runtime Args
        SetRuntimeArgs(program, reader_k, core, reader_args);
        SetRuntimeArgs(program, writer_k, core, writer_args);
        SetRuntimeArgs(program, compute_k, core, compute_args_rt);

        // 7. Execute
        EnqueueProgram(device_->command_queue(), program, false);
        Finish(device_->command_queue());

        // 8. Read Result
        std::vector<bfloat16> result_tiled;
        ReadFromBuffer(dst_buf, result_tiled);
        
        mat_c_out = untilize_result(result_tiled);

#else
        std::cerr << "[Error] TT Disabled." << std::endl;
        exit(1);
#endif
    }
};

std::unique_ptr<ComputeDevice> create_tt_compute() {
    return std::make_unique<TenstorrentCompute>();
}