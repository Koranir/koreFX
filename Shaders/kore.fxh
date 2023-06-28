#include "ReShade.fxh"

#define PPARGS (float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET

float linearize(float depth) {
    return depth / (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - (depth * RESHADE_DEPTH_LINEARIZATION_FAR_PLANE - 1));
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
        return tex2D(normal_sampler, tex_coord).z;
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