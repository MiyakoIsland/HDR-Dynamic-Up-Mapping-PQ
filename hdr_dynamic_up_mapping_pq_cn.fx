/*
    HDR Dynamic Up-Mapping (PQ)
    Copyright (C) 2026 Miyako Island

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    See the LICENSE file for the full license text.
*/

#include "ReShade.fxh"

//20261112易用版

// -----------------------------------------------------------------------------
// UI Controls
// -----------------------------------------------------------------------------
uniform int UI_TargetNits <
    ui_type = "slider";
    ui_min = 1; ui_max = 10000; ui_step = 1;
    ui_label = "目标峰值亮度";
    ui_tooltip = "设定为显示设备的最大峰值亮度（硬裁切）\n并且尽可能关闭windows和mpv以及显示设备的映射\n比如将windows和mpv的峰值亮度设置为10000nits，或尽可能大的值（即关闭映射）\n而显示设备尽量选择HGIG或类似的无映射模式\n\n如果对自身的显示设备不甚了解\n可以选择日常使用中最暗的那个模式，并在此处填写HDR校准时测得的峰值亮度（硬裁切）\n日常使用中最暗的模式通常为最贴合PQ曲线的较弱映射的模式\n\n对于PC游戏，建议将游戏内部（或Renodx）的峰值亮度设定为1000nits\n如果显示设备的峰值亮度低于1000nit，则根据实际值设定\n比如显示设备峰值800nits，则游戏内部（或Renodx）的峰值就设定为800nits\n\n如果对某PC游戏的原生HDR映射比较满意\n也可以将游戏内部（或Renodx）的峰值亮度设定为显示设备的峰值亮度\n比如显示设备峰值2000nits，游戏内部（或Renodx）的峰值也设定为2000nits\n此时，该着色器作用于实时高光补偿，而非整体向上映射";
> = 2800;

uniform int UI_Preset <
    ui_type = "combo";
    ui_label = "预设";
    ui_items = "暗室 游戏和通用\0暗室 观影\0亮室 通用\0";
    ui_tooltip = "观影：峰值亮度低于1000nits的电影和电视剧";
> = 0;

// 映射强度上限
static const float Preset_MaxExpansionDelta[3] =
{
    0.20,
    0.20,
    0.20
};

// 映射线弯折
static const float Preset_GainCurveStrength[3] =
{
    40.0,
    40.0,
    50.0
};

// 映射线拐点
static const float Preset_CurvePivot[3] =
{
    0.90,
    0.90,
    0.10
};

// 峰值检测方式
static const bool Preset_UseBaselinePeakDetection[3] =
{
    true,
    false,
    true
};

uniform float UI_MaxExpansionDelta_Offset <
    ui_type = "slider";
    ui_label = "映射强度";
    ui_tooltip = "更小的值更加自然，但也更接近原始画面\n更大的值更加生动，但可能使部分细节失真";
    ui_min = 0.0;
    ui_max = 50.0;
    ui_step = 1.0;
> = 20.0;

uniform float UI_GainCurveStrength_Offset <
    ui_type = "slider";
    ui_label = "对比度增强（暗室）";
    ui_tooltip = "仅对 暗室 生效";
    ui_min = -4.0;
    ui_max = 10.0;
    ui_step = 1.00;
> = 0.0;

uniform float UI_GainCurveStrength_Bright_Offset <
    ui_type = "slider";
    ui_label = "环境光补偿（亮室）";
    ui_tooltip = "仅对 亮室 生效";
    ui_min = 0.0;
    ui_max = 10.0;
    ui_step = 1.00;
> = 0.0;

#define UI_MaxExpansionDelta (Preset_MaxExpansionDelta[UI_Preset] + (UI_MaxExpansionDelta_Offset - 20.0) / 100.0)
#define UI_GainCurveStrength (Preset_GainCurveStrength[UI_Preset] + (UI_Preset <= 1 ? -2.5 * UI_GainCurveStrength_Offset : (UI_Preset == 2 ? 1.0 * UI_GainCurveStrength_Bright_Offset : 0.0)))
#define UI_CurvePivot Preset_CurvePivot[UI_Preset]
#define UI_UseBaselinePeakDetection Preset_UseBaselinePeakDetection[UI_Preset]

uniform float UI_ColorExpansionStrength <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 10.0; ui_step = 0.10;
    ui_label = "高光色彩增强";
    ui_tooltip = "越亮的像素，色彩增强越多\n推荐值：0~4\n完全关闭：0";
> = 0.5;

uniform bool UI_ShowOSD <
    ui_label = "OSD：原始画面参考峰值";
    ui_tooltip = "显示原始画面的参考峰值亮度，该亮度数值经由峰值检测算法逐帧测量，是动态映射的基准\n\n观影预设下为最大亮度像素的峰值\n其它预设经由采样算法，通常小于最大亮度像素的峰值";
> = true;

uniform int UI_RefreshRateMS <
    ui_type = "slider";
    ui_min = 100; ui_max = 2000; ui_step = 50;
    ui_label = "OSD 刷新周期：毫秒";
> = 500;

uniform float UI_OSDBrightnessNits <
    ui_type = "slider";
    ui_min = 10.0; ui_max = 500.0; ui_step = 5.0;
    ui_label = "OSD 文本亮度：nits";
> = 50.0;

uniform float UI_OSDScale <
    ui_type = "slider";
    ui_min = 0.5; ui_max = 10.0; ui_step = 0.1;
    ui_label = "OSD 大小";
> = 2.0;

uniform int UI_OSDPosX <
    ui_type = "slider";
    ui_min = 0; ui_max = 3840; ui_step = 5;
    ui_label = "OSD 在横坐标上的位置";
