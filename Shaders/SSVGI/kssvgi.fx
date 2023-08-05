#include "../kore.fxh"

uniform int interleavedPatternSize <
    ui_type = "drag";
    ui_label = "Interleaved Pattern Size";
> = 4;

uniform float3 ambientLight <
    ui_type = "color";
    ui_label = "Ambient Lighting";
> = float3(0.01, 0.01, 0.01);

uniform int dirsCount <
    ui_type = "drag";
    ui_label = "direction Count";
> = 4;

uniform float nearStepSize <
    ui_type = "drag";
    ui_label = "Step Size";
> = BUFFER_WIDTH / 1000f;

uniform float eps <
    ui_type = "drag";
    ui_label = "Epsilon";
> = 10e-1;

uniform float FOV <
    ui_type = "drag";
    ui_label = "FoV";
    ui_step = 1.;
> = 60;

texture blurredDirectLightTexture : COLOR;
sampler blurredDirectlightSampler {
    Texture = blurredDirectLightTexture;
    SRGBTexture = true;
};

texture kssvgi_tex {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
};
sampler kssvgi_sampler {
    Texture = kssvgi_tex;
};

float4 DepthMomentSample(float2 uv, float lod) {
    return float4(linearize(tex2Dlod(ReShade::DepthBuffer, float4(uv, 0, lod)).r), 0, 0, 1); // float4(linearize(tex2Dlod(ReShade::DepthBuffer, float4(uv, 0, lod)).r), 0, 0, 0);
}

float3 Unproject(float3 coords) {
    static const float3 uvtoprojADD = float3(-tan(radians(FOV) * 0.5).xx, 1.0) * float2(1.0, BUFFER_WIDTH * BUFFER_RCP_HEIGHT).yxx;
    static const float3 uvtoprojMUL = float3(-2.0 * uvtoprojADD.xy, 0.0);
    static const float4 projtouv    = float4(rcp(uvtoprojMUL.xy), -rcp(uvtoprojMUL.xy) * uvtoprojADD.xy); 
    return (coords.xyx * uvtoprojMUL + uvtoprojADD) * coords.z;
}

bool BoxRayCast(float2 rayStart, float2 rayDir, float2 boxMin, float2 boxMax, inout float paramMin, inout float paramMax)
{
    // r.dir is unit direction vector of ray
    float2 invDir = float2(1.0f / rayDir.x, 1.0f / rayDir.y);

    // lb is the corner of AABB with minimal coordinates - left bottom, rt is maximal corner
    // r.org is origin of ray
    float t1 = (boxMin.x - rayStart.x) * invDir.x;
    float t2 = (boxMax.x - rayStart.x) * invDir.x;
    float t3 = (boxMin.y - rayStart.y) * invDir.y;
    float t4 = (boxMax.y - rayStart.y) * invDir.y;

    paramMin = max(min(t1, t2), min(t3, t4));
    paramMax = min(max(t1, t2), max(t3, t4));

    return paramMin < paramMax;
}

float ComputeHorizonContribution(float3 eyeDir, float3 eyeTangent, float3 viewNorm, float minAngle, float maxAngle)
{
  return 0.25 * dot(eyeDir, viewNorm) * (-cos(2.0 * maxAngle) + cos(2.0 * minAngle))
    + 0.25 * dot(eyeTangent, viewNorm) * (2.0 * maxAngle - 2.0 * minAngle - sin(2.0 * maxAngle) + sin(2.0 * minAngle));
}

