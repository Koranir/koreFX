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
    sampler luma_average {
        Texture = average_luma;
    };
}

uniform float avg_mul <
    ui_label = "Multiplier";
    ui_type = "slider";
    ui_tooltip = "Higher means more deleting.";
    ui_min = 0.;
    ui_max = 2.;
> = .6;

float4 g_than_avg(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float avg = tex2Dfetch(kore::luma_average, 0).r;
    float pixel_luma = dot(tex2D(ReShade::BackBuffer, tex_coord).rgb, 0.333);
    if(pixel_luma > avg * avg_mul) {
        return float4(tex2D(ReShade::BackBuffer, tex_coord).rgb, 1);
    } else {
        return 0.;
    }
}

technique Greater_Than_Average {
    pass greater_than {
        VertexShader = PostProcessVS;
        PixelShader = g_than_avg;
    }
}
