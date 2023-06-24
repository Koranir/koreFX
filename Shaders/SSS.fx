#include "ReShade.fxh"

namespace Deferred 
{
	texture NormalsTex {
		Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;Format = RG8;
    };
	sampler normal_sampler {
        Texture = NormalsTex;
    };
	
	texture MotionVectorsTex {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RG16F;
    };
	sampler motion_sampler {
        Texture = MotionVectorsTex;
    };

    float3 decode_octahedral(float2 octahedral_encoded) {
        octahedral_encoded = octahedral_encoded * 2.0 - 1.0;
        float3 vec = float3(octahedral_encoded.xy, 1.0 - abs(octahedral_encoded.x) - abs(octahedral_encoded.y));
        float t = saturate(-vec.z);
        vec.xy += vec.xy >= 0.0.xx ? -t.xx : t.xx;
        return normalize(vec);
    }

    float3 get_normal(float2 tex_coord) {
        return decode_octahedral(tex2D(normal_sampler, tex_coord).xy);
    }

    float2 get_motion(float2 tex_coord) {
        return tex2D(motion_sampler, tex_coord).xy;
    }
}

#ifndef SHADOW_DOWNSAMPLE_LEVEL
    #define SHADOW_DOWNSAMPLE_LEVEL 2
#endif

#ifndef SOURCE_SEARCH_LOD
    #define SOURCE_SEARCH_LOD 4
#endif

#ifndef SOURCE_REGIONS_X
    #define SOURCE_REGIONS_X 16
#endif

#ifndef SOURCE_REGIONS_Y
    #define SOURCE_REGIONS_Y 9
#endif

#ifndef DEPTH_MULTIPLIER
    #define DEPTH_MULTIPLIER 1
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

uniform int shadow_quality
<
    ui_label = "Quality";
    ui_tooltip = "The deafult is more than enough, but you can add more.";
    ui_min  = 8;
    ui_max = 64;
    ui_type = "slider";
> = 10;

uniform float depth_offset
<
    ui_label = "Offset";
    ui_type = "drag";
    ui_tooltip = "To prevent shadowing artifacts.\nTry to keep to a minimum.";
    ui_min = -5.;
    ui_max = 25.;
    ui_step = 0.01;
> = 2.;

uniform float assumed_thickness
<
    ui_label = "Object Thickness";
    ui_type = "drag";
    ui_tooltip = "This thickness will be used to cut off shadows from becoming too large.\nJust drag this till it looks good.";
    ui_min = 0.;
    ui_max = 1000.;
    ui_step = 1;
> = 180.;

uniform float intensity
<
    ui_label = "Shadow Intensity";
    ui_type = "slider";
    ui_tooltip = "Shadow darkness.";
    ui_min = 0.;
    ui_max = 100.;
> = 50.;

texture back_buffer : COLOR;
sampler back_sampler {
    Texture = back_buffer;
    SRGBTexture = true;
};

texture region_brightest {
    Width = SOURCE_REGIONS_X;
    Height = SOURCE_REGIONS_Y;
    Format = RGBA8;
};
sampler bright_region_sampler {
    Texture = region_brightest;
};

texture shadow_tex {
    Width = BUFFER_WIDTH / SHADOW_DOWNSAMPLE_LEVEL;
    Height = BUFFER_HEIGHT / SHADOW_DOWNSAMPLE_LEVEL;
    Format = R8;
};
sampler shadow_sampler {
    Texture = shadow_tex;
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
            float l = length(tex2Dlod(back_sampler, float4(new_coord, 0, SOURCE_SEARCH_LOD)).rgb);
            if(l > brightest.z) {
                brightest = float3(new_coord, l);
            }
        }
    }

    return float4(float3(brightest.xy, brightest.z / sqrt(3)), 1);
}

float calculate_shadow(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {

    float fragment_depth = tex2D(ReShade::DepthBuffer, tex_coord).r;
    float3 fragment_position = UVtoPos(tex_coord, fragment_depth);

    float shadowed = 0.;

    for(uint x = 0; x < SOURCE_REGIONS_X; x++) {
        for(uint y = 0; y < SOURCE_REGIONS_Y; y++) {
            float3 light = tex2Dfetch(bright_region_sampler, uint2(x, y)).xyz;
            float light_depth = tex2D(ReShade::DepthBuffer, light.xy).r;
            float3 light_pos = UVtoPos(light.xy, light_depth);

            for(uint i = 1; i < shadow_quality; i++) {
                float traveled_percentage = float(i) / shadow_quality;
                float2 traveled_coord = lerp(light.xy, tex_coord, traveled_percentage);
                float traveled_depth = tex2D(ReShade::DepthBuffer, traveled_coord).r;
                float3 traveled_pos = UVtoPos(traveled_coord, traveled_depth);
                float3 lerped_pos = lerp(light_pos, fragment_position, traveled_percentage);

                float depth_difference = lerped_pos.z - traveled_pos.z;
                if(
                    (depth_difference > depth_offset / 100) &&
                    ((depth_difference - assumed_thickness / 100) < depth_offset)
                ) {
                    shadowed += light.z * intensity / (shadow_quality * SOURCE_REGIONS_X * SOURCE_REGIONS_Y);
                }
            }
        }
    }

    return shadowed;
};

float4 display_debug(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    for(uint x = 0; x < SOURCE_REGIONS_X; x++) {
        for(uint y = 0; y < SOURCE_REGIONS_Y; y++) {
            float2 light_uv = tex2Dfetch(bright_region_sampler, uint2(x, y)).xy;
            if(length(light_uv - tex_coord) < 0.01) {
                return tex2Dfetch(bright_region_sampler, uint2(x, y)).z;
            }
        }
    }
    return tex2D(ReShade::BackBuffer, tex_coord);
}

technique ScreenSpaceShadows {
    pass FindLightSources {
        VertexShader = PostProcessVS;
        PixelShader = get_region_brightest;
        RenderTarget = region_brightest;
    }
    pass shadow_map {
        VertexShader = PostProcessVS;
        PixelShader = calculate_shadow;
        RenderTarget = shadow_tex;
    }
#if DEBUG_LIGHT_POS
    pass display_debug {
        VertexShader = PostProcessVS;
        PixelShader = display_debug;
    }
#endif
}
