#include "ReShade.fxh"

uniform float mask_radius <
    ui_type = "drag";
    ui_label = "Blur Radius";
    ui_min = 0.0; ui_max = 100.0;
    ui_step = 0.01;
> = 1.0;

uniform int iterations <
    ui_type = "drag";
    ui_label = "Quality";
    ui_min = 1; ui_max = 8;
    ui_step = 1;
> = 2;

texture2D ui_mask < source = "UIMask.png"; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; MipLevels = 1; Format = R8; };
sampler2D ui_sampler { Texture = ui_mask; MipLODBias = 0; };

texture2D div2tex { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; MipLevels = 1; Format = RGBA8; };
sampler2D div2sampler { Texture = div2tex; MipLODBias = 0; };

texture2D div4tex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; MipLevels = 1; Format = RGBA8; };
sampler2D div4sampler { Texture = div2tex; MipLODBias = 0; };

texture2D div8tex { Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; MipLevels = 1; Format = RGBA8; };
sampler2D div8sampler { Texture = div2tex; MipLODBias = 0; };

#define nwbpo(x) float2(ReShade::PixelSize * -(1 << x), BUFFER_PIXEL_HEIGHT * (1 << x))
#define nebpo(x) float2(BUFFER_PIXEL_WIDTH * -(1 << x), BUFFER_PIXEL_HEIGHT * (1 << x))
#define swbpo(x) float2(BUFFER_PIXEL_WIDTH * -(1 << x), BUFFER_PIXEL_HEIGHT * (1 << x))
#define sebpo(x) float2(BUFFER_PIXEL_WIDTH * -(1 << x), BUFFER_PIXEL_HEIGHT * (1 << x))

#define EPSILON 0.01

float4 col_if_ui(sampler2D tex, float2 coords) {
    if(tex2D(ui_sampler, coords).r < EPSILON) {
        return float4(tex2D(tex, coords).rgb, 1);
    }
    return float4(0, 0, 0, 0);
}

float4 col_if_there(sampler2D tex, float2 coords) {
    if(length(tex2D(tex, coords).rgb) > EPSILON) {
        return float4(tex2D(tex, coords).rgb, 1);
    }
    return float4(0, 0, 0, 0);
}

float3 equalize(float4 inp) {
    if(inp.a > EPSILON) {
        return inp.rgb / inp.a;
    }
    else {
        return float3(0, 0, 0);
    }
}

float4 downsample2x(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
    float2 ne = ReShade::PixelSize * int2(1, 1) * mask_radius;
    float2 se = ReShade::PixelSize * int2(1, -1) * mask_radius;
    float2 sw = ReShade::PixelSize * int2(-1, -1) * mask_radius;
    float2 nw = ReShade::PixelSize * int2(-1, 1) * mask_radius;

    float4 total;
    for(int i = 0; i < iterations; i++) {
        float percentage = float(i) / iterations;
        total += col_if_ui(ReShade::BackBuffer, texcoord + ne * percentage);
        total += col_if_ui(ReShade::BackBuffer, texcoord + se * percentage);
        total += col_if_ui(ReShade::BackBuffer, texcoord + sw * percentage);
        total += col_if_ui(ReShade::BackBuffer, texcoord + nw * percentage);
    }

    return float4(equalize(total), 1.);
}

float4 downsample4x(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
    float2 ne = ReShade::PixelSize * int2(2, 2) * mask_radius;
    float2 se = ReShade::PixelSize * int2(2, -2) * mask_radius;
    float2 sw = ReShade::PixelSize * int2(-2, -2) * mask_radius;
    float2 nw = ReShade::PixelSize * int2(-2, 2) * mask_radius;

    float4 total;
    for(int i = 0; i < iterations; i++) {
        float percentage = float(i) / iterations;
        total = col_if_there(div2sampler, texcoord + ne * percentage);
        total += col_if_there(div2sampler, texcoord + se * percentage);
        total += col_if_there(div2sampler, texcoord + sw * percentage);
        total += col_if_there(div2sampler, texcoord + nw * percentage);
    }

    return float4(equalize(total), 1.);
}

float4 downsample8x(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
    float2 ne = ReShade::PixelSize * int2(4, 4) * mask_radius;
    float2 se = ReShade::PixelSize * int2(4, -4) * mask_radius;
    float2 sw = ReShade::PixelSize * int2(-4, -4) * mask_radius;
    float2 nw = ReShade::PixelSize * int2(-4, 4) * mask_radius;

    float4 total;
    for(int i = 0; i < iterations; i++) {
        float percentage = float(i) / iterations;
        total = col_if_there(div4sampler, texcoord + ne * percentage);
        total += col_if_there(div4sampler, texcoord + se * percentage);
        total += col_if_there(div4sampler, texcoord + sw * percentage);
        total += col_if_there(div4sampler, texcoord + nw * percentage);
    }

    return float4(equalize(total), 1.);
}

float4 remove_pass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
    return lerp(tex2D(ReShade::BackBuffer, texcoord), tex2D(div8sampler, texcoord), tex2D(ui_sampler, texcoord).r);
}

technique RemoveUIwMask {
    pass {
        VertexShader = PostProcessVS;
        PixelShader = downsample2x;
        RenderTarget = div2tex;
    }
    pass {
        VertexShader = PostProcessVS;
        PixelShader = downsample4x;
        RenderTarget = div4tex;
    }
    pass {
        VertexShader = PostProcessVS;
        PixelShader = downsample8x;
        RenderTarget = div8tex;
    }
    pass {
        VertexShader = PostProcessVS;
        PixelShader = remove_pass;
    }
}