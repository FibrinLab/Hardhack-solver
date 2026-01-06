#include <cstdint>
#include "compute_kernel_api/matmul_tiles.h"

namespace NAMESPACE {
void MAIN {
    uint32_t num_tiles = get_arg_val<uint32_t>(0);

    mm_init();

    for (uint32_t i = 0; i < num_tiles; ++i) {
        cb_wait_front(tt::CBIndex::c_0, 1);
        cb_wait_front(tt::CBIndex::c_1, 1);

        tile_regs_acquire();
        matmul_tiles(tt::CBIndex::c_0, tt::CBIndex::c_1, 0, 0, 0);
        tile_regs_commit();

        cb_pop_front(tt::CBIndex::c_0, 1);
        cb_pop_front(tt::CBIndex::c_1, 1);

        tile_regs_wait();
        cb_reserve_back(tt::CBIndex::c_16, 1);
        pack_tile(0, tt::CBIndex::c_16);
        cb_push_back(tt::CBIndex::c_16, 1);
        tile_regs_release();
    }
}
}