> = 10;

uniform int UI_OSDPosY <
    ui_type = "slider";
    ui_min = 0; ui_max = 2160; ui_step = 5;
    ui_label = "OSD 在纵坐标上的位置";
> = 10;

uniform bool UI_UseScRGB <
    ui_label = "强制scRGB";
    ui_tooltip = "少数HDR游戏采用全局scRGB色彩空间\n勾选后画面恢复正常，并且启动向上动态映射";
> = false;

#define UI_EnableSmoothing true
#define UI_UseGammaCurve true
#define UI_PQ_CV99 0.001
#define UI_MappingPeakFloorPQ 0.500
#define UI_AdaptationSpeedRise 1.0
#define UI_AdaptationSpeedFall 0.3

uniform float UI_FrameTime < source = "frametime"; >;

// -----------------------------------------------------------------------------
// Textures & Samplers
// -----------------------------------------------------------------------------
// Internal working image: PQ mode copies the backbuffer unchanged;
// forced scRGB mode converts linear scRGB to PQ/BT.2020 before analysis.
texture TexWorkingPQ { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler SamplerWorkingPQ { Texture = TexWorkingPQ; MagFilter = POINT; MinFilter = POINT; };
sampler2D<float4> SamplerWorkingPQCompute { Texture = TexWorkingPQ; };

// Full-screen maximum luminance accumulator (unsigned millinits).
texture TexPeakMax { Width = 1; Height = 1; Format = R32U; };
sampler2D<uint> SamplerPeakMax { Texture = TexPeakMax; };
storage2D<uint> StoragePeakMax { Texture = TexPeakMax; };

texture TexFinalPQ { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler SamplerFinalPQ { Texture = TexFinalPQ; MagFilter = POINT; MinFilter = POINT; };

texture TexCleanLuma { Width = 32; Height = 32; Format = R16F; };
sampler SamplerCleanLuma { Texture = TexCleanLuma; MagFilter = POINT; MinFilter = POINT; };

// R: Instant Target Peak, G: Temporal Smoothed Peak, B: Timer, A: OSD Latched Peak
texture TexPeakDataA { Width = 1; Height = 1; Format = RGBA32F; };
sampler SamplerPeakDataA { Texture = TexPeakDataA; MagFilter = POINT; MinFilter = POINT; };
sampler2D<float4> SamplerPeakDataACompute { Texture = TexPeakDataA; };

texture TexPeakDataB { Width = 1; Height = 1; Format = RGBA32F; };
sampler SamplerPeakDataB { Texture = TexPeakDataB; MagFilter = POINT; MinFilter = POINT; };

texture TexMappedColor { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler SamplerMappedColor { Texture = TexMappedColor; MagFilter = POINT; MinFilter = POINT; };

texture TexSmoothedColor { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler SamplerSmoothedColor { Texture = TexSmoothedColor; MagFilter = POINT; MinFilter = POINT; };

// -----------------------------------------------------------------------------
// Math & Helper Functions
// -----------------------------------------------------------------------------
float PQ2Nits(float pq)
{
    pq = max(pq, 0.0);
    float m1 = 0.1593017578125;
    float m2 = 78.84375;
    float c1 = 0.8359375;
    float c2 = 18.8515625;
    float c3 = 18.6875;

    float pN = pow(pq, 1.0 / m2);
    float num = max(pN - c1, 0.0);
    float den = c2 - c3 * pN;
    float val = pow(num / den, 1.0 / m1);
    return val * 10000.0;
}

float Nits2PQ(float nits)
{
    nits = clamp(nits / 10000.0, 0.0, 1.0);
    float m1 = 0.1593017578125;
    float m2 = 78.84375;
    float c1 = 0.8359375;
    float c2 = 18.8515625;
    float c3 = 18.6875;

    float Ym1 = pow(nits, m1);
    float num = c1 + c2 * Ym1;
    float den = 1.0 + c3 * Ym1;
    return pow(num / den, m2);
}

// Linear BT.709/sRGB <-> linear BT.2020 matrices retained for forced scRGB mode.
float3 Linear709To2020(float3 c)
{
    return float3(
        0.6274040 * c.r + 0.3292820 * c.g + 0.0433136 * c.b,
        0.0690970 * c.r + 0.9195400 * c.g + 0.0113612 * c.b,
        0.0163916 * c.r + 0.0880132 * c.g + 0.8955950 * c.b
    );
}

float3 Linear2020To709(float3 c)
{
    return float3(
         1.6604910 * c.r - 0.5876411 * c.g - 0.0728499 * c.b,
        -0.1245505 * c.r + 1.1328999 * c.g - 0.0083494 * c.b,
        -0.0181508 * c.r - 0.1005789 * c.g + 1.1187297 * c.b
    );
}

// Forced scRGB mode: linear scRGB (linear BT.709, 1.0 = 80 nits) <-> PQ/BT.2020.
float3 ScRGBToPQ2020(float3 sc)
{
    // Standard Windows scRGB convention: linear channel 1.0 = 80 nits.
    // Standard PQ cannot represent negative light; clamp non-positive channels.
    float3 linearNits2020 = Linear709To2020(sc * 80.0);
    return float3(
        Nits2PQ(max(linearNits2020.r, 0.0)),
        Nits2PQ(max(linearNits2020.g, 0.0)),
        Nits2PQ(max(linearNits2020.b, 0.0))
    );
}

float3 PQ2020ToScRGB(float3 pq)
{
    float3 linearNits2020 = float3(
        PQ2Nits(saturate(pq.r)),
        PQ2Nits(saturate(pq.g)),
        PQ2Nits(saturate(pq.b))
    );
    float3 linear709 = Linear2020To709(linearNits2020);
    // Negative and >10000-nit excursions cannot be represented by standard PQ.
    return linear709 / 80.0;
}

float GetMaxChannel(float3 color)
{
    return max(color.r, max(color.g, color.b));
}

// Convert a PQ/BT.2020 RGB pixel to its physical photometric luminance Y (nits).
// RGB channels are individually PQ-decoded to absolute light, then weighted in linear BT.2020.
float GetPixelLuminanceNits(float3 pqColor)
{
    float3 linearNits = float3(
        PQ2Nits(saturate(pqColor.r)),
        PQ2Nits(saturate(pqColor.g)),
        PQ2Nits(saturate(pqColor.b))
    );
    return max(dot(linearNits, float3(0.2627, 0.6780, 0.0593)), 0.0);
}

// Represent the pixel's physical luminance on the PQ code-value axis.
float GetPixelLuminancePQ(float3 pqColor)
{
    return Nits2PQ(GetPixelLuminanceNits(pqColor));
}



// Input normalization pass: PQ mode is an exact copy; scRGB mode converts
// the incoming linear scRGB values into the plugin's internal PQ/BT.2020 space.
void PS_InputToPQ(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD, out float4 outColor : SV_Target)
{
    float4 src = tex2D(ReShade::BackBuffer, texcoord);
    if (!UI_UseScRGB)
        outColor = src;
    else
        outColor = float4(ScRGBToPQ2020(src.rgb), src.a);
}

// Final output pass: in PQ mode preserve the existing PQ output; in scRGB mode
// decode internal PQ/BT.2020 and return linear scRGB values for the Windows chain.
void PS_PQToOutput(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD, out float4 outColor : SV_Target)
{
    float4 src = tex2D(SamplerFinalPQ, texcoord);
    if (!UI_UseScRGB)
        outColor = src;
    else
        outColor = float4(PQ2020ToScRGB(src.rgb), src.a);
}

// -----------------------------------------------------------------------------
// Vector SDF Font Engine
// -----------------------------------------------------------------------------
float dfSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
    return length(pa - ba * h);
}

float sdRoundedBox(float2 p, float2 b, float r)
{
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

float DrawVectorChar(int charID, float2 p)
{
    float d = 1e5;

    if (charID == 0) {
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.8, 0.05)));
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.8, 0.95)));
        d = min(d, dfSegment(p, float2(0.8, 0.95), float2(0.2, 0.95)));
        d = min(d, dfSegment(p, float2(0.2, 0.95), float2(0.2, 0.05)));
    }
    else if (charID == 1) {
        d = min(d, dfSegment(p, float2(0.5, 0.05), float2(0.5, 0.95)));
        d = min(d, dfSegment(p, float2(0.25, 0.25), float2(0.5, 0.05)));
        d = min(d, dfSegment(p, float2(0.25, 0.95), float2(0.75, 0.95)));
    }
    else if (charID == 2) {
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.8, 0.05)));
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.8, 0.5)));
        d = min(d, dfSegment(p, float2(0.8, 0.5), float2(0.2, 0.5)));
        d = min(d, dfSegment(p, float2(0.2, 0.5), float2(0.2, 0.95)));
        d = min(d, dfSegment(p, float2(0.2, 0.95), float2(0.8, 0.95)));
    }
    else if (charID == 3) {
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.8, 0.05)));
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.8, 0.95)));
        d = min(d, dfSegment(p, float2(0.2, 0.5), float2(0.8, 0.5)));
        d = min(d, dfSegment(p, float2(0.2, 0.95), float2(0.8, 0.95)));
    }
    else if (charID == 4) {
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.2, 0.5)));
        d = min(d, dfSegment(p, float2(0.2, 0.5), float2(0.8, 0.5)));
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.8, 0.95)));
    }
    else if (charID == 5) {
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.2, 0.05)));
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.2, 0.5)));
        d = min(d, dfSegment(p, float2(0.2, 0.5), float2(0.8, 0.5)));
        d = min(d, dfSegment(p, float2(0.8, 0.5), float2(0.8, 0.95)));
        d = min(d, dfSegment(p, float2(0.8, 0.95), float2(0.2, 0.95)));
    }
    else if (charID == 6) {
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.2, 0.05)));
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.2, 0.95)));
        d = min(d, dfSegment(p, float2(0.2, 0.5), float2(0.8, 0.5)));
        d = min(d, dfSegment(p, float2(0.8, 0.5), float2(0.8, 0.95)));
        d = min(d, dfSegment(p, float2(0.8, 0.95), float2(0.2, 0.95)));
    }
    else if (charID == 7) {
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.8, 0.05)));
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.4, 0.95)));
    }
    else if (charID == 8) {
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.8, 0.05)));
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.8, 0.95)));
        d = min(d, dfSegment(p, float2(0.8, 0.95), float2(0.2, 0.95)));
        d = min(d, dfSegment(p, float2(0.2, 0.95), float2(0.2, 0.05)));
        d = min(d, dfSegment(p, float2(0.2, 0.5), float2(0.8, 0.5)));
    }
    else if (charID == 9) {
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.8, 0.05)));
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.2, 0.5)));
        d = min(d, dfSegment(p, float2(0.2, 0.5), float2(0.8, 0.5)));
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.8, 0.95)));
        d = min(d, dfSegment(p, float2(0.8, 0.95), float2(0.2, 0.95)));
    }
    else if (charID == 10) { // P
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.2, 0.95)));
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.8, 0.05)));
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.8, 0.5)));
        d = min(d, dfSegment(p, float2(0.8, 0.5), float2(0.2, 0.5)));
    }
    else if (charID == 11) { // E
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.2, 0.95)));
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.8, 0.05)));
        d = min(d, dfSegment(p, float2(0.2, 0.5), float2(0.7, 0.5)));
        d = min(d, dfSegment(p, float2(0.2, 0.95), float2(0.8, 0.95)));
    }
    else if (charID == 12) { // A
        d = min(d, dfSegment(p, float2(0.2, 0.95), float2(0.2, 0.05)));
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.8, 0.05)));
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.8, 0.95)));
        d = min(d, dfSegment(p, float2(0.2, 0.5), float2(0.8, 0.5)));
    }
    else if (charID == 13) { // K
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.2, 0.95)));
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.2, 0.5)));
        d = min(d, dfSegment(p, float2(0.2, 0.5), float2(0.8, 0.95)));
    }
    else if (charID == 14) { // N
        d = min(d, dfSegment(p, float2(0.2, 0.95), float2(0.2, 0.05)));
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.8, 0.95)));
        d = min(d, dfSegment(p, float2(0.8, 0.95), float2(0.8, 0.05)));
    }
    else if (charID == 15) { // I
        d = min(d, dfSegment(p, float2(0.5, 0.05), float2(0.5, 0.95)));
        d = min(d, dfSegment(p, float2(0.25, 0.05), float2(0.75, 0.05)));
        d = min(d, dfSegment(p, float2(0.25, 0.95), float2(0.75, 0.95)));
    }
    else if (charID == 16) { // T
        d = min(d, dfSegment(p, float2(0.15, 0.05), float2(0.85, 0.05)));
        d = min(d, dfSegment(p, float2(0.5, 0.05), float2(0.5, 0.95)));
    }
    else if (charID == 17) { // S
        d = min(d, dfSegment(p, float2(0.8, 0.05), float2(0.2, 0.05)));
        d = min(d, dfSegment(p, float2(0.2, 0.05), float2(0.2, 0.5)));
        d = min(d, dfSegment(p, float2(0.2, 0.5), float2(0.8, 0.5)));
        d = min(d, dfSegment(p, float2(0.8, 0.5), float2(0.8, 0.95)));
        d = min(d, dfSegment(p, float2(0.8, 0.95), float2(0.2, 0.95)));
    }
    else if (charID == 18) { // :
        d = min(d, length(p - float2(0.5, 0.3)));
        d = min(d, length(p - float2(0.5, 0.7)));
    }

    return d;
}

