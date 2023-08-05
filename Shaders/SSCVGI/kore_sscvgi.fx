#include "../kore.fxh"

#ifndef sscvgi_downscale
    #define sscvgi_downscale 1
#endif

#ifndef sscvgi_smallao
    #define sscvgi_smallao 0
#endif

uniform float radius_2 <
    ui_type = "slider";
    ui_label = "Radius";
    ui_min = 0.01;
    ui_max = 6.;
> = 1.5;
uniform float intensity <
    ui_type = "slider";
    ui_label = "Intensity";
    ui_min = 0.;
    ui_max = 2.;
> = .8;
uniform float saturation <
    ui_type = "slider";
    ui_label = "Saturation";
    ui_min = 0.;
    ui_max = 4.;
> = 2.;
uniform float og_col <
    ui_type = "slider";
    ui_label = "Original Lighting";
    ui_min = 0.;
    ui_max = 1.;
> = .7;
uniform float thickness <
    ui_type = "slider";
    ui_label = "Thickness";
    ui_min = 0.;
    ui_max = 3.;
> = 1.8;
uniform float depth_mask_min <
    ui_type = "slider";
    ui_label = "Depth Fadeout Min";
    ui_min = 0.;
    ui_max = 1.;
> = 0.1;
uniform float depth_mask_max <
    ui_type = "slider";
    ui_label = "Depth Fadeout Max";
    ui_min = 0.;
    ui_max = 1.;
> = 0.99;
uniform float samples_scaling <
    ui_type = "slider";
    ui_label = "Samples";
    ui_min = 0.;
    ui_max = 1.;
> = 0.5;

// http://lolengine.net/blog/2013/07/27/rgb-to-hsv-in-glsl
float3 rgb2hsv(float3 c)
{
  float4 K = float4(0.f, -1.f / 3.f, 2.f / 3.f, -1.f);
  float4 p = c.g < c.b ? float4(c.bg, K.wz) : float4(c.gb, K.xy);
  float4 q = c.r < p.x ? float4(p.xyw, c.r) : float4(c.r, p.yzx);

  float d = q.x - min(q.w, q.y);
  float e = 1e-10;
  return float3(abs(q.z + (q.w - q.y) / (6.f * d + e)), d / (q.x + e), q.x);
}

float3 hsv2rgb(float3 c)
{
  float4 K = float4(1.f, 2.f / 3.f, 1.f / 3.f, 3.f);
  float3 p = abs(frac(c.xxx + K.xyz) * 6.f - K.www);
  return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

float3 ACESFilm(float3 x)
{
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}

texture backBuffer {
    Width = BUFFER_WIDTH / sscvgi_downscale;
    Height = BUFFER_HEIGHT / sscvgi_downscale;
};
sampler backSampler {
    Texture = backBuffer;
    // SRGBTexture = true;
};

#define sscvgic(val) texture sscvgi_cascade_##val## {\
    Width = BUFFER_WIDTH / sscvgi_downscale / val * 4;\
    Height = BUFFER_HEIGHT / sscvgi_downscale / val * 4;\
};\
sampler sc##val##s {\
    Texture = sscvgi_cascade_##val##;\
};

#if sscvgi_smallao
texture sscvgi_cascade_1 {
    Width = BUFFER_WIDTH / sscvgi_downscale * 2;
    Height = BUFFER_HEIGHT / sscvgi_downscale * 2;
};
sampler sc1s {
    Texture = sscvgi_cascade_1;
};

sscvgic(2);
#endif
sscvgic(3);
sscvgic(4);
sscvgic(5);
sscvgic(6);
sscvgic(7);
sscvgic(8);

texture sscvgi_cascade_combined {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    MipLevels = 2;
};
sampler sccs {
    Texture = sscvgi_cascade_combined;
};

float4 sample_cascade(float2 uv, uint cascade) {
    const uint samples = 4 * pow(1 + pow(samples_scaling, 2), cascade);
    const float radius = radius_2 * 0.005 * pow(1.414, cascade);
    const float uvDepth = tex2Dlod(ReShade::DepthBuffer, float4(uv, 0, cascade));
    const float4 uvCol = tex2Dlod(backSampler, float4(uv, 0, cascade));
    float4 output = float4(0, 0, 0, 0);
    for(float angle = 0.; angle < 6.28; angle += 6.29 / samples) {
        const float2 sampleUV = float2(uv.x + sin(angle) * radius, uv.y + cos(angle) * radius);
        const float cascade_depth = tex2Dlod(ReShade::DepthBuffer, float4(sampleUV, 0, cascade)).r;
        for(uint i = 0; i < cascade + 1; i++) {
            const float raversed = float(i) / cascade + 2;
            const float2 testUV = lerp(uv, sampleUV, raversed);
            const float diff = uv_pos(sampleUV, tex2Dlod(ReShade::DepthBuffer, float4(sampleUV, 0, cascade)).r).z - uv_pos(sampleUV, lerp(uvDepth, cascade_depth, raversed)).z;
            output += ((diff < 0 || diff > pow(thickness, 5))) ? tex2Dlod(backSampler, float4(sampleUV, 0, cascade)) : -tex2Dlod(backSampler, float4(sampleUV, 0, cascade)) / 4.;
        }
    }
    return output / samples / cascade;
}

