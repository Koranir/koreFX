#include "ReShade.fxh"
#include "kore.fxh"

uniform float radius <
    ui_label = "Line Thickness";
    ui_type = "slider";
    ui_tooltip = "Radius of Depth Detection.";
    ui_min = 0.;
    ui_max = 1.;
> = .2;

uniform float div <
    ui_label = "Sensitivity";
    ui_type = "slider";
    ui_min = 0.;
    ui_max = 10.;
> = 2.;

uniform int combo_type <
    ui_label = "Mode";
    ui_type = "combo";
    ui_items = "Depth\0Normal\0Both\0";
> = 2;

float depth_difference PPARGS {
    const float s_gauss_kernel[3] = {1, 2, 1};
    const float gauss_kernel[5] = {1, 4, 6, 4, 1};
    float pixel_depth = 0;
    for(int x = -1; x <= 1; x++) {
        float traversed_x = x * radius / 600.;
        for(int y = -1; y <= 1; y++) {
            float traversed_y = y * radius / 600.;
            pixel_depth += s_gauss_kernel[x + 1] * s_gauss_kernel[y + 1] * linearize(tex2D(ReShade::DepthBuffer, float2(tex_coord.x + traversed_x, tex_coord.y + traversed_y)).r);
        }
    }
    pixel_depth /= 16;
    // float pixel_depth = linearize(tex2D(ReShade::DepthBuffer, tex_coord).r);
    float avg_depth = 0;
    for(int x = -2; x <= 2; x++) {
        float traversed_x = x * radius / 500.;
        for(int y = -2; y <= 2; y++) {
            float traversed_y = y * radius / 500.;
            avg_depth += gauss_kernel[x + 2] * gauss_kernel[y + 2] * linearize(tex2D(ReShade::DepthBuffer, float2(tex_coord.x + traversed_x, tex_coord.y + traversed_y)).r);
        }
    }
    // avg_depth /= pow(quality * 2, 2);
    return (1. - abs(((avg_depth / 256) - pixel_depth) * (div * 100) / linearize(tex2D(ReShade::DepthBuffer, tex_coord).r)));
}

float normal_difference PPARGS {
    const float gauss_kernel[5] = {1, 4, 6, 4, 1};
    float3 pixel_normal = Deferred::get_normal(tex_coord);
    float3 avg_nrm = float3(0, 0, 0);
    for(int x = -2; x <= 2; x++) {
        float traversed_x = x * radius / 500.;
        for(int y = -2; y <= 2; y++) {
            float traversed_y = y * radius / 500.;
            avg_nrm += gauss_kernel[x + 2] * gauss_kernel[y + 2] * Deferred::get_normal(float2(tex_coord.x + traversed_x, tex_coord.y + traversed_y));
        }
    }
    return pow(dot((avg_nrm / 256), pixel_normal), (div));// / Deferred::get_normal(tex_coord));
}

float4 diff_comb PPARGS {
    switch(combo_type) {
        case 0:
            return tex2D(ReShade::BackBuffer, tex_coord) * depth_difference(position, tex_coord);
        case 1:
            return tex2D(ReShade::BackBuffer, tex_coord) * normal_difference(position, tex_coord);
        default:
            return tex2D(ReShade::BackBuffer, tex_coord) * normal_difference(position, tex_coord) * depth_difference(position, tex_coord);
    }
}

technique Depth_Contrast_Lines {
    pass {
        VertexShader = PostProcessVS;
        PixelShader = diff_comb;
    }
}