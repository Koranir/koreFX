#include "ReShade.fxh"

#ifndef LUMA_SIZE
    #define LUMA_SIZE 256
#endif 

#ifndef LUMA_SIZE_2_POW
    #define LUMA_SIZE_2_POW 8
#endif 

namespace kore {
    texture average_luma {
        Format = R16F;
    };
}
texture luma_wide {
    Width = LUMA_SIZE;
    Height = LUMA_SIZE;
    Format = R16F;
    MipLevels = 8;
};
sampler wide_luma {
    Texture = luma_wide;
};
sampler luma_average {
    Texture = kore::average_luma;
};



float luma_wide_ps(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    return dot(tex2D(ReShade::BackBuffer, tex_coord).rgb, 0.333f);
}

float luma_average_ps(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    return tex2Dlod(wide_luma, float4(0.5, 0.5, 0, LUMA_SIZE_2_POW)).r;
}

technique Average_Luma {
    pass wide {
        VertexShader = PostProcessVS;
        PixelShader = luma_wide_ps;
        RenderTarget = luma_wide;
    }
    pass average {
        VertexShader = PostProcessVS;
        PixelShader = luma_average_ps;
        RenderTarget = kore::average_luma;
    }
}
