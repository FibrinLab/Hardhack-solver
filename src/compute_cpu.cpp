#include "compute.h"
#include <algorithm>
#include <cstring>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#endif

class CpuComputeDevice : public ComputeDevice {
public:
    void matmul(const uint8_t* A, 
                const uint8_t* B, 
                uint8_t* C) override {
        
        // We accumulate in 32-bit to prevent overflow. 
        // 16x16 matrix fits easily in L1 cache or even registers.
        uint32_t sums[M * N] __attribute__((aligned(16)));
        std::memset(sums, 0, sizeof(sums));

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
        // Optimization: Since N=16, we can process one whole row of the 
        // output matrix (16 columns) using NEON vectors.
        for (int k = 0; k < K; ++k) {
            // Load 16 bytes of B (one row of B)
            uint8x16_t v_b = vld1q_u8(&B[k * 16]);
            
            // Expand B to 16-bit then 32-bit to prepare for accumulation
            uint16x8_t v_b_lo = vmovl_u8(vget_low_u8(v_b));
            uint16x8_t v_b_hi = vmovl_u8(vget_high_u8(v_b));

            for (int i = 0; i < M; ++i) {
                uint32_t a_val = A[i * K + k];
                if (a_val == 0) continue; // Skip zeros (sparse-ish win)
                
                uint16x8_t v_a = vdupq_n_u16((uint16_t)a_val);
                
                // Multiply and add to current sums
                uint32_t* out_ptr = &sums[i * 16];
                
                // Vectorized Multiply-Accumulate
                uint32x4_t v_res0 = vld1q_u32(out_ptr);
                uint32x4_t v_res1 = vld1q_u32(out_ptr + 4);
                uint32x4_t v_res2 = vld1q_u32(out_ptr + 8);
                uint32x4_t v_res3 = vld1q_u32(out_ptr + 12);

                v_res0 = vmlal_u16(v_res0, vget_low_u16(v_a), vget_low_u16(v_b_lo));
                v_res1 = vmlal_u16(v_res1, vget_high_u16(v_a), vget_high_u16(v_b_lo));
                v_res2 = vmlal_u16(v_res2, vget_low_u16(v_a), vget_low_u16(v_b_hi));
                v_res3 = vmlal_u16(v_res3, vget_high_u16(v_a), vget_high_u16(v_b_hi));

                vst1q_u32(out_ptr, v_res0);
                vst1q_u32(out_ptr + 4, v_res1);
                vst1q_u32(out_ptr + 8, v_res2);
                vst1q_u32(out_ptr + 12, v_res3);
            }
        }
#else
        // Fallback for non-ARM
        for (int k = 0; k < K; ++k) {
            for (int i = 0; i < M; ++i) {
                uint32_t a_val = A[i * K + k];
                for (int j = 0; j < N; ++j) {
                    sums[i * N + j] += a_val * B[k * N + j];
                }
            }
        }
#endif

        for (int i = 0; i < M * N; ++i) C[i] = (uint8_t)(sums[i] & 0xFF);
    }

    std::string name() const override { return "CPU (NEON Int8)"; }
};

std::unique_ptr<ComputeDevice> create_cpu_compute() {
    return std::make_unique<CpuComputeDevice>();
}