float4 ssc_1 PPARGS {
    return sample_cascade(tex_coord, 0);
}

float4 ssc_2 PPARGS {
    return sample_cascade(tex_coord, 1);
}

float4 ssc_3 PPARGS {
    return sample_cascade(tex_coord, 2);
}

float4 ssc_4 PPARGS {
    return sample_cascade(tex_coord, 3);
}

float4 ssc_5 PPARGS {
    return sample_cascade(tex_coord, 4);
}

float4 ssc_6 PPARGS {
    return sample_cascade(tex_coord, 5);
}

float4 ssc_7 PPARGS {
    return sample_cascade(tex_coord, 6);
}

float4 ssc_8 PPARGS {
    return sample_cascade(tex_coord, 7);
}

float4 ssc_c PPARGS {
    float3 mul;
    mul += tex2D(sc8s, tex_coord).rgb;
    mul += tex2D(sc7s, tex_coord).rgb;
    mul += tex2D(sc6s, tex_coord).rgb;
    mul += tex2D(sc5s, tex_coord).rgb;
    mul += tex2D(sc4s, tex_coord).rgb;
    mul += tex2D(sc3s, tex_coord).rgb;
#if sscvgi_smallao
    mul += tex2D(sc2s, tex_coord).rgb;
    mul += tex2D(sc1s, tex_coord).rgb;
    float3 hsv = rgb2hsv(mul / 6.);
#else
    float3 hsv = rgb2hsv(mul / 4.);
#endif
    hsv.y *= saturation;
    return float4(hsv2rgb(hsv), 1.);// - pow(tex2D(ReShade::BackBuffer, tex_coord).rgb + l_contribution_2, l_contribution), 1);
}

float4 ssc_m PPARGS {
    float4 col = tex2D(ReShade::BackBuffer, tex_coord);
    const float depth = linearize(tex2D(ReShade::DepthBuffer, tex_coord).r);
    return lerp(
        col,
        float4((col * og_col + length(col.rgb) * (tex2Dlod(sccs, float4(tex_coord, 0, 2)) - .2) * intensity).rgb, 1.),
        pow(
            saturate((depth_mask_max - depth) * (1. / sqrt(depth_mask_max - depth_mask_min)))
            , 1
        )
    );
}

float4 bbb PPARGS {
    return float4(ACESFilm(tex2D(ReShade::BackBuffer, tex_coord).rgb).rgb, 1.);
}

technique SSCVGI {
    pass backBufferBlit {
        VertexShader = PostProcessVS;
        PixelShader = bbb;
        RenderTarget = backBuffer;
    }
#if sscvgi_smallao
    pass ssc1p {
        VertexShader = PostProcessVS;
        PixelShader = ssc_1;
        RenderTarget = sscvgi_cascade_1;
    }
    pass ssc2p {
        VertexShader = PostProcessVS;
        PixelShader = ssc_2;
        RenderTarget = sscvgi_cascade_2;
    }
#endif
    pass ssc3p {
        VertexShader = PostProcessVS;
        PixelShader = ssc_3;
        RenderTarget = sscvgi_cascade_3;
    }
    pass ssc4p {
        VertexShader = PostProcessVS;
        PixelShader = ssc_4;
        RenderTarget = sscvgi_cascade_4;
    }
    pass ssc5p {
        VertexShader = PostProcessVS;
        PixelShader = ssc_5;
        RenderTarget = sscvgi_cascade_5;
    }
    pass ssc6p {
        VertexShader = PostProcessVS;
        PixelShader = ssc_6;
        RenderTarget = sscvgi_cascade_6;
    }
    pass ssc7p {
        VertexShader = PostProcessVS;
        PixelShader = ssc_7;
        RenderTarget = sscvgi_cascade_7;
    }
    pass ssc8p {
        VertexShader = PostProcessVS;
        PixelShader = ssc_8;
        RenderTarget = sscvgi_cascade_8;
    }
    pass ssccp {
        VertexShader = PostProcessVS;
        PixelShader = ssc_c;
        RenderTarget = sscvgi_cascade_combined;
    }
    pass ssc_mp {
        VertexShader = PostProcessVS;
        PixelShader = ssc_m;
    }
}