// -----------------------------------------------------------------------------
// Pass 0: 5x5 Spatial Median Filter on PQ-encoded physical pixel luminance Y
// The 13th-highest of 25 samples is used, rejecting isolated tiny highlights.
// -----------------------------------------------------------------------------
void PS_SpatialMedian5x5(
    in float4 pos : SV_Position,
    in float2 texcoord : TEXCOORD,
    out float outCleanPQ : SV_Target)
{
    // Keep the baseline filter intact, but skip its sampling work in compute mode.
    if (!UI_UseBaselinePeakDetection)
    {
        outCleanPQ = 0.0;
        return;
    }

    // 当前输出纹理是 32x32。
    // 每个输出像素对应成熟版峰值分析器的一个采样位置。
    float2 sampleIndex = floor(pos.xy);
    float2 sampleUV = sampleIndex / 31.0;

    // 邻域偏移仍然使用原图的像素尺寸。
    float2 texelSize = BUFFER_PIXEL_SIZE;
    float v[25];

    int idx = 0;

    [unroll]
    for (int dy = -2; dy <= 2; dy++)
    {
        [unroll]
        for (int dx = -2; dx <= 2; dx++)
        {
            float2 offset = float2(dx, dy) * texelSize;
            float3 col = tex2D(
                SamplerWorkingPQ,
                sampleUV + offset
            ).rgb;

            v[idx++] = GetPixelLuminancePQ(col);
        }
    }

    // 保留成熟版原有排序逻辑。
    // v[12] 为 25 个样本中的中值。
    [unroll]
    for (int i = 0; i < 13; i++)
    {
        [unroll]
        for (int j = i + 1; j < 25; j++)
        {
            if (v[j] > v[i])
            {
                float temp = v[i];
                v[i] = v[j];
                v[j] = temp;
            }
        }
    }

    outCleanPQ = v[12];
}

