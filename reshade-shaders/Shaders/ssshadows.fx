#include "ReShadeUI.fxh"

#include "ReShade.fxh"

#ifndef DownSamplerSampleDownRate
    #define DownSamplerSampleDownRate 16
#endif

#ifndef LightColorAlphaBoost
    #define LightColorAlphaBoost 2.
#endif

uniform float Threshold <
    ui_type = "drag";
    ui_step = 0.01;
    ui_min = 0.;
    ui_max = 1.5;
> = 1.;

uniform float Intensity <
    ui_type = "drag";
    ui_min = 0.;
    ui_max = 10.;
> = 1.;

uniform float Offset <
    ui_type = "drag";
    ui_step = 0.01;
    ui_min = -1.;
    ui_max = 1.;
> = 0.;

uniform float Influence <
    ui_type = "drag";
    ui_step = 0.05;
    ui_min = 0.;
    ui_max = 1.;
> = 0.;

uniform int Quality <
    ui_type = "drag";
    ui_min = 1;
    ui_max = 100;
> = 4;

uniform float Divisor <
    ui_type = "drag";
    ui_step = 1.;
    ui_min = 0.;
    ui_max = 100.;
> = 1.;

uniform float Thickness <
    ui_type = "drag";
    ui_step = 0.5;
    ui_min = 0.;
    ui_max = 1000.;
> = 10.;

uniform float Saturation <
    ui_type = "drag";
    ui_min = 0.;
    ui_max = 5.;
> = 1.;

uniform float Exposure <
    ui_type = "drag";
    ui_step = 0.1;
    ui_min = 0.;
    ui_max = 2.;
> = 1.;

uniform int Method <
    ui_type = "drag";
    ui_min = 0;
    ui_max = 2;
> = 0;

texture downsampledblur1 { Width = BUFFER_WIDTH / DownSamplerSampleDownRate; Height = BUFFER_HEIGHT / DownSamplerSampleDownRate; Format = RGBA8; };
sampler dsb1sampler {Texture = downsampledblur1;};

texture downsampledblur2 { Width = BUFFER_WIDTH / DownSamplerSampleDownRate; Height = BUFFER_HEIGHT / DownSamplerSampleDownRate; Format = RGBA8; };
sampler dsb2sampler {Texture = downsampledblur2;};

texture DownSamplerSampleDownRated { Width = BUFFER_WIDTH / DownSamplerSampleDownRate; Height = BUFFER_HEIGHT / DownSamplerSampleDownRate; Format = RGBA8;};
sampler DownSamplerSampleDownRater { Texture = DownSamplerSampleDownRated; };

texture lightBlur { Width = BUFFER_WIDTH / DownSamplerSampleDownRate; Height = BUFFER_HEIGHT / DownSamplerSampleDownRate; Format = RGBA8;};
sampler lightBlurSampler { Texture = DownSamplerSampleDownRated; };

texture lightBlur2 { Width = BUFFER_WIDTH / DownSamplerSampleDownRate; Height = BUFFER_HEIGHT / DownSamplerSampleDownRate; Format = RGBA8;};
sampler lightBlur2Sampler { Texture = DownSamplerSampleDownRated; };

texture oldDownSampled { Width = BUFFER_WIDTH / DownSamplerSampleDownRate; Height = BUFFER_HEIGHT / DownSamplerSampleDownRate; Format = RGBA8; };
sampler oldDownSampler { Texture = oldDownSampled; };

texture loopSample { Width = BUFFER_WIDTH / DownSamplerSampleDownRate * 2; Height = BUFFER_HEIGHT / DownSamplerSampleDownRate * 2; Format = RGBA8; };
sampler loopSampler { Texture = loopSample; };

texture brightCorrection { Width = BUFFER_WIDTH / DownSamplerSampleDownRate * 2; Height = BUFFER_HEIGHT / DownSamplerSampleDownRate * 2; Format = RGBA8; };
sampler brightSampler { Texture = brightCorrection; };

texture maxBrightness {Width = 1; Height = 1; Format = R16F;};
sampler maxSampler { Texture = maxBrightness; };

float2 mix(float2 a, float2 b, float c)
{
    return float2( a.x + (b.x - a.x)*c, a.y + (b.y - a.y)*c );
}

float mix(float a, float b, float c)
{
    return a + (b - a)*c;
}

