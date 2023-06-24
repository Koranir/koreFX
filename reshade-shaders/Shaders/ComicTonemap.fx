#include "kore.fxh"

float map(float x) {
    return x + sin(x * 100.) * 0.01;
}

float4 tonemap PPARGS {
    float4 col = tex2D(ReShade::BackBuffer, tex_coord);
    col.x = map(col.x);
    col.y = map(col.y);
    col.z = map(col.z);
    return col;
}

technique Comic_Tonemap {
    pass {
        VertexShader = PostProcessVS;
        PixelShader = tonemap;
    }
}