float4 ps_main PPARGS {
    // Get Framebuffer-Space and Screen-Space pixel coordinates.
    float2 centerPixelCoord = tex_coord * BUFFER_SCREEN_SIZE;
    float2 centerScreenCoord = tex_coord;
    // Get the World-Space normal direction for this pixel.
    float3 centerNormalSample = Deferred::get_normal(centerScreenCoord);
    // Get the Screen-Space depth for this pixel.
    float4 centerDepthSample = DepthMomentSample(centerScreenCoord, 0.0);
    // Get the direct lighting for this pixel.
    float4 centerlightSample = pow(tex2D(blurredDirectlightSampler, centerScreenCoord), 1);

    /*
    Normally: 
    vertex -> model matrix -> World Space -> view matrix -> projection matrix
    In ReShade:
    vertex -> model matrix -> World Space -> view matrix -> Final position
    We can fake an inveerse view matrix to get to 'world space'.

    In ReShade, we don't have access to the proection or view matrices.
    Instead, we can assum that we are already in view-space and pretend to form the world-space coordinates.
    This means that we need not Unproject().

    mat4 viewProjMatrix = projMatrix * viewMatrix;
    mat4 invViewProjMatrix = inverse(viewProjMatrix);
    mat4 invViewMatrix = inverse(viewMatrix);
    mat4 invProjMatrix = inverse(projMatrix);

    float3 camWorldPos = (invViewMatrix * vec4(0.0f, 0.0f, 0.0f, 1.0f)).xyz;
    
    float3 centerWorldPos = Unproject(float3(centerScreenCoord, centerDepthSample.r), invViewProjMatrix);
    float3 centerViewPos = Unproject(float3(centerScreenCoord, centerDepthSample.r), invProjMatrix);

    into:
    */

    // Our camera is in the center of the screen.
    float3 camWorldPos = float3(0, 0, 0);

    float3 centerWorldPos = Unproject(float3(centerScreenCoord, centerDepthSample.r));
    float3 centerViewPos = float3(centerScreenCoord, centerDepthSample.r);

    float3 centerWorldNorm = centerNormalSample.xyz;

    // const int interleavedPatternSize <-- is uniform already
    // float3 ambientLight <-- is uniform already

    // Pattern repeats itself every interleavedPatternSize pixels.
    int2 patternIndex = int2(centerPixelCoord) % interleavedPatternSize;

    int index = patternIndex.x + patternIndex.y * interleavedPatternSize;
    float2 distribution;
    // HammersleyNorm(i, N) where i = index, N = interleavedPatternSize^2
    {
        // principle: reverse bit sequence of i
        uint b =  ( uint(index) << 16) | (uint(index) >> 16 );
        b = (b & 0x55555555u) << 1u | (b & 0xAAAAAAAAu) >> 1u;
        b = (b & 0x33333333u) << 2u | (b & 0xCCCCCCCCu) >> 2u;
        b = (b & 0x0F0F0F0Fu) << 4u | (b & 0xF0F0F0F0u) >> 4u;
        b = (b & 0x00FF00FFu) << 8u | (b & 0xFF00FF00u) >> 8u;

        distribution = float2(index, b) / float2(16, float(0xffffffff));
    }
    float angOffset = distribution.x;
    float linOffset = distribution.y;

    // const int dirsCount <-- is uniform already
    // const float nearStepSize <-- is uniform already

    const float pi = 3.1415f;
    float pixelAngOffset = 2.0 * pi / float(dirsCount) * angOffset;

    float3 sumLight = float3(0.0, 0.0, 0.0);
    for(int dirIndex = 0; dirIndex < dirsCount; dirIndex++) {
        float dirPixelOffset = linOffset;
        float screenAng = pixelAngOffset + 2.0 * pi / float(dirsCount) * float(dirIndex);
        float2 screenPixelDir = float2(cos(screenAng), sin(screenAng));

        // float eps <-- is uniform already
        float3 offsetWorldPos = Unproject(float3((centerPixelCoord + screenPixelDir * eps) / BUFFER_SCREEN_SIZE, centerDepthSample.r));
        float3 eyeWorldDir = normalize(camWorldPos - centerWorldPos);
        float3 eyeWorldTangent = normalize(normalize(offsetWorldPos - camWorldPos) - normalize(centerWorldPos - camWorldPos));

        float maxHorizonAngle = -1e5;

        {
            float3 dirNormalPoint = cross(-cross(eyeWorldTangent, eyeWorldDir), centerWorldNorm);
            float2 projectedDirNormal = float2(dot(dirNormalPoint, eyeWorldDir), dot(dirNormalPoint, eyeWorldTangent));

            maxHorizonAngle = atan2(projectedDirNormal.y, projectedDirNormal.x);
        }

        float tmin, tmax;
        BoxRayCast(centerPixelCoord, screenPixelDir, float2(0.0, 0.0), BUFFER_SCREEN_SIZE, tmin, tmax);
        float totalPixelPath = abs(tmax);

        float3 dirLight = float3(0.0f, 0.0f, 0.0f);
        {
            dirLight = ambientLight * ComputeHorizonContribution(eyeWorldDir, eyeWorldTangent, centerWorldNorm, 0.0, maxHorizonAngle);
        }

        int iterationsCount = int(log(totalPixelPath / nearStepSize) / log(2.0f * pi / dirsCount + 1)) + 1;

        for(int offset = 0; offset < iterationsCount; offset++) {
            float pixelOffset = 0;
            pixelOffset = nearStepSize * pow(2.0f * pi / dirsCount + 1, offset + dirPixelOffset) + 1 - nearStepSize;
            float2 samplePixelCoord = centerPixelCoord + screenPixelDir * pixelOffset;
            float2 sampleScreenCoord = samplePixelCoord / BUFFER_SCREEN_SIZE;
            float sideMult = 1.0f;
            {
                float width = 0.1f;
                float invWidth = 1.0f / width;
                sideMult *= saturate((1.0f - sampleScreenCoord.x) * invWidth);
                sideMult *= saturate(sampleScreenCoord.x * invWidth);
                sideMult *= saturate((1.0f - sampleScreenCoord.y) * invWidth);
                sideMult *= saturate(sampleScreenCoord.y * invWidth);
            }

            float blurLodOffset = -2.0f;
            float depthLodMult = 0.5f;
            float colorLodMult = 0.5f;
            float depthLod = log(max(0, 2.0f * pi / dirsCount * (pixelOffset - 1.0f) * depthLodMult)) / log(2.0) + blurLodOffset;
            float colorLod = log(max(0, 2.0f * pi / dirsCount * (pixelOffset - 1.0f) * colorLodMult)) / log(2.0) + blurLodOffset;

            float4 depthSample = DepthMomentSample(sampleScreenCoord.xy, depthLod);
            float3 sampleWorldPos = camWorldPos + normalize(Unproject(float3(sampleScreenCoord, 1.0f)) - camWorldPos) * depthSample.r;

            float3 worldDelta = sampleWorldPos - centerWorldPos;
            float2 horizonPoint = float2(dot(eyeWorldDir, worldDelta), dot(eyeWorldTangent, worldDelta));

            float sampleHorizonAngle = atan2(horizonPoint.y, horizonPoint.x);

            if(sampleHorizonAngle < maxHorizonAngle) {
                float4 lightSample = pow(tex2Dlod(blurredDirectlightSampler, float4(sampleScreenCoord.xy, 0, colorLod)), 1);

                float horizonContribution = ComputeHorizonContribution(eyeWorldDir, eyeWorldTangent, centerWorldNorm, sampleHorizonAngle, maxHorizonAngle) * sideMult;

                dirLight += lightSample.rgb * horizonContribution;
                dirLight -= ambientLight * horizonContribution;
                maxHorizonAngle = sampleHorizonAngle;
            }
        }

        sumLight += 2. * dirLight / float(dirsCount);
    }

    return float4(sumLight, 1);
}

float4 ps_combine PPARGS {
    return tex2D(ReShade::BackBuffer, tex_coord) + tex2D(kssvgi_sampler, tex_coord);
}

technique KoreSSVGI <
    ui_tooltip =    "Port of Raikiri's SSVGI to ReShade.\n"
                    "https://github.com/Raikiri/LegitEngine";
> {
    pass main {
        PixelShader = ps_main;
        VertexShader = PostProcessVS;
        RenderTarget = kssvgi_tex;
    }
    pass combine {
        PixelShader = ps_combine;
        VertexShader = PostProcessVS;
    }
}