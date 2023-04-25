#include "ReShade.fxh"

#ifndef LIGHT_FIX_FACTOR
    #define LIGHT_FIX_FACTOR 0.25
#endif

#ifndef LIGHT_SOURCE_SEARCH_STEPS_X
    #define LIGHT_SOURCE_SEARCH_STEPS_X 48
#endif

#ifndef LIGHT_SOURCE_SEARCH_STEPS_Y
    #define LIGHT_SOURCE_SEARCH_STEPS_Y 27
#endif

#ifndef MULTISAMPLE_ENABLE

#else
    #ifndef MULTISAMPLE_QUALITY
        #define MULTISAMPLE_QUALITY 0
    #endif
#endif

#ifndef GPU_SOURCE_CALC_STEPS
    #define GPU_SOURCE_CALC_STEPS 20
#endif

#ifndef SHADOW_MIPMAP_LEVEL
    #define SHADOW_MIPMAP_LEVEL 4
#endif

#ifndef SEARCH_DELAY
    #define SEARCH_DELAY 0.16
#endif

#define LUMA_COEFFICIENT float3(0.212656, 0.715158, 0.072186)

uniform int shadow_quality
<
    ui_label = "Quality";
    ui_tooltip = "The deafult is more than enough, but you can add more.";
    ui_min  = 8;
    ui_max = 128;
    ui_type = "slider";
> = 32;

uniform float depth_offset
<
    ui_label = "Offset";
    ui_type = "drag";
    ui_tooltip = "To prevent shadowing artifacts.\nTry to keep to a minimum.";
    ui_min = -1.;
    ui_max = 1.;
    ui_step = 0.001;
> = 0.01;

uniform float assumed_thickness
<
    ui_label = "Object Thickness";
    ui_type = "drag";
    ui_tooltip = "This thickness will be used to cut off shadows from becoming too large.\nJust drag this till it looks good.";
    ui_min = 0.;
    ui_max = 100.;
    ui_step = 0.5;
> = 40.;

#ifdef MULTISAMPLE_ENABLE

uniform float multisample_radius
<
    ui_label = "Multisample Radius";
    ui_type = "drag";
    ui_tooltip = "Samples in a radius this large for softer shadows.";
    ui_min = 0.;
    ui_max = 1.;
    ui_step = 0.001;
> = 0.1;

#endif

uniform float mot_delay
<
    ui_label = "Light Motion Speed";
    ui_type = "slider";
    ui_tooltip = "Prevents flickering, but causes ghosting.";
    ui_min = 0.;
    ui_max = 1.;
> = 0.05;

uniform float intensity
<
    ui_label = "Shadow Intensity";
    ui_type = "slider";
    ui_tooltip = "Shadow darkness.";
    ui_min = 0.;
    ui_max = 5.;
> = 2.5;

uniform float minimum_brightness
<
    ui_label = "Ambient Brightness";
    ui_type = "slider";
    ui_tooltip = "Currently useless.";
    ui_min = 0.;
    ui_max = 1.;
> = 0.15;

/*uniform float max_change
<
    ui_label = "Max Depth Change";
    ui_type = "drag";
    ui_min = 0.;
    ui_max = 100.;
    ui_step = 0.5;
> = 40.;*/

uniform float randomness
<
    ui_label = "Shadow Randomness";
    ui_type = "slider";
    ui_tooltip = "Default should be good.\nThis is used to allow for multiple lights, but causes flickering.";
    ui_min = 0.;
    ui_max = 1.;
> = 0.3;

uniform float search_blur_radius
<
    ui_label = "Search Radius";
    ui_type = "slider";
    ui_tooltip = "Prevents flickering.";
    ui_min = 0.;
    ui_max = 8.;
> = 2.;

