Texture2D bgTexture : register(t0);
Texture2D dskTexture : register(t1);
SamplerState Sampler : register(s0);

cbuffer DSKBuffer : register(b0)
{
    float opacity;
    float3 padding;
};

struct PS_INPUT
{
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
};

float4 main(PS_INPUT input) : SV_TARGET
{
    float4 bg = bgTexture.Sample(Sampler, input.uv);
    float4 overlay = dskTexture.Sample(Sampler, input.uv);
    
    float alpha = overlay.a * opacity;
    
    float4 finalColor;
    finalColor.rgb = lerp(bg.rgb, overlay.rgb, alpha);
    finalColor.a = max(bg.a, alpha);
    
    return finalColor;
}
