/* Keep a real D3D12 import so the Auto inspector can identify the API. The
 * shared smoke implementation exercises actual D3D11/D3D12 GPU readback. */
#define main scotch_graphics_smoke_main
#include "D3DMetalSmoke.c"
#undef main
static create12_fn volatile required_d3d12_import = D3D12CreateDevice;
int main(int argc, char **argv) {
    if (!required_d3d12_import) return 1;
    return scotch_graphics_smoke_main(argc, argv);
}
