#include <stdint.h>
#include "dataflow_api.h"

void kernel_main() {
    uint32_t src0_addr  = get_arg_val<uint32_t>(0);
    uint32_t src1_addr  = get_arg_val<uint32_t>(1);
    uint32_t num_tiles  = get_arg_val<uint32_t>(2); // 50240 / 32 = 1570

    constexpr uint32_t cb_id_in0 = 0;
    constexpr uint32_t cb_id_in1 = 1;

    // Load tiles from DRAM into Local L1 Cache
    for (uint32_t i = 0; i < num_tiles; ++i) {
        cb_reserve_back(cb_id_in0, 1);
        uint32_t l1_write_addr0 = get_write_ptr(cb_id_in0);
        noc_async_read(src0_addr + (i * 1024), l1_write_addr0, 1024); // 1024 bytes per 32x32 tile
        noc_async_read_barrier();
        cb_push_back(cb_id_in0, 1);

        cb_reserve_back(cb_id_in1, 1);
        uint32_t l1_write_addr1 = get_write_ptr(cb_id_in1);
        noc_async_read(src1_addr + (i * 1024), l1_write_addr1, 1024);
        noc_async_read_barrier();
        cb_push_back(cb_id_in1, 1);
    }
}
