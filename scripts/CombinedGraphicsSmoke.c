/* Verify a game/launcher can use Direct3D and Zink in the same process. */
#define main scotch_d3d_probe
#include "D3DMetalSmoke.c"
#undef main
#define main scotch_gl_probe
#include "ZinkSmoke.c"
#undef main
int main(void) {
    char *args[] = {"ScotchCombinedGraphicsSmoke", "--d3d11"};
    int d3d = scotch_d3d_probe(2, args);
    if (d3d)
        return d3d;
    return scotch_gl_probe();
}