/*uniform float offset_down
<
    ui_label = "Offset Light Position Up";
    ui_tooltip = "Torches, for instance, might not have a depth were the flame is. This somewhat remedies that by using a depth from little lower, hopefully the handle or whatever.";
    ui_type = "drag";
    ui_min = 0.;
    ui_max = 1.5;
> = 0.2;*/
#define offset_down 0

uniform float shadow_ramp
<
    ui_label = "Shadow Intensity Ramping";
    ui_type = "slider";
    ui_tooltip = "Shadow thickness.";
    ui_min = 0.;
    ui_max = 3.;
> = 1.7;

uniform float shadow_luma_mod
<
    ui_label = "Shadow Luma Factor";
    ui_type = "slider";
    ui_tooltip = "Default is good.";
    ui_min = -1.;
    ui_max = 1.;
> = 0.2;

uniform float luma_correction_factor
<
    ui_label = "Scene Luma Correction";
    ui_type = "slider";
    ui_tooltip = "Used to increase the brightness after shadow is cast.";
    ui_min = 0.;
    ui_max = 1.;
> = .5;

uniform float luma_adaption
<
    ui_label = "Scene Luma Adaption";
    ui_type = "slider";
    ui_tooltip = "Luma correction delay.";
    ui_min = 0.;
    ui_max = 1.;
> = 0.1;

uniform bool flip_depth
<
    ui_label = "Flip depth";
    ui_tooltip = "If shadows aren't showing, this is usually it.";
> = false;

uniform float depth_cut_off_min
<
    ui_label = "Depth Cutoff Minimum";
    ui_tooltip = "Keep at deafult, or set to one for inifitely long shadows.";
    ui_type = "slider";
    ui_min = 0.;
    ui_max = 1.;
> = .999;

uniform float depth_cut_off_max
<
    ui_label = "Depth Cutoff Maximum";
    ui_tooltip = "Keep at default.";
    ui_type = "slider";
    ui_min = 0.;
    ui_max = 1.;
> = 1.;

uniform float difference_strength
<
    ui_label = "Deghosting Strength";
    ui_tooltip = "Expirimental deghosting.";
    ui_type = "slider";
    ui_min = 0;
    ui_max = 8.;
> = 0.5;

uniform float normal_depth
<
    ui_label = "Normalized Depth";
    ui_tooltip = "Currently useless.";
    ui_type = "drag";
> = 30.;

uniform float random_value < source = "random"; min = -1.; max = 1.; >;
uniform int framecount < source = "framecount"; >;

texture back_buffer : COLOR;

sampler back_sampler {
    Texture = back_buffer;
    SRGBTexture = true;
};

texture normal_tex {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
};

sampler normal_sampler {
    Texture = normal_tex;
};

texture old_back_buffer {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
};

sampler old_back_sampler {
    Texture = old_back_buffer;
};

texture diff_buffer {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = R8;
};

sampler diff_sampler {
    Texture = diff_buffer;
};

texture search_tex {
    Width = LIGHT_SOURCE_SEARCH_STEPS_X;
    Height = LIGHT_SOURCE_SEARCH_STEPS_Y;
    Format = R8;
};

sampler search_sampler {
    Texture = search_tex;
};

texture old_search_tex {
    Width = LIGHT_SOURCE_SEARCH_STEPS_X;
    Height = LIGHT_SOURCE_SEARCH_STEPS_Y;
    Format = R8;
};

sampler old_search_sampler {
    Texture = search_tex;
};

texture luma_tex {
    Width = LIGHT_SOURCE_SEARCH_STEPS_X;
    Height = LIGHT_SOURCE_SEARCH_STEPS_Y;
    Format = R8;
};

sampler luma_sampler {
    Texture = luma_tex;
};

texture luma_tex_2 {
    Width = LIGHT_SOURCE_SEARCH_STEPS_X / 4;
    Height = LIGHT_SOURCE_SEARCH_STEPS_Y / 4;
    Format = R8;
};

sampler luma_sampler_2 {
    Texture = luma_tex_2;
};

texture luma_tex_3 {
    Format = R8;
};

