#include "../kore.fxh"

texture blurred_light_tex : COLOR;
sampler blurred_light_sampler {
    Texture = blurred_light_tex;
    SRGBTexture = true;
};

texture ssvgi_tex {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
};
sampler ssvgi_sampler {
    Texture = ssvgi_tex;
};

uniform float FOV <ui_type = "drag"; ui_step = 1.;> = 60;

uniform float lintensity <ui_type = "drag";> = 1.;

uniform float3 ambient_light <
    ui_type = "color";
> = float3(0.01, 0.01, 0.01);

float2 proj_to_uv(float3 pos)
{
    //optimized math to simplify matrix mul
    static const float3 uvtoprojADD = float3(-tan(radians(FOV) * 0.5).xx, 1.0) * float2(1.0, BUFFER_WIDTH * BUFFER_RCP_HEIGHT).yxx;
    static const float3 uvtoprojMUL = float3(-2.0 * uvtoprojADD.xy, 0.0);
    static const float4 projtouv    = float4(rcp(uvtoprojMUL.xy), -rcp(uvtoprojMUL.xy) * uvtoprojADD.xy); 
    return (pos.xy / pos.z) * projtouv.xy + projtouv.zw;          
}

float3 uv_to_proj(float2 uv, float z)
{
    //optimized math to simplify matrix mul
    static const float3 uvtoprojADD = float3(-tan(radians(FOV) * 0.5).xx, 1.0) * float2(1.0, BUFFER_WIDTH * BUFFER_RCP_HEIGHT).yxx;
    static const float3 uvtoprojMUL = float3(-2.0 * uvtoprojADD.xy, 0.0);
    static const float4 projtouv    = float4(rcp(uvtoprojMUL.xy), -rcp(uvtoprojMUL.xy) * uvtoprojADD.xy); 
    return (uv.xyx * uvtoprojMUL + uvtoprojADD) * z;
}

float3 unproject(float3 screenPos)
{
//   float4 viewPos;// = inverseProjectionMatrix * vec4((screenPos.xy * 2.0 - 1.0), screenPos.z, 1.0);
// //   viewPos /= viewPos.w;
  return uv_to_proj(screenPos.xy, screenPos.z);
}

// float3 project(float3 viewPos)
// {
// //   vec4 normalizedDevicePos = projectionMatrix * vec4(viewPos, 1.0);
// //   normalizedDevicePos.xyz /= normalizedDevicePos.w;

//   // float3 screenPos;//  = float3(normalizedDevicePos.xy * 0.5 + float2(0.5), normalizedDevicePos.z);
//   return proj_to_uv(viewPos);
// }

// float saturate(float val)
// {
//   return clamp(val, 0.0f, 1.0f);
// }

float rand(float2 co){
  return frac(sin(dot(co.xy, float2(12.9898,78.233))) * 43758.5453);
}

float ComputeHorizonContribution(float3 eyeDir, float3 eyeTangent, float3 viewNorm, float minAngle, float maxAngle)
{
  return
    +0.25 * dot(eyeDir, viewNorm) * (- cos(2.0 * maxAngle) + cos(2.0 * minAngle))
    +0.25 * dot(eyeTangent, viewNorm) * (2.0 * maxAngle - 2.0 * minAngle - sin(2.0 * maxAngle) + sin(2.0 * minAngle));
}

float2 GetAngularDistribution(float3 centerViewPoint, float3 eyeDir, float3 eyeTangent, float3 rayDir, float2 depthDistribution)
{
  float3 viewPoint = rayDir * depthDistribution.x;

  float3 diff = viewPoint - centerViewPoint;
  
  float depthProj = dot(eyeDir, diff);
  float tangentProj = dot(eyeTangent, diff);
  
  float invTangentProj = 1.0f / tangentProj;
  
  float horizonRatio = depthProj * invTangentProj;
  float horizonAngle = atan2(1.0f, horizonRatio);

  float horizonAngleDerivative;
  {
    float eps = 1e-1f;
    float3 offsetViewPoint = rayDir * (depthDistribution.x + eps);
    float3 offsetDiff = offsetViewPoint - centerViewPoint;
    
    float offsetDepthProj = dot(eyeDir, offsetDiff);
    float offsetTangentProj = dot(eyeTangent, offsetDiff);
    
    float invOffsetTangentProj = 1.0f / offsetTangentProj;
    
    float offsetHorizonRatio = offsetDepthProj * invOffsetTangentProj;
    float offsetHorizonAngle = atan2(1.0f, offsetHorizonRatio);
    horizonAngleDerivative = (offsetHorizonAngle - horizonAngle) / eps;
  }
  return float2(horizonAngle, depthDistribution.y * horizonAngleDerivative * horizonAngleDerivative);
}