// -----------------------------------------------------------------------------
// Pass 1: Dynamic Peak Detection with Anti-Flicker Adaptation
// -----------------------------------------------------------------------------
bool PeakRefreshDue()
{
    float4 lastData = tex2Dfetch(SamplerPeakDataACompute, int2(0, 0));
    float accumTime = lastData.b + UI_FrameTime;
    return (accumTime >= (float)UI_RefreshRateMS || lastData.a <= 1.0);
}

// Reset the single global accumulator only when the next peak scan is due.
void CS_ResetPeak(uint3 DTID : SV_DispatchThreadID)
{
    if (UI_UseBaselinePeakDetection || !PeakRefreshDue())
        return;

    tex2Dstore(StoragePeakMax, int2(0, 0), 0u);
}

groupshared uint GroupPeakMilliNits[64];

void CS_ScanPeak(
    uint3 GID  : SV_GroupID,
    uint3 GTID : SV_GroupThreadID,
    uint3 DTID : SV_DispatchThreadID)
{
    // Uniform early-out: no source-image reads unless compute mode needs a refresh.
    if (UI_UseBaselinePeakDetection || !PeakRefreshDue())
        return;

    uint lane = GTID.x + GTID.y * 8;
    float threadMaxNits = 0.0;

    // One thread handles one source pixel. An 8x8 group covers an 8x8 tile.
    if (DTID.x < BUFFER_WIDTH && DTID.y < BUFFER_HEIGHT)
    {
        int2 pixelPos = int2(DTID.xy);
        float pixelNits = GetPixelLuminanceNits(tex2Dfetch(SamplerWorkingPQCompute, pixelPos).rgb);
        threadMaxNits = max(threadMaxNits, pixelNits);
    }

    GroupPeakMilliNits[lane] = (uint)(max(threadMaxNits, 0.0) * 1000.0 + 0.5);
    barrier();

    [unroll]
    for (uint stride = 32; stride > 0; stride >>= 1)
    {
        if (lane < stride)
            GroupPeakMilliNits[lane] = max(GroupPeakMilliNits[lane], GroupPeakMilliNits[lane + stride]);
        barrier();
    }

    // One global atomic operation per 8x8 tile, not per source pixel.
    if (lane == 0)
        atomicMax(StoragePeakMax, int2(0, 0), GroupPeakMilliNits[0]);
}

