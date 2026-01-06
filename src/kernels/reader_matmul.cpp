#include <stdint.h>
#include "dataflow_api.h"

void kernel_main() {
    uint32_t src0_addr  = get_arg_val<uint32_t>(0);
    uint32_t src1_addr  = get_arg_val<uint32_t>(1);
    uint32_t num_tiles  = get_arg_val<uint32_t>(2);

    constexpr uint32_t cb_id_in0 = 0;
    constexpr uint32_t cb_id_in1 = 1;

    // Use two buffers per input to hide DRAM latency
    for (uint32_t i = 0; i < num_tiles; ++i) {
        // Tile for Matrix A
        cb_reserve_back(cb_id_in0, 1);
        uint32_t l1_addr0 = get_write_ptr(cb_id_in0);
        noc_async_read(src0_addr + (i * 1024), l1_addr0, 1024);
        
        // Tile for Matrix B
        cb_reserve_back(cb_id_in1, 1);
        uint32_t l1_addr1 = get_write_ptr(cb_id_in1);
        noc_async_read(src1_addr + (i * 1024), l1_addr1, 1024);
        
        // Ensure data is landed before pushing to compute
        noc_async_read_barrier();
        
        cb_push_back(cb_id_in0, 1);
        cb_push_back(cb_id_in1, 1);
    }
}