#include <stdint.h>
#include "dataflow_api.h"

void kernel_main() {
    uint32_t dst_addr  = get_arg_val<uint32_t>(0);
    constexpr uint32_t cb_id_out = 16;

    // Wait for the result from the compute kernel
    cb_wait_front(cb_id_out, 1);
    uint32_t l1_read_addr = get_read_ptr(cb_id_out);

    // Write the 16x16 result (padded to 32x32 tile = 1024 bytes) back to DRAM
    noc_async_write(l1_read_addr, dst_addr, 1024);
    noc_async_write_barrier();

    cb_pop_front(cb_id_out, 1);
}