void PS_AnalyzePeak(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD, out float4 outData : SV_Target)
{
    float4 lastData = tex2D(SamplerPeakDataA, float2(0.5, 0.5));
    float rawPeak = lastData.r;
    float smoothedPeak = lastData.g;
    float accumTime = lastData.b + UI_FrameTime;
    float osdLatchedPeak = lastData.a;

    if (accumTime >= (float)UI_RefreshRateMS || osdLatchedPeak <= 1.0)
    {
        if (UI_UseBaselinePeakDetection)
        {
            // Original baseline algorithm: 32x32 samples from the 5x5 median-filtered texture.
            float maxPQ = 0.0;

            [unroll]
            for (int y = 0; y < 32; y++)
            {
                [unroll]
                for (int x = 0; x < 32; x++)
                {
                    float2 uv = (float2((float)x, (float)y) + 0.5) / 32.0;
                    float cleanPQ = tex2D(SamplerCleanLuma, uv).r;
                    maxPQ = max(maxPQ, cleanPQ);
                }
            }

            rawPeak = PQ2Nits(maxPQ);
        }
        else
        {
            // Full-screen parallel maximum, stored as unsigned millinits.
            rawPeak = (float)tex2Dfetch(SamplerPeakMax, int2(0, 0)) / 1000.0;
        }
        accumTime = 0.0;
        osdLatchedPeak = rawPeak;
    }

    float deltaSec = max(UI_FrameTime * 0.001, 0.001);
    float adaptSpeed = (rawPeak > smoothedPeak) ? UI_AdaptationSpeedRise : UI_AdaptationSpeedFall;
    float alpha = 1.0 - exp(-deltaSec * adaptSpeed);
    
    smoothedPeak = lerp(smoothedPeak, rawPeak, alpha);

    outData = float4(rawPeak, smoothedPeak, accumTime, osdLatchedPeak);
}

void PS_CopyPeakData(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD, out float4 outData : SV_Target)
{
    outData = tex2D(SamplerPeakDataB, float2(0.5, 0.5));
}

// -----------------------------------------------------------------------------
// HDR Color Expansion: ICtCp chroma radius expansion driven by PQ(Y) delta
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// HDR Color Expansion: proper BT.2100 ICtCp path
// PQ RGB -> LMS (linear) -> PQ encoded LMS -> ICtCp
// Only Ct/Cp are expanded. I is untouched.
// -----------------------------------------------------------------------------
float3 PQToLMSPrime(float3 pq)
{
    // BT.2020 RGB -> LMS matrix (linear-light), then ST 2084 PQ encoding.
    float3 rgb = float3(
        PQ2Nits(saturate(pq.r)),
        PQ2Nits(saturate(pq.g)),
        PQ2Nits(saturate(pq.b))
    );

    float3 lms;
    lms.r = 0.412109375 * rgb.r + 0.523925781 * rgb.g + 0.063964844 * rgb.b;
    lms.g = 0.166748047 * rgb.r + 0.720458984 * rgb.g + 0.112792969 * rgb.b;
    lms.b = 0.024169922 * rgb.r + 0.075439453 * rgb.g + 0.900390625 * rgb.b;

    return float3(Nits2PQ(lms.r), Nits2PQ(lms.g), Nits2PQ(lms.b));
}

// Standard BT.2100 ICtCp forward matrix.
// Inputs are PQ-encoded LMS values (L', M', S').
float3 LMSPrimeToICtCp(float3 lmsP)
{
    return float3(
        0.5 * lmsP.r + 0.5 * lmsP.g,
        1.61376953125 * lmsP.r - 3.323486328125 * lmsP.g + 1.709716796875 * lmsP.b,
        4.378173828125 * lmsP.r - 4.24560546875 * lmsP.g - 0.132568359375 * lmsP.b
    );
}

// Standard inverse BT.2100 ICtCp matrix.
float3 ICtCpToLMSPrime(float3 ictcp)
{
    float I  = ictcp.x;
    float Ct = ictcp.y;
    float Cp = ictcp.z;

    return float3(
        I + 0.0086090370379328 * Ct + 0.111029625003026 * Cp,
        I - 0.0086090370379328 * Ct - 0.111029625003026 * Cp,
        I + 0.560031335710679 * Ct - 0.320627174987319 * Cp
    );
}