sampler luma_sampler_3 {
    Texture = luma_tex_3;
};

texture comp_luma_tex {
    Format = R8;
};

sampler comp_luma_sampler {
    Texture = comp_luma_tex;
};

texture luma_diff_tex {
    Format = R8;
};

sampler luma_diff_sampler {
    Texture = luma_diff_tex;
};

texture luma_old_tex {
    Format = R8;
};

sampler luma_old_sampler {
    Texture = luma_old_tex;
};

texture light_centre {
    Width = GPU_SOURCE_CALC_STEPS;
    Format = RGBA8;
};

sampler light_centre_sampler {
    Texture = light_centre;
};

/*
texture old_light_centre {

    Format = RGBA16F;
};

sampler old_light_centre_sampler {
    Texture = old_light_centre;
};*/

texture shadow_map {
    Width = BUFFER_WIDTH / SHADOW_MIPMAP_LEVEL;
    Height = BUFFER_HEIGHT / SHADOW_MIPMAP_LEVEL;
    Format = R8;
};

sampler shadow_sampler {
    Texture = shadow_map;
};

texture old_shadow_map {
    Width = BUFFER_WIDTH / SHADOW_MIPMAP_LEVEL;
    Height = BUFFER_HEIGHT / SHADOW_MIPMAP_LEVEL;
    Format = R8;
};

sampler old_shadow_sampler {
    Texture = old_shadow_map;
};

texture final_tex {
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
};

sampler final_sampler {
    Texture = final_tex;
};

float calc_diff(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    return length(tex2D(ReShade::BackBuffer, tex_coord) - tex2D(old_back_sampler, tex_coord)) * difference_strength;
}

float4 gen_normals(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float2 offset = 1. / float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float dn = tex2D(ReShade::DepthBuffer, tex_coord + float2(0, offset.y)).r;
    //float ds = tex2D(ReShade::DepthBuffer, tex_coord + float2(0, piy)).r;
    float de = tex2D(ReShade::DepthBuffer, tex_coord + float2(offset.x, 0)).r;
    //float dw = tex2D(ReShade::DepthBuffer, tex_coord + float2(0, piy)).r;
    float dc = tex2D(ReShade::DepthBuffer, tex_coord).r;
    float3 normal;
    normal.xy = (dc - float2(de, dn));
    normal.xy /= offset;
    // normal.x = dc - de;
    // normal.y = dc - dn;
    normal.z = 1. / normal_depth;
    normal = normalize(normal);
    normal = normal * 0.5 + 0.5;
    return float4(normal, 1.);
}

float luma_sample(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float luma = 0.;
    for(int x = -1; x <= 1; x++) {
        for(int y = -1; y <= 1; y++) {
            float2 mod_coord = float2(x, y) * (1./float2(LIGHT_SOURCE_SEARCH_STEPS_X, LIGHT_SOURCE_SEARCH_STEPS_Y));
            float4 col = tex2Dlod(ReShade::BackBuffer, float4(tex_coord + mod_coord, 0, 0));
            luma += dot(col.xyz, LUMA_COEFFICIENT);
        }
    }
    return luma / 9;
};

float comp_luma_sample(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float luma = 0.;
    for(int x = -1; x <= 1; x++) {
        for(int y = -1; y <= 1; y++) {
            float2 mod_coord = float2(x, y) * (1./float2(LIGHT_SOURCE_SEARCH_STEPS_X, LIGHT_SOURCE_SEARCH_STEPS_Y));
            float4 col = tex2Dlod(final_sampler, float4(tex_coord + mod_coord, 0, 0));
            luma += dot(col.xyz, LUMA_COEFFICIENT);
        }
    }
    return luma / 9;
};

float luma_diff(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float old_luma = tex2Dfetch(luma_sampler_3, 0).r;
    float new_luma = tex2Dfetch(comp_luma_sampler, 0).r;
    float prev_luma_diff = tex2Dfetch(luma_diff_sampler, 0).r;
    float luma_diff = old_luma / new_luma;
    return lerp(prev_luma_diff, luma_diff, luma_adaption);
};

