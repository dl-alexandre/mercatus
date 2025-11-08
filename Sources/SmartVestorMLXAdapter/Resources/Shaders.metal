#include <metal_stdlib>
using namespace metal;

kernel void passthrough(const device float* in [[ buffer(0) ]],
                        device float* out [[ buffer(1) ]],
                        uint id [[ thread_position_in_grid ]]) {
    out[id] = in[id];
}
