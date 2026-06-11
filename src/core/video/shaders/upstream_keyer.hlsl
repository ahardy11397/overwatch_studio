Texture2D shaderTexture : register(t0);
SamplerState Sampler : register(s0);

cbuffer UpstreamKeyerBuffer : register(b0)
{
    float2 scale;          // Resize factor (e.g. float2(0.5f, 0.5f))
    float2 position;       // Canvas offset coordinate (e.g. float2(0.2f, 0.2f))
    float4 crop;           // Cropping bounds: [Left, Right, Top, Bottom]
};

struct PS_INPUT
{
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
};

float4 main(PS_INPUT input) : SV_TARGET
{
    float2 uv = input.uv;
    
    // 1. Crop check
    if (uv.x < crop.x || uv.x > crop.y || uv.y < crop.z || uv.y > crop.w) {
        return float4(0.0f, 0.0f, 0.0f, 0.0f);
    }
    
    // 2. Picture-in-Picture rendering boundary check
    float2 pipUV = (uv - position) / scale;
    if (pipUV.x >= 0.0f && pipUV.x <= 1.0f && pipUV.y >= 0.0f && pipUV.y <= 1.0f) {
        return shaderTexture.Sample(Sampler, pipUV);
    }
    
    return float4(0.0f, 0.0f, 0.0f, 0.0f);
}
