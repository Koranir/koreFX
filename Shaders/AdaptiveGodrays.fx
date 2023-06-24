#include "ReShade.fxh"

// From LightFinder.fx:
// SOURCE_REGIONS_X
// SOURCE_REGIONS_Y

#ifndef SOURCE_REGIONS_X
    #define SOURCE_REGIONS_X 16
#endif

#ifndef SOURCE_REGIONS_Y
    #define SOURCE_REGIONS_Y 9
#endif

#ifndef RAY_SAMPLES
    #define RAY_SAMPLES 10
#endif

uniform float Intensity
<
	ui_label = "Intensity";
	ui_tooltip = "Default: 1.0";
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.05;
> = 1.0;

uniform float Curve
<
	ui_label = "Curve";
	ui_tooltip = "Default: 3.0";
	ui_type = "slider";
	ui_min = 1.0;
	ui_max = 5.0;
	ui_step = 0.1;
> = 3.0;

uniform float Scale
<
	ui_label = "Scale";
	ui_tooltip = "Default: 10.0";
	ui_type = "slider";
	ui_min = 1.0;
	ui_max = 10.0;
	ui_step = 0.1;
> = 10.0;

uniform float Delay
<
	ui_label = "Delay";
	ui_tooltip = "Default: 1.0";
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 10.0;
	ui_step = 0.1;
> = 1.0;

uniform float ClampBelow
<
	ui_label = "Clamp";
	ui_tooltip = "Clamps Below";
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_step = 0.01;
> = 0.5;

texture region_brightest {
    Width = SOURCE_REGIONS_X;
    Height = SOURCE_REGIONS_Y;
    Format = RGBA8;
};
sampler bright_region_sampler {
    Texture = region_brightest;
};

float2 ScaleCoord(float2 uv, float2 scale, float2 pivot)
{
	return (uv - pivot) * scale + pivot;
}

float4 ZoomBlur(sampler sp, float2 tex_coord, float2 pivot, float scale, int samples)
{
	float invScale = rcp(scale);
	float4 color = tex2D(sp, tex_coord);
	//float4 maxColor = color;

	for (int i = 1; i < samples; ++i)
	{
		tex_coord = ScaleCoord(tex_coord, invScale, pivot);

		float4 pixel = tex2D(sp, tex_coord);
		color += pixel;
		//maxColor = max(maxColor, pixel);
	}

	color /= samples;
	//color = lerp(color, maxColor, color);

	return color;
}

float4 godrays(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float4 base_color = tex2D(ReShade::BackBuffer, tex_coord);
    float4 color = float4(0, 0, 0, 0);

    float scale = 1.0 + (Scale - 1.0) / RAY_SAMPLES * 0.1;
    int i = 0;

    for(uint x = 0; x < SOURCE_REGIONS_X; x++) {
        for(uint y = 0; x < SOURCE_REGIONS_Y; y++) {
            float3 light = tex2Dfetch(bright_region_sampler, uint2(SOURCE_REGIONS_X, SOURCE_REGIONS_Y)).xyz;
            if(light.z > ClampBelow) {
                float2 pivot = light.xy;

                float4 rays = ZoomBlur(ReShade::BackBuffer, tex_coord, pivot, scale, RAY_SAMPLES);
                rays.rgb = pow(abs(rays.rgb), Curve);

                color += 1.0 - (1.0 - base_color) * (1.0 - rays * Intensity);
                i++;
            }
        }
    }

    color /= i;

	return color;
}

technique AdaptiveGodrays
<
    ui_tooltip = "Enable LightFinder.fx before this.";
>
{
    pass Godrays {
        VertexShader = PostProcessVS;
        PixelShader = godrays;
    }
}