#include <stdint.h>
#include "dataflow_api.h"

// Reader Kernel: Streams A and B tiles from DRAM to L1
void kernel_main() {
    // Runtime Arguments
    uint32_t src0_addr  = get_arg_val<uint32_t>(0);
    uint32_t src1_addr  = get_arg_val<uint32_t>(1);
    uint32_t Kt         = get_arg_val<uint32_t>(2); // Number of tiles in K dimension (1570)

    // Circular Buffer IDs
    constexpr uint32_t cb_id_in0 = tt::CBIndex::c_0; // A
    constexpr uint32_t cb_id_in1 = tt::CBIndex::c_1; // B

    // Tile size (Bfloat16 = 2048 bytes for 32x32)
    uint32_t tile_bytes = get_tile_size(cb_id_in0);

    // Address Generators for Interleaved DRAM
    const InterleavedAddrGenFast<true> s0 = {
        .bank_base_address = src0_addr,
        .page_size = tile_bytes,
        .data_format = DataFormat::Float16_b
    };
    const InterleavedAddrGenFast<true> s1 = {
        .bank_base_address = src1_addr,
        .page_size = tile_bytes,
        .data_format = DataFormat::Float16_b
    };

    // Main Loop: Stream K tiles for the single output position
    for (uint32_t k = 0; k < Kt; k++) {
        // 1. Fetch Tile from A
        cb_reserve_back(cb_id_in0, 1);
        uint32_t l1_write_addr_in0 = get_write_ptr(cb_id_in0);
        noc_async_read_tile(k, s0, l1_write_addr_in0); 
        noc_async_read_barrier();
        cb_push_back(cb_id_in0, 1);

        // 2. Fetch Tile from B
        cb_reserve_back(cb_id_in1, 1);
        uint32_t l1_write_addr_in1 = get_write_ptr(cb_id_in1);
        noc_async_read_tile(k, s1, l1_write_addr_in1);
        noc_async_read_barrier();
        cb_push_back(cb_id_in1, 1);
    }
}