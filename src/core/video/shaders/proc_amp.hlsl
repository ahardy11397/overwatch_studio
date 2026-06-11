Texture2D shaderTexture : register(t0);
SamplerState Sampler : register(s0);

cbuffer ProcAmpBuffer : register(b0)
{
    float brightness; // range [-1.0f, 1.0f]
    float contrast;   // range [0.0f, 2.0f]
    float saturation; // range [0.0f, 2.0f]
    float gamma;      // range [0.01f, 3.0f]
    float hueAngle;   // Hue rotation in radians [0.0f, 6.28318f]
};

struct PS_INPUT
{
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
};

float3 HueRotate(float3 color, float angle)
{
    float3 k = float3(0.57735, 0.57735, 0.57735);
    float cosAngle = cos(angle);
    return color * cosAngle + cross(k, color) * sin(angle) + k * dot(k, color) * (1.0 - cosAngle);
}

float4 main(PS_INPUT input) : SV_TARGET
{
    float4 color = shaderTexture.Sample(Sampler, input.uv);
    
    // 1. Adjust Brightness
    color.rgb += brightness;
    
    // 2. Adjust Contrast
    color.rgb = (color.rgb - 0.5f) * contrast + 0.5f;
    
    // 3. Adjust Saturation
    float luma = dot(color.rgb, float3(0.299f, 0.587f, 0.114f));
    color.rgb = lerp(float3(luma, luma, luma), color.rgb, saturation);
    
    // 4. Adjust Gamma
    color.rgb = pow(max(color.rgb, 0.0f), gamma);
    
    // 5. Shift Hue
    color.rgb = HueRotate(color.rgb, hueAngle);
    
    return saturate(color);
}
