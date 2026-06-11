Texture2D fillTexture : register(t0);
Texture2D keyTexture  : register(t1);
Texture2D bgTexture   : register(t2);
SamplerState Sampler  : register(s0);

struct PS_INPUT
{
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
};

float4 main(PS_INPUT input) : SV_TARGET
{
    float4 fill = fillTexture.Sample(Sampler, input.uv);
    float4 key = keyTexture.Sample(Sampler, input.uv);
    float4 bg = bgTexture.Sample(Sampler, input.uv);
    
    // Extract key alpha from Key texture red channel
    float alpha = key.r;
    
    float4 finalColor;
    finalColor.rgb = fill.rgb * alpha + bg.rgb * (1.0f - alpha);
    finalColor.a = max(fill.a * alpha, bg.a);
    
    return finalColor;
}
