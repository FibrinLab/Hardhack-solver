#include "compute.h"
#include <vector>
#include <cstdint>

class CpuCompute : public ComputeDevice {
public:
    std::string name() const override {
        return "CPU_Int8_Optimized";
    }

    void multiply(const std::vector<int8_t>& mat_a, 
                  const std::vector<int8_t>& mat_b, 
                  std::vector<uint8_t>& mat_c_out) override {
        
        constexpr int ROWS_A = 16;
        constexpr int COLS_A = 50240; // K
        constexpr int COLS_B = 16;    // N
        
        int32_t result[16][16];

        for (int i = 0; i < ROWS_A; ++i) {
            int32_t acc[16] = {0}; 
            const int8_t* row_a_ptr = &mat_a[i * COLS_A];
            
            for (int k = 0; k < COLS_A; ++k) {
                int8_t val_a = row_a_ptr[k];
                const int8_t* row_b_ptr = &mat_b[k * COLS_B]; 
                
                for (int j = 0; j < 16; ++j) {
                    acc[j] += (int32_t)val_a * (int32_t)row_b_ptr[j];
                }
            }
            
            for(int j=0; j<16; ++j) {
                result[i][j] = acc[j];
            }
        }

        mat_c_out.resize(16 * 16 * 4);
        size_t idx = 0;
        for (int i = 0; i < 16; ++i) {
            for (int j = 0; j < 16; ++j) {
                int32_t val = result[i][j];
                mat_c_out[idx++] = val & 0xFF;
                mat_c_out[idx++] = (val >> 8) & 0xFF;
                mat_c_out[idx++] = (val >> 16) & 0xFF;
                mat_c_out[idx++] = (val >> 24) & 0xFF;
            }
        }
    }
};

std::unique_ptr<ComputeDevice> create_cpu_compute() {
    return std::make_unique<CpuCompute>();
}