// Convert expanded ICtCp to linear-light BT.2020 RGB (nits).
// Clamp only the intermediate PQ-encoded LMS' coordinates to their legal
// [0, 1] range; do not clip RGB here, because luminance is restored first.
float3 ICtCpToLinearRGB(float3 ictcp)
{
    float3 lmsPQ = saturate(ICtCpToLMSPrime(ictcp));
    float3 lms = float3(
        PQ2Nits(lmsPQ.r),
        PQ2Nits(lmsPQ.g),
        PQ2Nits(lmsPQ.b)
    );

    // Exact inverse of the BT.2020 RGB -> LMS matrix used in PQToLMSPrime.
    // The previous coefficients did not invert that forward matrix and could
    // therefore introduce unintended hue shifts during ICtCp round-tripping.
    float3 rgb;
    rgb.r =  3.436606694 * lms.r - 2.50645212  * lms.g + 0.06984542  * lms.b;
    rgb.g = -0.79132956  * lms.r + 1.98360045  * lms.g - 0.19227090  * lms.b;
    rgb.b = -0.02594990  * lms.r - 0.09891371  * lms.g + 1.12486361  * lms.b;

    return rgb;
}

float3 PQRGB_to_ICtCp(float3 pq)
{
    return LMSPrimeToICtCp(PQToLMSPrime(pq));
}

// BT.2020 linear-light luminance.
float GetLinearLuminance(float3 rgbLinear)
{
    return 0.2627 * rgbLinear.r +
           0.6780 * rgbLinear.g +
           0.0593 * rgbLinear.b;
}

