#include "kore.fxh"

#ifndef SOURCE_SEARCH_LOD
    #define SOURCE_SEARCH_LOD 4
#endif

#ifndef SOURCE_REGIONS_X
    #define SOURCE_REGIONS_X 16
#endif

#ifndef SOURCE_REGIONS_Y
    #define SOURCE_REGIONS_Y 9
#endif

#ifndef DEBUG_LIGHT_POS
    #define DEBUG_LIGHT_POS 0
#endif

#ifndef LOCAL_LUMA
    #define LOCAL_LUMA 1
#endif 

#ifndef LUMA_SIZE
    #define LUMA_SIZE 256
#endif 

#define SIM_FOV 70

float3 UVtoPos(float2 tex_coord, float depth)
{
	float3 scrncoord = float3(tex_coord.xy*2-1, depth * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
	scrncoord.xy *= scrncoord.z;
	scrncoord.x *= BUFFER_WIDTH / BUFFER_HEIGHT;
	scrncoord *= SIM_FOV * 3.1415926 / 180;
	
	return scrncoord;
}

uniform float debug_clamp
<
    ui_category = "Debug";
    ui_label = "Clamp Light Sources";
    ui_type = "slider";
    ui_tooltip =    "Stops lights beneath this intensity from displaying.\n"
                    "Intended for reference purposes.";
    ui_min = 0.;
    ui_max = 1.;
> = 0.1;

uniform float debug_pow_scale
<
    ui_category = "Debug";
    ui_label = "Scale Light Intensity";
    ui_type = "slider";
    ui_tooltip =    "Light intensity display is scaled by pow(<intensity>, 1/<this value>)";
    ui_min = 0.;
    ui_max = 10.;
> = 1.;

uniform float frame_blend
<
    ui_label = "Frame Continuity";
    ui_type = "slider";
    ui_tooltip =    "Frame Blending factor.\n"
                    "Can cause artifacting, but higher values stabilize.";
    ui_min = 0.;
    ui_max = 1.;
> = 0.1;

#if LOCAL_LUMA
namespace kore {
    texture average_luma {
        Format = R16F;
    };
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
    sampler luma_local {
    Texture = kore::local_luma;
    };
    sampler luma_average {
        Texture = kore::average_luma;
    };
    sampler luma_contrast {
        Texture = contrast_luma;
    };
}
#endif

texture region_brightest {
    Width = SOURCE_REGIONS_X;
    Height = SOURCE_REGIONS_Y;
    Format = RGBA8;
};
sampler bright_region_sampler {
    Texture = region_brightest;
};
texture prev_region_brightest {
    Width = SOURCE_REGIONS_X;
    Height = SOURCE_REGIONS_Y;
    Format = RGBA8;
};
sampler prev_bright_region_sampler {
    Texture = prev_region_brightest;
};

float4 get_region_brightest(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
#if LOCAL_LUMA
    static const float2 REGION_STEPS = float2(
        float(LUMA_SIZE) / SOURCE_REGIONS_X,
        float(LUMA_SIZE) / SOURCE_REGIONS_Y
    );
    static const float2 OFFSET = float2(
        1. / LUMA_SIZE,
        1. / LUMA_SIZE
    );
    static const float2 HALF_REGION = float2(
        1 / SOURCE_REGIONS_X / 2,
        1 / SOURCE_REGIONS_X / 2
    );
#else
    static const int2 REGION_STEPS = int2(
        BUFFER_WIDTH / pow(2, SOURCE_SEARCH_LOD) / SOURCE_REGIONS_X,
        BUFFER_HEIGHT / pow(2, SOURCE_SEARCH_LOD) / SOURCE_REGIONS_Y
    );
    static const float2 OFFSET = float2(
        1. / SOURCE_REGIONS_X / REGION_STEPS.x,
        1. / SOURCE_REGIONS_Y / REGION_STEPS.y
    );
    static const float2 HALF_REGION = float2(
        1 / SOURCE_REGIONS_X / 2,
        1 / SOURCE_REGIONS_X / 2
    );
#endif

    float3 brightest = float3(0, 0, 0);
    for(uint x = 0; x < REGION_STEPS.x; x++) {
        for(uint y = 0; y < REGION_STEPS.y; y++) {
            float2 new_coord = tex_coord + OFFSET * int2(x, y) - HALF_REGION;
            #if LOCAL_LUMA
            float l = tex2D(kore::luma_contrast, new_coord).r;
            #else
            float l = length(tex2Dlod(ReShade::BackBuffer, float4(new_coord, 0, SOURCE_SEARCH_LOD)).rgb) / 1.73;
            #endif
            if(l > brightest.z) {
                brightest = float3(new_coord, l);
            }
        }
    }

    // 0.7 ~= \frac{1}{\left(3\right)^{\frac{1}{3}}}
    brightest.z *= 0.7;
    brightest.z = pow(brightest.z, debug_pow_scale);
    float4 prev = tex2D(prev_bright_region_sampler, tex_coord);
    if(brightest.z > debug_clamp) {
        if(prev.x || prev.y || prev.z) {
            return lerp(float4(brightest, 1), prev, frame_blend);
        } else {
            return float4(brightest, 1);
        }
    }
    if(prev.z < 0.01) {
        prev.z = 0;
    }
    return lerp(float4(prev.xy, 0, 0), prev, frame_blend);
}

float4 display_debug(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    for(uint x = 0; x < SOURCE_REGIONS_X; x++) {
        for(uint y = 0; y < SOURCE_REGIONS_Y; y++) {
            float3 light = tex2Dfetch(bright_region_sampler, uint2(x, y)).xyz;
            if(length(light.xy - tex_coord) < 0.01) {
                if(!light.z) {
                    break;
                }
                return (float4(light.z, light.z, light.z, 1));
            }
        }
    }
    return tex2D(ReShade::BackBuffer, tex_coord);
}

float4 save_old PPARGS {
    return tex2D(bright_region_sampler, tex_coord);
}

technique LightFinder
<
    ui_tooltip =    "A shader that finds the lights in a scene.\n"
                    "The output is a SOURCE_REGIONS_X * SOURCE_REGIONS_Y sized texture that holds\n"
                    "the texture coordinates (r and g) and intensity (b).\n"
                    "Generally, you make a loop through all the coordinates, mask for the intensities\n"
                    "you want to operate on, then apply the code.";
>
{
    pass FindLightSources {
        VertexShader = PostProcessVS;
        PixelShader = get_region_brightest;
        RenderTarget = region_brightest;
    }
#if DEBUG_LIGHT_POS
    pass display_debug {
        VertexShader = PostProcessVS;
        PixelShader = display_debug;
    }
#endif
    pass save {
        VertexShader = PostProcessVS;
        PixelShader = save_old;
        RenderTarget = prev_region_brightest;
    }
}
