#include "ReShadeUI.fxh"

#include "ReShade.fxh"

#ifndef DownSamplerSampleDownRate
    #define DownSamplerSampleDownRate 16
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

uniform int Quality <
    ui_type = "drag";
    ui_min = 1;
    ui_max = 100;
> = 4;

uniform float Divisor <
    ui_type = "drag";
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

texture DownSamplerSampleDownRated { Width = BUFFER_WIDTH / DownSamplerSampleDownRate; Height = BUFFER_HEIGHT / DownSamplerSampleDownRate; Format = RGBA8;};
sampler DownSamplerSampleDownRater { Texture = DownSamplerSampleDownRated; };

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

void getLights(in float4 position : SV_Position, in float2 texCoord : TexCoord, out float4 color : SV_Target)
{
    color = float4(0, 0, 0, 0);
    if(length(tex2D(ReShade::BackBuffer, texCoord).rgb) > Threshold)
    {
        color = tex2D(ReShade::BackBuffer, texCoord).rgb;
        color.rgb = (color.rgb*Saturation) + ((color.r+color.g+color.b)/3)*(1-Saturation);
        color.a = 1.;
    }
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
            if (tex2D(DownSamplerSampleDownRater, coord).a == 1.)
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
                        color += 1.- tex2D(DownSamplerSampleDownRater, coord).rgb;
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
    color.rgb = sqrt(color.rgb);

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
    color = tex2D(ReShade::BackBuffer, texCoord) - tex2D(brightSampler, texCoord).rgb * Intensity;
}

technique ScreenSpaceShadows
{

    pass DownSamplerSampleDownRatedBackBufferPass
    {
        VertexShader = PostProcessVS;
        PixelShader = getLights;
        RenderTarget = DownSamplerSampleDownRated;
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
