#include <stdint.h>
#include "dataflow_api.h"

// Writer Kernel: Writes result C from L1 to DRAM
void kernel_main() {
    uint32_t dst_addr = get_arg_val<uint32_t>(0);

    constexpr uint32_t cb_id_out = tt::CBIndex::c_16; // Output CB
    uint32_t tile_bytes = get_tile_size(cb_id_out);

    const InterleavedAddrGenFast<true> s = {
        .bank_base_address = dst_addr,
        .page_size = tile_bytes,
        .data_format = DataFormat::Float16_b
    };

    // Wait for the computed tile
    cb_wait_front(cb_id_out, 1);
    uint32_t l1_read_addr = get_read_ptr(cb_id_out);
    
    // Write to DRAM (Tile Index 0)
    noc_async_write_tile(0, s, l1_read_addr);
    noc_async_write_barrier();
    
    cb_pop_front(cb_id_out, 1);
}