// linear to sRGB
float toneMap(float c)
{
    switch (Method) {
  	  case 0: // to sRGB gamma via filmic-like Reinhard-esque combination approximation
	    c = c / (c + .1667); // actually cancelled out the gamma correction!  Probably cheaper than even sRGB approx by itself.
		break; 	// considering I can't tell the difference, using full ACES+sRGB together seems quite wasteful computationally.
  	  case 1: // ACES+sRGB, which I approximated above
	    c = ((c*(2.51*c+.03))/(c*(2.43*c+.59)+.14));
	    c = pow(c, 1./2.2); // to sRGBish gamut
	    break;
  	  default: // sRGB approx by itself
	    c = pow(c, 1./2.2);
        break;
    }
    return c;
}

// combined exposure, tone map, gamma correction
float3 toneMap(float3 crgb, float exposure) // exposure = white point
{
    float4 c = float4(crgb, exposure);
    for (int i = 4; i-- > 0; ) c[i] = toneMap(c[i]);
    // must compute the tonemap operator of the exposure level, although optimizes out at compile time, 
    // do it all in float4 and then divide by alpha.
    return c.rgb / c.a;
}

void dsb1(in float4 position : SV_Position, in float2 texCoord : TexCoord, out float4 color : SV_Target)
{
    color = float4(0, 0, 0, 0);
    for (int x = -2; x <= 2; x++)
    {
        color += tex2D(ReShade::BackBuffer, texCoord + BUFFER_PIXEL_SIZE * float2(x, 0));
    }
    color /= 5;
}

void dsb2(in float4 position : SV_Position, in float2 texCoord : TexCoord, out float4 color : SV_Target)
{
    color = float4(0, 0, 0, 0);
    for (int x = -2; x <= 2; x++)
    {
        color += tex2D(dsb1sampler, texCoord + BUFFER_PIXEL_SIZE * float2(0, x));
    }
    color /= 5;
}

void getLights(in float4 position : SV_Position, in float2 texCoord : TexCoord, out float4 color : SV_Target)
{
    color = float4(0, 0, 0, 0);
    if(length(tex2D(dsb2sampler, texCoord).rgb) > Threshold)
    {
        color = tex2D(dsb2sampler, texCoord).rgb;
        color.rgb = (color.rgb*Saturation) + ((color.r+color.g+color.b)/3)*(1-Saturation);
        color.a = LightColorAlphaBoost;
    }
    color += (tex2D(oldDownSampler, texCoord) - color)*Influence;
}

void getOldLights(in float4 position : SV_Position, in float2 texCoord : TexCoord, out float4 color : SV_Target)
{
    color = tex2D(DownSamplerSampleDownRater, texCoord);
}

void lb1(in float4 position : SV_Position, in float2 texCoord : TexCoord, out float4 color : SV_Target)
{
    color = float4(0, 0, 0, 0);
    for (int x = -1; x <= 1; x++)
    {
        color += tex2D(DownSamplerSampleDownRater, texCoord + BUFFER_PIXEL_SIZE * DownSamplerSampleDownRate * float2(x, 0));
    }
    color /= 3;
}

void lb2(in float4 position : SV_Position, in float2 texCoord : TexCoord, out float4 color : SV_Target)
{
    color = float4(0, 0, 0, 0);
    for (int x = -1; x <= 1; x++)
    {
        color += tex2D(lightBlurSampler, texCoord + BUFFER_PIXEL_SIZE * DownSamplerSampleDownRate * float2(0, x));
    }
    color /= 3;
}

void getBrightness(in float4 position : SV_Position, in float2 texCoord : TexCoord, out float color : SV_Target)
{
    float maxBright = 0.;
    for (int x = 0; x < BUFFER_WIDTH / DownSamplerSampleDownRate * 2; x++)
    {
        for (int y = 0; y < BUFFER_HEIGHT / DownSamplerSampleDownRate * 2; y++)
        {
            float2 coord = BUFFER_PIXEL_SIZE * DownSamplerSampleDownRate  * 2 * float2(x, y);
            if(length(tex2D(loopSampler, coord).rgb) > maxBright)
            {
                maxBright = length(tex2D(loopSampler, coord).rgb);
            }
        }
    }
    color = maxBright;
}

