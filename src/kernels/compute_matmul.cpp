#include <cstdint>
#include "compute_kernel_api/matmul.h"
#include "compute_kernel_api/tilize.h"
#include "compute_kernel_api/untilize.h"

namespace NAMESPACE {
    void MAIN {
        uint32_t Kt = get_arg_val<uint32_t>(0); // 1570 tiles

        constexpr auto cb_in0 = tt::CBIndex::c_0;
        constexpr auto cb_in1 = tt::CBIndex::c_1;
        constexpr auto cb_out = tt::CBIndex::c_16;

        // Initialize Matmul
        mm_init(cb_in0, cb_in1, cb_out);
        
        // Acquire destination registers (accumulator)
        tile_regs_acquire();
        
        // Loop over K dimension
        for (uint32_t k = 0; k < Kt; ++k) {
            // Wait for inputs
            cb_wait_front(cb_in0, 1);
            cb_wait_front(cb_in1, 1);
            
            // Multiply and Accumulate
            // matmul_tiles(in0_cb, in1_cb, in0_tile, in1_tile, dst_tile, transpose)
            matmul_tiles(cb_in0, cb_in1, 0, 0, 0, false);
            
            // Release inputs
            cb_pop_front(cb_in0, 1);
            cb_pop_front(cb_in1, 1);
        }
        
        // Commit results
        tile_regs_commit();
        tile_regs_wait();
        
        // Pack result to L1
        cb_reserve_back(cb_out, 1);
        pack_tile(0, cb_out);
        cb_push_back(cb_out, 1);
        
        // Release registers
        tile_regs_release();
    }
}