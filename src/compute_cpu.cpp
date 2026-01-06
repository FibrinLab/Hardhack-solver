#include "compute.h"
#include <algorithm>
#include <cstring>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#endif

class CpuComputeDevice : public ComputeDevice {
public:
    void matmul(const uint8_t* A, 
                const int8_t* B, 
                int32_t* C) override {
        
        // Verified logic: Standard A x B, Little-Endian
        std::memset(C, 0, M * N * sizeof(int32_t));

        for (int i = 0; i < M; ++i) {
            for (int k = 0; k < K; ++k) {
                int32_t val_a = (int32_t)A[i * K + k];
                const int8_t* b_row = &B[k * N];
                int32_t* c_row = &C[i * N];

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
                // Vectorized row update (N=16)
                int32x4_t va = vdupq_n_s32(val_a);
                
                // Process 16 columns in 4 chunks of 4
                for (int j = 0; j < 16; j += 4) {
                    // 1. Load 4 bytes from B
                    int8x8_t vb8 = vld1_s8(&b_row[j]);
                    // 2. Widen 8-bit to 16-bit (gives 8 elements)
                    int16x8_t vb16 = vmovl_s8(vb8);
                    // 3. Widen first 4 elements of 16-bit to 32-bit
                    int32x4_t vb32 = vmovl_s16(vget_low_s16(vb16));
                    
                    // 4. Load C, Multiply-Accumulate, Store
                    int32x4_t vc = vld1q_s32(&c_row[j]);
                    vc = vmlaq_s32(vc, va, vb32);
                    vst1q_s32(&c_row[j], vc);
                }
#else
                for (int j = 0; j < N; ++j) {
                    c_row[j] += val_a * (int32_t)b_row[j];
                }
#endif
            }
        }
    }

    std::string name() const override { return "CPU (Fixed NEON Winner)"; }
};

std::unique_ptr<ComputeDevice> create_cpu_compute() {
    return std::make_unique<CpuComputeDevice>();
}