void sss(in float4 position : SV_Position, in float2 texCoord : TexCoord, out float4 color : SV_Target)
{
    color = float4(0, 0, 0, 1);
    for (int x = 0; x < BUFFER_WIDTH / DownSamplerSampleDownRate; x++)
    {
        for (int y = 0; y < BUFFER_HEIGHT / DownSamplerSampleDownRate; y++)
        {
            float2 coord = BUFFER_PIXEL_SIZE * DownSamplerSampleDownRate * float2(x, y);
            if (tex2D(lightBlur2Sampler, coord).a > 0.)
            {
                float scanPixelDepth = tex2D(ReShade::DepthBuffer, coord).x;
                float coordPixelDepth = tex2D(ReShade::DepthBuffer, texCoord).x;
                for (int i = 1; i <= Quality; i++) {
                    float phase = (i*1.)/Quality;
                    float2 sampleCoord = mix(coord, texCoord, phase);
                    bool inShadow = false;
                    float depthChange = mix(scanPixelDepth, coordPixelDepth, phase) - tex2D(ReShade::DepthBuffer, sampleCoord).x;
                    if (depthChange > Offset/1000 && depthChange - Thickness / 10000 < Offset/1000)
                    {
                        inShadow = true;
                    }
                    if (inShadow)
                    {
                        color += 1.- tex2D(lightBlur2Sampler, coord).rgb;
                    }
                }
                /*float pixelDepth = tex2D(ReShade::DepthBuffer, coord).x;
                float realDepth = tex2D(ReShade::DepthBuffer, texCoord).x;
                bool light = true;
                for (int i = 1; i <= Quality; i++) {
                    float2 newCoord = mix(coord, texCoord, i/Quality);
                    if (tex2D(ReShade::DepthBuffer, newCoord).x > mix(pixelDepth, realDepth, i/Quality) + Offset){
                        light = false;
                        break;
                    }
                }
                if (light = true)
                {
                    color += tex2D(ReShade::BackBuffer, coord).rgb;
                }*/
            }
        }
    }
    color.rgb /= Quality;
    color.rgb /= Divisor;
    color.rgb = toneMap(color.rgb, Exposure);

/*
    color = float4(0, 0, 0, 1);
    for (int x = 0; x < BUFFER_WIDTH / DownSamplerSampleDownRate; x++)
    {
        for (int y = 0; y < BUFFER_HEIGHT / DownSamplerSampleDownRate; y++)
        {
            float2 coord = BUFFER_PIXEL_SIZE * DownSamplerSampleDownRate * float2(x, y);
            float pixelDepth = tex2D(ReShade::DepthBuffer, coord).x;
            float realDepth = tex2D(ReShade::DepthBuffer, texCoord).x;
            bool light = true;
            for (int i = 0; i < 4; i++) {
                float2 newCoord = mix(coord, texCoord, i/4.);
                if (tex2D(ReShade::DepthBuffer, newCoord).x > mix(pixelDepth, realDepth, i/4.) + Offset){
                    light = false;
                    break;
                }
            }
            if (light)
            {
                color += pow(tex2D(ReShade::BackBuffer, coord).rgb, 2.);
            }
        }
    }
    color.rgb /= Threshold;*/
}

void correctLight(in float4 position : SV_Position, in float2 texCoord : TexCoord, out float4 color : SV_Target)
{
    color = float4(0, 0, 0 ,1);
    color.rgb = tex2D(loopSampler, texCoord).rgb * (1/ tex2D(maxSampler, float2(0.5, 0.5)).x);
}

void comb(in float4 position : SV_Position, in float2 texCoord : TexCoord, out float4 color : SV_Target)
{
    color = tex2D(ReShade::BackBuffer, texCoord) - float4((tex2D(brightSampler, texCoord).rgb * Intensity), 0);
}

technique ScreenSpaceShadows
{
    pass Blur1
    {
        VertexShader = PostProcessVS;
        PixelShader = dsb1;
        RenderTarget = downsampledblur1;
    }

    pass Blur1
    {
        VertexShader = PostProcessVS;
        PixelShader = dsb2;
        RenderTarget = downsampledblur2;
    }

    pass mergeOld
    {
        VertexShader = PostProcessVS;
        PixelShader = getOldLights;
        RenderTarget = oldDownSampled;
    }

    pass DownSamplerSampleDownRatedBackBufferPass
    {
        VertexShader = PostProcessVS;
        PixelShader = getLights;
        RenderTarget = DownSamplerSampleDownRated;
    }

    pass lightBlur
    {
        VertexShader = PostProcessVS;
        PixelShader = lb1;
        RenderTarget = lightBlur;
    }

    pass lightBlur2
    {
        VertexShader = PostProcessVS;
        PixelShader = lb2;
        RenderTarget = lightBlur2;
    }

    pass lightPass
    {
        VertexShader = PostProcessVS;
        PixelShader = sss;
        RenderTarget = loopSample;
    }

    pass maxBrightness
    {
        VertexShader = PostProcessVS;
        PixelShader = getBrightness;
        RenderTarget = maxBrightness;
    }

    pass brightPass
    {
        VertexShader = PostProcessVS;
        PixelShader = correctLight;
        RenderTarget = brightCorrection;
    }

    pass mainPass
    {
        VertexShader = PostProcessVS;
        PixelShader = comb;
    }
}