// Low discrepancy on [0, 1] ^2
float2 hammersley_norm(int i, int N)
{
  // principle: reverse bit sequence of i
  uint b =  ( uint(i) << 16u) | (uint(i) >> 16u );
  b = (b & 0x55555555u) << 1u | (b & 0xAAAAAAAAu) >> 1u;
  b = (b & 0x33333333u) << 2u | (b & 0xCCCCCCCCu) >> 2u;
  b = (b & 0x0F0F0F0Fu) << 4u | (b & 0xF0F0F0F0u) >> 4u;
  b = (b & 0x00FF00FFu) << 8u | (b & 0xFF00FF00u) >> 8u;

  return float2( i, b ) / float2( N, 0xffffffffu );
}

bool BoxRayCast(float2 rayStart, float2 rayDir, float2 boxMin, float2 boxMax, out float paramMin, out float paramMax)
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

float4 ps_main PPARGS {
    float2 framebuffer_coords = float2(round(tex_coord.x * BUFFER_WIDTH), round(tex_coord.y * BUFFER_HEIGHT));
    float2 screen_coords = tex_coord;
    float3 world_space_normals = Deferred::get_normal(screen_coords);
    float screen_coord_depth = linearize(tex2D(ReShade::DepthBuffer, tex_coord).r);// Deferred::get_depth(screen_coords);
    float4 screen_coord_light = tex2D(blurred_light_sampler, screen_coords);

    float3 cam_world_pos = float3(0, 0, 0);
    float3 center_world_pos = unproject(float3(screen_coords, screen_coord_depth));
    float3 center_view_pos = float3(screen_coords, screen_coord_depth);    
    
    const int interleaved_pattern_size = 4;
    int offsets2[16] = {
        4,  8,  2,  9,
        15, 0,  12, 5,
        1,  3,  10, 11,
        6,  13, 7,  14
    };
    int offsets[16] = {
        0,  4,  8,  12,
        5,  9,  13, 2,
        8,  11, 15, 3,
        14, 6,  10, 7
    };
    // float3 ambient_light = float3(0.01, 0.01, 0.01);
    int2 pattern_index = int2(framebuffer_coords) % interleaved_pattern_size;

    int index = pattern_index.x + pattern_index.y * 4;
    float2 distribution = hammersley_norm(index, 16);
    float ang_offset = distribution.x;
    float lin_offset = distribution.y;

    const int dirs_count = 4;
    const float near_step_size = BUFFER_WIDTH / 1000.f;

    const float pi = 3.1415;
    float pixel_ang_offset = 2.0 * pi / dirs_count * ang_offset;
    float offset_eps = 0.01;

    float3 sum_light = float3(0, 0, 0);
    for(int dir_index = 0; dir_index < dirs_count; dir_index++)
    {
        float dir_pixel_offset = lin_offset;
        float screen_ang = pixel_ang_offset + 2.0 * pi / float(dirs_count) * float(dir_index);
        float2 screen_pixel_dir = float2(cos(screen_ang), sin(screen_ang));

        float eps = 10e-1;
        float3 offset_world_pos = unproject(float3((framebuffer_coords + screen_pixel_dir * eps) / float2(BUFFER_WIDTH, BUFFER_HEIGHT), screen_coord_depth.r));
        float3 eye_world_dir = normalize(cam_world_pos - center_world_pos);
        float3 eye_world_tangent = normalize(normalize(offset_world_pos - cam_world_pos) - normalize(center_world_pos - cam_world_pos));

        float max_horizon_angle = -1e5;

        {
            float3 dir_normal_point = cross(-cross(eye_world_tangent, eye_world_dir), world_space_normals);
            float2 projected_dir_normal = float2(dot(dir_normal_point, eye_world_dir), dot(dir_normal_point, eye_world_tangent));

            max_horizon_angle = atan2(projected_dir_normal.y, projected_dir_normal.x);
        }

        float tmin, tmax;
        BoxRayCast(framebuffer_coords, screen_pixel_dir, float2(0, 0), float2(BUFFER_WIDTH, BUFFER_HEIGHT), tmin, tmax);
        float total_pixel_path = abs(tmax);

        float3 dir_light = float3(0, 0, 0);
        {
            dir_light = ambient_light * ComputeHorizonContribution(float3(0, 0, 1), eye_world_tangent, world_space_normals, 0.0, max_horizon_angle); // TODO: ComputeHorizonContribution(eyeWorldDir, eyeWorldTangent, centerWorldNorm, 0.0, maxHorizonAngle);
        }

        int iterations_count = int(log(total_pixel_path / near_step_size) / log(2.0 * pi / dirs_count + 1)) + 1;

        for(int offset = 0; offset < iterations_count; offset++)
        {
            float pixel_offset = 0;
            pixel_offset = near_step_size * pow(2.0 * pi / dirs_count + 1, offset + dir_pixel_offset) + 1 - near_step_size;
            float2 sample_pixel_coord = framebuffer_coords + screen_pixel_dir * pixel_offset;
            float2 sample_screen_coord = sample_pixel_coord / float2(BUFFER_WIDTH, BUFFER_HEIGHT);
            float side_mult = 1.0;
            {
                float width = 0.1;
                float inv_width = 1.0 / width;
                side_mult *= saturate((1.0 - sample_screen_coord.x) * inv_width);
                side_mult *= saturate(sample_screen_coord.x * inv_width);
                side_mult *= saturate((1.0 - sample_screen_coord.y) * inv_width);
                side_mult *= saturate(sample_screen_coord.y * inv_width);
            }

            float blur_lod_offset = -2;
            float depth_lod_mult = 0.5;
            float color_lod_mult = 0.5;
            float depth_lod = log(max(0, 2.0 * pi / dirs_count * (pixel_offset - 1.0) * depth_lod_mult)) / log(2.0) + blur_lod_offset;
            float color_lod = log(max(0, 2.0 * pi / dirs_count * (pixel_offset - 1.0) * color_lod_mult)) / log(2.0) + blur_lod_offset;

            float depth_sample = linearize(tex2Dlod(ReShade::DepthBuffer, float4(sample_screen_coord, 0, depth_lod)).r);
            float3 sample_world_pos = cam_world_pos + normalize(unproject(float3(sample_screen_coord, 1.0)) - cam_world_pos) * depth_sample;

            float3 world_delta = sample_world_pos - center_world_pos;
            float2 horizon_point = float2(dot(eye_world_dir, world_delta), dot(eye_world_tangent, world_delta));

            float sample_horizon_angle = atan2(horizon_point.y, horizon_point.x);

            if(sample_horizon_angle < max_horizon_angle)
            {
                float4 light_sample = tex2Dlod(blurred_light_sampler, float4(sample_screen_coord, 0, color_lod));

                float horizon_contribution = ComputeHorizonContribution(float3(0, 0, 1), eye_world_tangent, world_space_normals, sample_horizon_angle, max_horizon_angle) * side_mult;

                dir_light += light_sample.rgb * horizon_contribution * pow(2., lintensity);
                dir_light -= ambient_light * horizon_contribution;
                max_horizon_angle = sample_horizon_angle;
            }
        }

        sum_light += float3(2.0, 2.0, 2.0) * dir_light / float(dirs_count);
    }

    return float4(sum_light, 1.0);
    // return float4(dirs_count, dirs_count / 10., 0, 1);
}

float4 ps_combine PPARGS {
    return tex2D(ReShade::BackBuffer, tex_coord) + tex2D(ssvgi_sampler, tex_coord);
}

technique KoreSSVGI <
    ui_tooltip =    "Port of Raikiri's SSVGI to ReShade.\n"
                    "https://github.com/Raikiri/LegitEngine";
> {
    pass main {
        PixelShader = ps_main;
        VertexShader = PostProcessVS;
        RenderTarget = ssvgi_tex;
    }
    pass combine {
        PixelShader = ps_combine;
        VertexShader = PostProcessVS;
    }
}