float luma_sample_2(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    return tex2Dlod(luma_sampler, float4(tex_coord, 0, 0)).r;
};

float luma_sample_3(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float2 pixel_size = float2(8 * LIGHT_SOURCE_SEARCH_STEPS_X / float(BUFFER_RCP_WIDTH), 8 * LIGHT_SOURCE_SEARCH_STEPS_Y / float(BUFFER_HEIGHT));
    float2 start_pixel = pixel_size / 2.;
    float luma = 0.;
    for(uint x = 0; x < LIGHT_SOURCE_SEARCH_STEPS_X / 16; x++) {
        for(uint y = 0; y < LIGHT_SOURCE_SEARCH_STEPS_Y / 16; y++) {
            luma += tex2D(luma_sampler_2, float2(x, y) * pixel_size + start_pixel).x;
        }
    }
    luma /= (LIGHT_SOURCE_SEARCH_STEPS_X / 16) * (LIGHT_SOURCE_SEARCH_STEPS_Y / 16);
    float old_luma = tex2Dfetch(luma_sampler_3, 0).r;
    return lerp(old_luma, luma, luma_adaption);
};

float comp_luma_sample_3(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float2 pixel_size = float2(8 * LIGHT_SOURCE_SEARCH_STEPS_X / float(BUFFER_RCP_WIDTH), 8 * LIGHT_SOURCE_SEARCH_STEPS_Y / float(BUFFER_HEIGHT));
    float2 start_pixel = pixel_size / 2.;
    float luma = 0.;
    for(uint x = 0; x < LIGHT_SOURCE_SEARCH_STEPS_X / 16; x++) {
        for(uint y = 0; y < LIGHT_SOURCE_SEARCH_STEPS_Y / 16; y++) {
            luma += tex2D(luma_sampler_2, float2(x, y) * pixel_size + start_pixel).x;
        }
    }
    luma /= (LIGHT_SOURCE_SEARCH_STEPS_X / 16) * (LIGHT_SOURCE_SEARCH_STEPS_Y / 16);
    float old_luma = tex2Dfetch(comp_luma_sampler, 0).r;
    return lerp(old_luma, luma, luma_adaption);
};

void luma_blend(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD, out float old_luma : SV_TARGET0, out float comp_luma : SV_TARGET1) {
    float a_old_luma = tex2Dfetch(luma_old_sampler, 0).r;
    float a_comp_luma = tex2Dfetch(comp_luma_sampler, 0).r;
    old_luma = a_comp_luma;
    comp_luma = lerp(a_old_luma, a_comp_luma, luma_adaption);
}

float down_sample(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float2 pixel_size = float2(LIGHT_SOURCE_SEARCH_STEPS_X / float(BUFFER_WIDTH), LIGHT_SOURCE_SEARCH_STEPS_Y / float(BUFFER_HEIGHT));
    float brightness = 0.;

    const float PI = 6.2831;
    const float NUMBER = 32.0;
    const float QUALITY = 12.0;
    for(float n = 0.0; n < PI; n += PI/NUMBER) {
		for(float i = 1.0 / QUALITY; i <= 1.0; i += 1.0 / QUALITY) {
			float n_brightness = length(
                tex2Dlod(
                    luma_sampler,
                    float4(
                        float2(tex_coord + float2(cos(n),sin(n)) * pixel_size * search_blur_radius * i),
                        0.,
                        3.
                    )
                ).rgb
            );
            if(n_brightness > brightness) {
                brightness = n_brightness;
            }
        }
    }
    // brightness += length(tex2Dlod(luma_sampler, float4(tex_coord, 0., 3)).rgb);
    // brightness /= QUALITY * NUMBER - 15.;
    //brightness -= tex2Dfetch(luma_sampler_3, 0).r;
    brightness *= brightness;// * (1. / tex2Dfetch(luma_sampler_3, 0).r);
    //return brightness;
    return lerp(tex2D(old_search_sampler, tex_coord).r, brightness, SEARCH_DELAY);
    //return saturate(brightness * (brightness + 0.1) * (1. / tex2Dfetch(luma_sampler_3, 0).r));
};

