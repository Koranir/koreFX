#include "kore.fxh"

#ifndef LUMA_SIZE
    #define LUMA_SIZE 256
#endif 

#ifndef LUMA_SIZE_2_POW
    #define LUMA_SIZE_2_POW 8
#endif 

#ifndef LOCAL_LUMA
    #define LOCAL_LUMA 1
#endif 

#ifndef BLUR_GAUSS
    #define BLUR_GAUSS 1
#endif 

namespace kore {
    texture average_luma {
        Format = R16F;
    };
    #if LOCAL_LUMA
    texture local_luma {
        Width = LUMA_SIZE;
        Height = LUMA_SIZE;
        Format = R16F;
    };
    texture contrast_luma {
        Width = LUMA_SIZE;
        Height = LUMA_SIZE;
        Format = R16F;
    };
    #endif
}
texture luma_wide {
    Width = LUMA_SIZE;
    Height = LUMA_SIZE;
    Format = R16F;
    MipLevels = 8;
};
#if LOCAL_LUMA
texture luma_gauss_x {
    Width = LUMA_SIZE;
    Height = LUMA_SIZE;
    Format = R16F;
};
#endif
sampler wide_luma {
    Texture = luma_wide;
};
#if LOCAL_LUMA
sampler luma_g_x {
    Texture = luma_gauss_x;
};
sampler luma_local {
    Texture = kore::local_luma;
};
#endif
sampler luma_average {
    Texture = kore::average_luma;
};

#if LOCAL_LUMA
float gaussian_out <
    ui_label = "Blur Scale";
    ui_type = "drag";
> = 1;
#endif


float luma_wide_ps(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    return dot(tex2D(ReShade::BackBuffer, tex_coord).rgb, 0.333f);
}

#if LOCAL_LUMA
float sample_gauss(bool horizontal, float2 uv, sampler s) {
    const int iterations = 64;
    float out_f = 0;
    const float2 offset = horizontal ? float2(gaussian_out, 0) : float2(0, gaussian_out);
    [unroll]
    for(int i = 0; i < iterations; i++) {
        float traversed = ((float(i) / iterations) - 0.5) * 2;
        out_f += tex2D(s, uv + offset * traversed).r * (1. - abs(traversed));// * gaussian13[i];
    }
    return out_f / iterations * 2;
}

float luma_gaussian_x PPARGS {
    return sample_gauss(true, tex_coord, wide_luma);
}

float luma_gaussian_y PPARGS {
    return sample_gauss(false, tex_coord, luma_g_x);
}
#endif

float luma_average_ps(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    return tex2Dlod(wide_luma, float4(0.5, 0.5, 0, LUMA_SIZE_2_POW)).r;
}

#if LOCAL_LUMA
float luma_contrast_ps PPARGS {
    float f = tex2D(wide_luma, tex_coord).r - tex2D(luma_local, tex_coord).r;
    if(f > tex2Dfetch(luma_average, tex_coord).r) {
        return f;
    } else {
        return 0;
    }
}
#endif

technique Average_Luma {
    pass wide {
        VertexShader = PostProcessVS;
        PixelShader = luma_wide_ps;
        RenderTarget = luma_wide;
    }
    #if LOCAL_LUMA
    pass g_x {
        VertexShader = PostProcessVS;
        PixelShader = luma_gaussian_x;
        RenderTarget = luma_gauss_x;
    }
    pass g_y {
        VertexShader = PostProcessVS;
        PixelShader = luma_gaussian_y;
        RenderTarget = kore::local_luma;
    }
    #endif
    pass average {
        VertexShader = PostProcessVS;
        PixelShader = luma_average_ps;
        RenderTarget = kore::average_luma;
    }
    #if LOCAL_LUMA
    pass average {
        VertexShader = PostProcessVS;
        PixelShader = luma_contrast_ps;
        RenderTarget = kore::contrast_luma;
    }
    #endif
}
