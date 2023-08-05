#ifndef BUFFER_HEIGHT
    #define BUFFER_HEIGHT 1
    #define BUFFER_WIDTH 1
    #define BUFFER_RCP_HEIGHT 1
    #define BUFFER_RCP_WIDTH 1
#endif

#include "ReShade.fxh"

#define PPARGS (float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET

#define fov 60

#define rad 0.0174533
#define deg 57.2958

// Legacy
float linearize(float depth) {
    return depth / (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - (depth * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - 1));
}

float3 uv_pos(float2 texcoord)
{
	float3 scrncoord = float3(texcoord.xy * 2 - 1, ReShade::GetLinearizedDepth(texcoord) * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
	scrncoord.xy *= scrncoord.z * (rad*fov*0.5);
	scrncoord.x *= BUFFER_ASPECT_RATIO;
	
	return scrncoord.xyz;
}

float3 uv_pos(float2 texcoord, float depth)
{
	float3 scrncoord = float3(texcoord.xy * 2 - 1, depth * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE);
	scrncoord.xy *= scrncoord.z * (rad * fov * 0.5);
	scrncoord.x *= BUFFER_ASPECT_RATIO;
	
	return scrncoord.xyz;
}

float2 pos_uv(float3 position)
{
	float2 screen_pos = position.xy;
	screen_pos.x /= BUFFER_ASPECT_RATIO;
	screen_pos /= position.z * rad * fov / 2;
	
	return screen_pos / 2 + 0.5;
}


// iMMERSE Launchpad Things
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

    float get_depth(float2 tex_coord) {
        return tex2D(motion_sampler, tex_coord).z;
    }

    float get_depth_lod(float2 tex_coord, float lod) {
        return tex2Dlod(motion_sampler, float4(tex_coord, 0, lod)).w;
    }

    float2 get_motion(float2 tex_coord) {
        return tex2D(motion_sampler, tex_coord).xy;
    }
}

static float gaussian5[5] = {1, 4, 6, 4, 1};
static float gaussian7[7] = {1, 6, 15, 20, 15, 6, 1};
static float gaussian9[9] = {1, 8, 28, 56, 70, 56, 28, 8, 1};
static float gaussian11[11] = {1, 10, 45, 120, 210, 235, 210, 130, 45, 10, 1};
static float gaussian13[13] = {1, 12, 66, 220, 495, 792, 924, 792, 495, 220, 66, 12, 1};
static float igaussian5[5] = {1, .25, 9, 11, 15};