float3 ApplyColorExpansion(float3 pq, float deltaPQ, float targetY)
{
    if (UI_ColorExpansionStrength <= 0.0 || deltaPQ <= 0.0)
        return pq;

    float3 ictcp = PQRGB_to_ICtCp(pq);

    float gain = 1.0 + UI_ColorExpansionStrength * deltaPQ*0.5;
    ictcp.y *= gain;
    ictcp.z *= gain;

    // If expanded LMS' coordinates exceed the legal PQ range, clamp them
    // to the nearest boundary instead of bypassing this pixel. This avoids
    // abrupt pixel-to-pixel changes between expanded and unexpanded colors.
    // RGB itself remains unclipped until after mapped-luminance restoration.
    float3 expandedLinear = ICtCpToLinearRGB(ictcp);
    float currentY = GetLinearLuminance(expandedLinear);

    if (currentY <= 0.00001 || targetY <= 0.00001)
        return pq;

    expandedLinear *= targetY / currentY;

    // Clip only the final RGB after luminance restoration.
    expandedLinear = clamp(expandedLinear, 0.0, 10000.0);
    return float3(
        Nits2PQ(expandedLinear.r),
        Nits2PQ(expandedLinear.g),
        Nits2PQ(expandedLinear.b)
    );
}
// -----------------------------------------------------------------------------
// Pass 2: Dynamic PQ Code Value Expansion Mapping
// -----------------------------------------------------------------------------
void PS_PQExpansionMap(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD, out float4 outColor : SV_Target)
{
    float3 col = tex2D(SamplerWorkingPQ, texcoord).rgb;

    // Global peak is derived from the temporally smoothed physical luminance peak.
    // Apply the user-defined floor only to the mapping reference; measured peak data
    // and the OSD remain untouched.
    float dynamicPeakNits = tex2D(SamplerPeakDataA, float2(0.5, 0.5)).g;
    float measuredPeakPQ = Nits2PQ(max(dynamicPeakNits, 1.0));
    float mappingPeakPQ = max(measuredPeakPQ, UI_MappingPeakFloorPQ);
    float M = Nits2PQ((float)UI_TargetNits);

    if (mappingPeakPQ >= M || mappingPeakPQ <= 0.0)
    {
        outColor = float4(col, 1.0);
        return;
    }

    // The curve coordinate is PQ(Y), where Y is the pixel's BT.2020 photometric luminance.
    float Y1 = GetPixelLuminanceNits(col);
    if (Y1 <= 0.00001)
    {
        outColor = float4(col, 1.0);
        return;
    }
    float origPQ = Nits2PQ(Y1);

    // 1. Hard dark-region protection, now applied to PQ(Y).
    if (origPQ <= UI_PQ_CV99)
    {
        outColor = float4(col, 1.0);
        return;
    }

    // 2. Preserve the original PQ-domain expansion delta and cap.
    float rawDelta = M - mappingPeakPQ;
    float effectiveDelta = min(rawDelta, UI_MaxExpansionDelta);

    // Preserve the original high-highlight branch, but interpret its target as pixel PQ(Y).
    if (origPQ >= mappingPeakPQ)
    {
        // Outlier highlights use the same additive PQ-code delta as the detected
        // peak, but are individually capped at the user's target peak M.
        float mappedPQ = min(origPQ + effectiveDelta, M);
        float targetY = PQ2Nits(saturate(mappedPQ));
        float scaleY = targetY / max(Y1, 0.00001);

        // Reconstruct color by uniformly scaling linear-light RGB, then re-encode to PQ.
        float3 linearNits = float3(
            PQ2Nits(saturate(col.r)),
            PQ2Nits(saturate(col.g)),
            PQ2Nits(saturate(col.b))
        );
        float3 expandedLinear = linearNits * scaleY;
        float3 expandedPQ = float3(
            Nits2PQ(expandedLinear.r),
            Nits2PQ(expandedLinear.g),
            Nits2PQ(expandedLinear.b)
        );
        expandedPQ = ApplyColorExpansion(expandedPQ, effectiveDelta, targetY);
        outColor = float4(expandedPQ, 1.0);
        return;
    }

    // 3. Normalize PQ(Y) over the same original protected-dark-to-peak range.
    float safeRange = max(mappingPeakPQ - UI_PQ_CV99, 0.00001);
    float normPQ = clamp((origPQ - UI_PQ_CV99) / safeRange, 0.0, 1.0);

    // 4. Original selectable curve math, intentionally kept unchanged.
    float curvedNormPQ = 0.0;

    if (!UI_UseGammaCurve)
    {
        float Px = clamp(UI_CurvePivot, 0.05, 0.95);
        float k = ((float)UI_GainCurveStrength - 50.0) / 50.0;
        float multiplier = 1.5;
        float Py = (k >= 0.0) ? lerp(Px, Px + (1.0 - Px) * multiplier, k)
                              : lerp(Px, Px - Px * multiplier, -k);

        float A = 1.0 - 2.0 * Px;
        float B = 2.0 * Px;
        float C = -normPQ;

        float t = normPQ;

        if (abs(A) < 0.0001)
        {
            t = normPQ;
        }
        else
        {
            // Numerically stable quadratic solution (preserved from the original).
            float discriminant = max(0.0, B * B - 4.0 * A * C);
            t = (-2.0 * C) / (B + sqrt(discriminant));
        }

        t = clamp(t, 0.0, 1.0);
        curvedNormPQ = 2.0 * (1.0 - t) * t * Py + t * t;
    }
    else
    {
        float Px = clamp(UI_CurvePivot, 0.05, 0.95);
        float k = ((float)UI_GainCurveStrength - 50.0) / 50.0;
        float multiplier = 1.5;
        float Py = (k >= 0.0) ? lerp(Px, Px + (1.0 - Px) * multiplier, k)
                              : lerp(Px, Px - Px * multiplier, -k);

        if (normPQ < Px)
        {
            curvedNormPQ = normPQ * (Py / max(Px, 0.0001));
        }
        else
        {
            curvedNormPQ = Py + (normPQ - Px) * ((1.0 - Py) / max(1.0 - Px, 0.0001));
        }
    }

    // 5. Keep the original additive PQ-code mapping, now operating on PQ(Y).
    float newPQ = origPQ + curvedNormPQ * effectiveDelta;
    float targetY = PQ2Nits(saturate(newPQ));

    // 6. Match the target physical luminance by uniformly scaling linear-light RGB.
    float scaleY = targetY / max(Y1, 0.00001);
    float3 linearNits = float3(
        PQ2Nits(saturate(col.r)),
        PQ2Nits(saturate(col.g)),
        PQ2Nits(saturate(col.b))
    );
    float3 expandedLinear = linearNits * scaleY;
    float3 expandedPQ = float3(
        Nits2PQ(expandedLinear.r),
        Nits2PQ(expandedLinear.g),
        Nits2PQ(expandedLinear.b)
    );

    expandedPQ = ApplyColorExpansion(expandedPQ, curvedNormPQ * effectiveDelta, targetY);

    outColor = float4(expandedPQ, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 3: Directional Local Gradient Smoothing
// -----------------------------------------------------------------------------
void PS_GradientSmooth(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD, out float4 outColor : SV_Target)
{
    float3 centerCol = tex2D(SamplerMappedColor, texcoord).rgb;

    if (!UI_EnableSmoothing)
    {
        outColor = float4(centerCol, 1.0);
        return;
    }

    float2 pSize = BUFFER_PIXEL_SIZE;

    float l = GetMaxChannel(tex2D(SamplerMappedColor, texcoord + float2(-pSize.x, 0)).rgb);
    float r = GetMaxChannel(tex2D(SamplerMappedColor, texcoord + float2(pSize.x, 0)).rgb);
    float t = GetMaxChannel(tex2D(SamplerMappedColor, texcoord + float2(0, -pSize.y)).rgb);
    float b = GetMaxChannel(tex2D(SamplerMappedColor, texcoord + float2(0, pSize.y)).rgb);

    float dx = r - l;
    float dy = b - t;
    float gradMag = sqrt(dx * dx + dy * dy);

    if (gradMag > 0.0001 && gradMag < 0.015)
    {
        float2 dir = normalize(float2(dx, dy));
        float3 s1 = tex2D(SamplerMappedColor, texcoord - dir * pSize).rgb;
        float3 s2 = tex2D(SamplerMappedColor, texcoord + dir * pSize).rgb;

        centerCol = (s1 + centerCol + s2) / 3.0;
    }

    outColor = float4(centerCol, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 4: Tech HUD OSD Panel Render Pass
// -----------------------------------------------------------------------------
void PS_RenderOSD(in float4 pos : SV_Position, in float2 texcoord : TEXCOORD, out float4 outColor : SV_Target)
{
    // 从 Pass 3 的输出纹理采样，而不是直接从 BackBuffer 采样
    float3 color = tex2D(SamplerSmoothedColor, texcoord).rgb;

    if (!UI_ShowOSD)
    {
        outColor = float4(color, 1.0);
        return;
    }

    float currentPeakNits = tex2D(SamplerPeakDataA, float2(0.5, 0.5)).r;
    int displayValue = clamp((int)currentPeakNits, 0, 99999);

    int strIDs[20];
    int totalChars = 0;

    strIDs[totalChars++] = 10; // P
    strIDs[totalChars++] = 11; // E
    strIDs[totalChars++] = 12; // A
    strIDs[totalChars++] = 13; // K
    strIDs[totalChars++] = 18; // :
    strIDs[totalChars++] = 19; // Space

    int digits[5];
    int valLen = 0;
    int tempVal = displayValue;

    if (tempVal == 0)
    {
        digits[0] = 0;
        valLen = 1;
    }
    else
    {
        while (tempVal > 0 && valLen < 5)
        {
            digits[valLen++] = tempVal % 10;
            tempVal /= 10;
        }
    }

    for (int d = valLen - 1; d >= 0; d--)
    {
        strIDs[totalChars++] = digits[d];
    }

    strIDs[totalChars++] = 19; // Space
    strIDs[totalChars++] = 14; // N
    strIDs[totalChars++] = 15; // I
    strIDs[totalChars++] = 16; // T
    strIDs[totalChars++] = 17; // S

    float scale = UI_OSDScale;
    float charW = 14.0 * scale;
    float charH = 20.0 * scale;
    float padX = 16.0 * scale;
    float padY = 12.0 * scale;
    float barH = 4.0 * scale;
    float gapY = 8.0 * scale;

    float textW = totalChars * charW;
    float panelW = textW + padX * 2.0;
    float panelH = padY * 2.0 + charH + gapY + barH;

    float2 panelOrigin = float2((float)UI_OSDPosX, (float)UI_OSDPosY);
    float2 p = pos.xy - panelOrigin;
    float2 panelCenter = float2(panelW, panelH) * 0.5;

    float dBox = sdRoundedBox(p - panelCenter, panelCenter, 6.0 * scale);

    if (dBox <= 0.0)
    {
        float alphaBg = smoothstep(0.0, -2.0, dBox) * 0.82;
        float3 bgCol = float3(0.015, 0.018, 0.025);
        color = lerp(color, bgCol, alphaBg);

        float topBorderDist = abs(p.y - 1.0) + max(0.0, abs(p.x - panelCenter.x) - panelCenter.x + 4.0);
        float topGlow = smoothstep(1.5 * scale, 0.0, topBorderDist);
        float osdPQGlow = Nits2PQ(UI_OSDBrightnessNits * 1.5);
        color += float3(0.2, 0.5, 0.9) * osdPQGlow * topGlow * 0.6;

        float2 textP = p - float2(padX, padY);
        if (textP.x >= 0.0 && textP.x < textW && textP.y >= 0.0 && textP.y < charH)
        {
            int charIdx = (int)floor(textP.x / charW);
            if (charIdx >= 0 && charIdx < totalChars)
            {
                int cID = strIDs[charIdx];
                if (cID != 19)
                {
                    float localX = textP.x - ((float)charIdx * charW);
                    float2 charUV = float2(localX / charW, textP.y / charH);

                    float dist = DrawVectorChar(cID, charUV) * charH;
                    float thickness = 1.6 * scale;
                    
                    float distShadow = DrawVectorChar(cID, charUV - float2(0.04, 0.04)) * charH;
                    float shadowAlpha = smoothstep(thickness + 1.0, thickness - 1.0, distShadow) * 0.5;
                    color = lerp(color, float3(0.0, 0.0, 0.0), shadowAlpha);

                    float textAlpha = smoothstep(thickness, thickness - 1.2, dist);
                    if (textAlpha > 0.0)
                    {
                        float targetPQ = Nits2PQ(UI_OSDBrightnessNits);
                        
                        float3 textCol = (charIdx >= 5 && charIdx < 5 + valLen) 
                                       ? float3(1.0, 0.8, 0.3) * targetPQ 
                                       : float3(0.85, 0.9, 0.95) * targetPQ;

                        color = lerp(color, textCol, textAlpha);
                    }
                }
            }
        }

        float2 barP = p - float2(padX, padY + charH + gapY);
        if (barP.x >= 0.0 && barP.x < textW && barP.y >= 0.0 && barP.y < barH)
        {
            float fillRatio = clamp(currentPeakNits / max((float)UI_TargetNits, 1.0), 0.0, 1.0);
            float barFillW = textW * fillRatio;

            float barBgPQ = Nits2PQ(UI_OSDBrightnessNits * 0.15);
            color = float3(barBgPQ, barBgPQ, barBgPQ);

            if (barP.x < barFillW)
            {
                float barFillPQ = Nits2PQ(UI_OSDBrightnessNits * 1.2);
                float3 barCol = lerp(float3(0.2, 0.7, 1.0), float3(1.0, 0.6, 0.1), fillRatio) * barFillPQ;
                color = barCol;
            }
        }
    }

    outColor = float4(color, 1.0);
}

// -----------------------------------------------------------------------------
// Pipeline
// -----------------------------------------------------------------------------
technique DynamicPQMapper < ui_label = "HDR向上动态映射"; >
{
    pass Pass0_InputNormalize
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_InputToPQ;
        RenderTarget = TexWorkingPQ;
    }

    pass Pass0_ResetPeak
    {
        ComputeShader = CS_ResetPeak<1, 1>;
        DispatchSizeX = 1;
        DispatchSizeY = 1;
    }

    pass Pass0_ScanPeak
    {
        ComputeShader = CS_ScanPeak<8, 8>;
        DispatchSizeX = (BUFFER_WIDTH + 7) / 8;
        DispatchSizeY = (BUFFER_HEIGHT + 7) / 8;
    }

    pass Pass0_SpatialMedian
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SpatialMedian5x5;
        RenderTarget = TexCleanLuma;
    }

    pass Pass1_AnalyzePeak
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_AnalyzePeak;
        RenderTarget = TexPeakDataB;
    }

    pass Pass1_Copy
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_CopyPeakData;
        RenderTarget = TexPeakDataA;
    }

    pass Pass2_PQExpansionMap
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_PQExpansionMap;
        RenderTarget = TexMappedColor;
    }

    pass Pass3_GradientSmooth
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_GradientSmooth;
        RenderTarget = TexSmoothedColor;
    }

    pass Pass4_RenderOSD
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_RenderOSD;
        RenderTarget = TexFinalPQ;
    }

    pass Pass5_OutputConvert
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_PQToOutput;
    }
}