float old_down_sample(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    return tex2D(search_sampler, tex_coord).r;
};

/*#define M1 1597334677U     //1719413*929
#define M2 3812015801U     //140473*2467*11
float hash(float2 q)
{
    q *= float2(M1, M2); 
    
    uint n = ((uint)q.x ^ (uint)q.y) * M1;
    
    return float(n) / 0xffffffff;
}*/

#define hash(p)  frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453)

float4 find_centre(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float2 centre = float2(0.5, 0.5);
    float luma = pow(tex2Dfetch(luma_sampler_3, 0).r, 2);
    float brightest = luma;

    bool found = false;
    for(uint x = 0; x < LIGHT_SOURCE_SEARCH_STEPS_X; x++) {
        for(uint y = 0; y < LIGHT_SOURCE_SEARCH_STEPS_Y; y++) {
            float2 sample_pos = float2(
                float(x) / LIGHT_SOURCE_SEARCH_STEPS_X,
                float(y) / LIGHT_SOURCE_SEARCH_STEPS_Y
            );

            float sample_intensity = length(tex2D(search_sampler, sample_pos).rgb);

            float hash_x = ((tex_coord.x + x) * GPU_SOURCE_CALC_STEPS + random_value);
            float hash_y = (y * GPU_SOURCE_CALC_STEPS + random_value);
            float hashed = hash(hash_x * hash_y) - 0.5;

            if((sample_intensity * (1 + hashed * randomness) * (1. - length(tex_coord) * LIGHT_FIX_FACTOR)) > brightest) {
                centre = sample_pos;
                brightest = sample_intensity;
                found = true;
            }
        }
    }

    return float4(centre, found ? brightest : 0., 1.);
};

