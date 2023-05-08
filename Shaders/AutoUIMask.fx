#include "ReShade.fxh"
#include "ReShadeUI.fxh"

uniform int help_text <
    ui_type = "radio";
    ui_category = "Help";
    ui_tooltip = "";
    ui_text =    "Automatic UI Mask generation for ReShade.\n"
                    "Instructions:\n"
                    "1. Reset the mask texture.\n"
                    "2. Set 'Generate Mask' to on.\n"
                    "3. Move the game camera to try and get as much contrast in non-ui pixels.\n"
                    "4. Use the 'Mask Helper' option to see if areas are missing.\n"
                    "5. Disable the 'Generate Mask' option.\n"
                    "6. Enable the 'Show Mask' option.\n"
                    "7. Screenshot and use as UIMask image.";
    ui_items = "";
> = 0;

uniform bool reset_mask <
    ui_type = "radio";
    ui_label = "Reset Mask";
    ui_category = "Mask";
    ui_tooltip = "Resets the mask texture";
> = false;

uniform bool detect_mask <
    ui_type = "radio";
    ui_label = "Generate Mask";
    ui_category = "Mask";
    ui_tooltip = "While this option is on, move the camera";
> = false;

uniform bool mask_helper <
    ui_type = "radio";
    ui_label = "Mask Helper";
    ui_category = "Mask";
    ui_tooltip = "Adds an overlay on screen that shows the non-masked areas";
> = false;

uniform bool show_mask <
    ui_type = "radio";
    ui_label = "Show Mask";
    ui_category = "Mask";
    ui_tooltip = "Shows the mask texture";
> = false;

uniform float detect_mask_sensitivity <
    ui_type = "slider";
    ui_category = "Mask";
    ui_label = "Masking Sensitivity";
    ui_tooltip = "";
    ui_min = -1.0; ui_max = 1.0;
    ui_step = 0.05;
> = 0.25;

uniform int algorithm_type <
    ui_type = "combo";
    ui_category = "Mask";
    ui_label = "Algorithm";
    ui_tooltip = "Which algorithm to detect with";
    ui_items = "Normalized Dot Product\0Normalized Difference\0Absolute Difference\0";
> = 2;

texture2D start_back_tex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; MipLevels = 1; Format = RGBA32F; };
sampler2D start_back_sampler { Texture = start_back_tex; MipLODBias = 0; };

texture2D old_start_back_tex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; MipLevels = 1; Format = RGBA32F; };
sampler2D old_start_back_sampler { Texture = old_start_back_tex; MipLODBias = 0; };

texture2D d_tex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; MipLevels = 1; Format = RGBA32F; };
sampler2D d_samp { Texture = d_tex; MipLODBias = 0; };

texture2D generated_mask_texture { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; MipLevels = 1; Format = R32F; };
sampler2D generated_mask_sampler { Texture = generated_mask_texture; MipLODBias = 0; };

texture2D old_generated_mask_texture { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; MipLevels = 1; Format = R32F; };
sampler2D old_generated_mask_sampler { Texture = old_generated_mask_texture; MipLODBias = 0; };

void generate_mask(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float mask : SV_Target0, out float4 start_col : SV_Target1, out float4 col_dot : SV_Target2) {
    if(reset_mask) {
        mask = 0.;
        start_col = tex2D(ReShade::BackBuffer, texcoord);
        col_dot = float4(0., 0., 0., 1.);
        return;
    } else if(detect_mask) {
        float3 s_col = tex2D(old_start_back_sampler, texcoord).rgb;
        float3 c_col = tex2D(ReShade::BackBuffer, texcoord).rgb;
        float diff;
        switch(algorithm_type) {
            case 0:
            diff = dot(normalize(s_col).rgb, normalize(c_col).rgb);
            break;
            case 1:
            diff = length(normalize(s_col).rgb - normalize(c_col).rgb);
            break;
            case 2:
            diff = length(s_col.rgb - c_col.rgb);
            break;
        }
        col_dot = float4(diff, diff, diff, 1.);
        if(diff > detect_mask_sensitivity) {
            mask = 1.;
        } else {
            mask = tex2D(old_generated_mask_sampler, texcoord).r;
        }
        start_col = tex2D(old_start_back_sampler, texcoord);
        return;
    } else {
        mask = tex2D(old_generated_mask_sampler, texcoord);
        start_col = tex2D(old_start_back_sampler, texcoord);
        col_dot = float4(0., 0., 0., 1.);
        return;
    }
}

void overlays(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 col : SV_Target0) {
    col = tex2D(ReShade::BackBuffer, texcoord);
    if(show_mask) {
        float t = tex2D(generated_mask_sampler, texcoord).r;
        col = float4(t, t, t, 1.);
        return;
    }
    if(mask_helper) {
        if(tex2D(generated_mask_sampler, texcoord).r == 0.) {
            col = float4(1., 1., 1., 1.);
        }
        return;
    }
    return;
}

float4 copy_back(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
    return tex2D(start_back_sampler, texcoord);
}

float4 copy_mask(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
    return tex2D(generated_mask_sampler, texcoord);
}

technique AutoUIMask {
    pass {
        VertexShader = PostProcessVS;
        PixelShader = generate_mask;
        RenderTarget0 = generated_mask_texture;
        RenderTarget1 = start_back_tex;
        RenderTarget2 = d_tex;
    }
    pass {
        VertexShader = PostProcessVS;
        PixelShader = overlays;
        /* RenderTarget = BackBuffer */
    }
    pass {
        VertexShader = PostProcessVS;
        PixelShader = copy_back;
        RenderTarget = old_start_back_tex;
    }
    pass {
        VertexShader = PostProcessVS;
        PixelShader = copy_mask;
        RenderTarget = old_generated_mask_texture;
    }
}