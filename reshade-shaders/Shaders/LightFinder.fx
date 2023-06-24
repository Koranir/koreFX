#include "ReShade.fxh"

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

texture region_brightest {
    Width = SOURCE_REGIONS_X;
    Height = SOURCE_REGIONS_Y;
    Format = RGBA8;
};
sampler bright_region_sampler {
    Texture = region_brightest;
};

float4 get_region_brightest(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
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

    float3 brightest = float3(0, 0, 0);
    for(uint x = 0; x < REGION_STEPS.x; x++) {
        for(uint y = 0; y < REGION_STEPS.y; y++) {
            float2 new_coord = tex_coord + OFFSET * int2(x, y) - HALF_REGION;
            float l = length(tex2Dlod(ReShade::BackBuffer, float4(new_coord, 0, SOURCE_SEARCH_LOD)).rgb);
            if(l > brightest.z) {
                brightest = float3(new_coord, l);
            }
        }
    }

    // 0.7 ~= \frac{1}{\left(3\right)^{\frac{1}{3}}}
    return float4(float3(brightest.xy, brightest.z * 0.7), 1);
}

float4 display_debug(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    for(uint x = 0; x < SOURCE_REGIONS_X; x++) {
        for(uint y = 0; y < SOURCE_REGIONS_Y; y++) {
            float3 light = tex2Dfetch(bright_region_sampler, uint2(x, y)).xyz;
            light.z = pow(abs(light.z), 1/debug_pow_scale);
            if(length(light.xy - tex_coord) < 0.01) {
                if(light.z < debug_clamp) {
                    break;
                }
                return (float4(light.z, light.z, light.z, 1));
            }
        }
    }
    return tex2D(ReShade::BackBuffer, tex_coord);
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
}