float calculate_shadow(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float fragment_depth = flip_depth ? (1. - tex2D(ReShade::DepthBuffer, tex_coord).r) : tex2D(ReShade::DepthBuffer, tex_coord).r;
    float3 fragment_normal = tex2D(normal_sampler, tex_coord).xyz * 2. - 1.;

    float shadowed = 0.;
    float aspect_ratio = float(BUFFER_WIDTH) / BUFFER_HEIGHT;

#ifdef MULTISAMPLE_ENABLE

    /*const int MS_QUALITY_FACTOR = MULTISAMPLE_QUALITY * 2 * MULTISAMPLE_QUALITY * 2;

    for(uint s = 0; s < GPU_SOURCE_CALC_STEPS; s++) {
        for(uint i = 1; i < shadow_quality; i++) {
            for(int x = -MULTISAMPLE_QUALITY; x <= MULTISAMPLE_QUALITY; x++) {
                for(int y = -MULTISAMPLE_QUALITY; y <= MULTISAMPLE_QUALITY; y++) {
                    float2 coord_mod = float2(
                        (x / aspect_ratio)  / ((MS_QUALITY_FACTOR + 1) * GPU_SOURCE_CALC_STEPS),
                        y                   / ((MS_QUALITY_FACTOR + 1) * GPU_SOURCE_CALC_STEPS)
                    ) * multisample_radius * 0.1;

                    float2 light_pos = tex2Dfetch(light_centre_sampler, uint2(s, 0)).xy + coord_mod;

                    float traveled_percentage = float(i) / shadow_quality;
                    float2 traveled_coord = lerp(light_pos, tex_coord, traveled_percentage);
                    float traveled_depth = flip_depth ? (1. - tex2D(ReShade::DepthBuffer, traveled_coord).r) : tex2D(ReShade::DepthBuffer, traveled_coord).r;

                    float dotp = dot(light_normal, fragment_normal);

                    float light_depth = flip_depth
                        ? (1. - tex2D(ReShade::DepthBuffer, light_pos - float2(0, offset_down)).r)
                        : tex2D(ReShade::DepthBuffer, light_pos - float2(0, offset_down)).r;
                    float lerped_depth = lerp(light_depth, fragment_depth, traveled_percentage);

                    float depth_difference = lerped_depth - traveled_depth;
                    if(
                        (depth_difference > depth_offset / 1000) &&
                        ((depth_difference - assumed_thickness / 10000) < depth_offset / 1000)
                    ) {
                        shadowed += 1. / (shadow_quality * (MS_QUALITY_FACTOR + 1) * GPU_SOURCE_CALC_STEPS);
                    }
                }
            }
        }
    }*/

#else

    for(uint s = 0; s < GPU_SOURCE_CALC_STEPS; s++) {
        float2 light_pos = tex2Dfetch(light_centre_sampler, uint2(s, 0)).xy;
        float light_depth = flip_depth
            ? (1. - tex2D(ReShade::DepthBuffer, light_pos - float2(0, offset_down)).r)
            : tex2D(ReShade::DepthBuffer, light_pos - float2(0, offset_down)).r;

        float3 light_dir = float3(light_pos, light_depth) - float3(tex_coord, fragment_depth);


        float dotp = saturate(dot(light_dir, fragment_normal));

        for(uint i = 1; i < shadow_quality; i++) {
            float traveled_percentage = float(i) / shadow_quality;
            float2 traveled_coord = lerp(light_pos, tex_coord, traveled_percentage);
            float traveled_depth = flip_depth ? (1. - tex2D(ReShade::DepthBuffer, traveled_coord).r) : tex2D(ReShade::DepthBuffer, traveled_coord).r;
            float lerped_depth = lerp(light_depth, fragment_depth, traveled_percentage);

            float depth_difference = lerped_depth - traveled_depth;
            if(
                (depth_difference > depth_offset / 1000) &&
                ((depth_difference - assumed_thickness / 10000) < depth_offset / 1000)
            ) {
                shadowed += 1. / (shadow_quality * GPU_SOURCE_CALC_STEPS);
                // shadowed += max(dotp, 0.);
            }
        }
    }

#endif

    shadowed = lerp(tex2D(old_shadow_sampler, tex_coord), shadowed, mot_delay + tex2D(diff_sampler, tex_coord)).x;

    return shadowed;
};

float old_shadow(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    return saturate(tex2D(shadow_sampler, tex_coord)).x;
};

float Tonemap_ACES(float x) {
    // Narkowicz 2015, "ACES Filmic Tone Mapping Curve"
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return (x * (a * x + b)) / (x * (c * x + d) + e);
}

float4 apply_shadow(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float luma = sqrt(tex2Dfetch(luma_sampler_3, 0).r);
    float shadow = tex2D(shadow_sampler, tex_coord).r;
    float3 color = tex2D(ReShade::BackBuffer, tex_coord).rgb;
    float mod_intensity = intensity * (tex2D(light_centre_sampler, 0).z);
    float final_shadow = Tonemap_ACES(pow(shadow * mod_intensity, 1. / shadow_ramp) * (1 + luma * shadow_luma_mod));
    //final_shadow = min(final_shadow, 1. - minimum_brightness);
    color *= 1. - final_shadow;// / 2;
    //color -= final_shadow / 2;
    return float4(color, 1);
};

float4 show_image(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    float multiply_by = tex2Dfetch(luma_diff_sampler, 0).r;
    float depth = flip_depth ? (1. - tex2D(ReShade::DepthBuffer, tex_coord).r) : tex2D(ReShade::DepthBuffer, tex_coord).r;
    float mix_t = smoothstep(depth_cut_off_min, depth_cut_off_max, pow(depth, 4));
    return lerp(tex2D(final_sampler, tex_coord), tex2D(ReShade::BackBuffer, tex_coord), mix_t) * min(10, (1. + multiply_by * luma_correction_factor));
};

float4 old_back_buffer_copy(float4 position : SV_POSITION, float2 tex_coord : TEXCOORD) : SV_TARGET {
    return tex2D(ReShade::BackBuffer, tex_coord);
}

technique SSS
<
    ui_tooltip =    "Highly expirimental screen-space shadows, based off\n"
                    "Lucas Melo (luluco250)'s TrackingRays.\n"
                    "\n"
                    "Still a work in progress.\n"
                    "As of now, ghosting is a large problem.\n"
                    "This can be mitigated through increasing the\n"
                    "Quality, Light Motion Speed, Deghosting Strength,\n"
                    "And most importantly the GPU_SOURCE_CALC,\n"
                    "LIGHT_SOURCE_SEARCH_STEPS_X and Y preprocessors.\n"
                    "Quality can be increased further with the\n"
                    "SHADOW_MIPMAP_LEVEL preprocessor."
>
{
    pass Diff {
        VertexShader = PostProcessVS;
        PixelShader = calc_diff;
        RenderTarget = diff_buffer;
    }
    pass Normals {
        VertexShader = PostProcessVS;
        PixelShader = gen_normals;
        RenderTarget = normal_tex;
    }
    pass LumaSample {
        VertexShader = PostProcessVS;
        PixelShader = luma_sample;
        RenderTarget = luma_tex;
    }
    pass LumaSample2 {
        VertexShader = PostProcessVS;
        PixelShader = luma_sample_2;
        RenderTarget = luma_tex_2;
    }
    pass LumaSample3 {
        VertexShader = PostProcessVS;
        PixelShader = luma_sample_3;
        RenderTarget = luma_tex_3;
    }
    pass DownSample {
        VertexShader = PostProcessVS;
        PixelShader = down_sample;
        RenderTarget = search_tex;
    }
    pass SaveDownSample {
        VertexShader = PostProcessVS;
        PixelShader = old_down_sample;
        RenderTarget = old_search_tex;
    }
    pass GetCentre {
        VertexShader = PostProcessVS;
        PixelShader = find_centre;
        RenderTarget = light_centre;
    }
    pass InShadow {
        VertexShader = PostProcessVS;
        PixelShader = calculate_shadow;
        RenderTarget = shadow_map;
    }
    pass OldShadow {
        VertexShader = PostProcessVS;
        PixelShader = old_shadow;
        RenderTarget = old_shadow_map;
    }
    pass ShadowPass {
        VertexShader = PostProcessVS;
        PixelShader = apply_shadow;
        RenderTarget = final_tex;
    }
    pass CompLumaSample {
        VertexShader = PostProcessVS;
        PixelShader = comp_luma_sample;
        RenderTarget = luma_tex;
    }
    pass CompLumaSample2 {
        VertexShader = PostProcessVS;
        PixelShader = luma_sample_2;
        RenderTarget = luma_tex_2;
    }
    pass CompLumaSample3 {
        VertexShader = PostProcessVS;
        PixelShader = comp_luma_sample_3;
        RenderTarget = comp_luma_tex;
    }
    /*pass LumaComp {
        VertexShader = PostProcessVS;
        PixelShader = luma_blend;
        RenderTarget0 = luma_old_tex;
        RenderTarget1 = comp_luma_tex;
    }*/
    pass LumaDiff {
        VertexShader = PostProcessVS;
        PixelShader = luma_diff;
        RenderTarget = luma_diff_tex;
    }
    pass OldBackBuffer {
        VertexShader = PostProcessVS;
        PixelShader = old_back_buffer_copy;
        RenderTarget = old_back_buffer;
    }
    pass Final {
        VertexShader = PostProcessVS;
        PixelShader = show_image;
    }
}
