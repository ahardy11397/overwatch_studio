Texture2D shaderTexture : register(t0);
SamplerState Sampler : register(s0);

cbuffer ChromaKeyBuffer : register(b0)
{
    float3 keyColor;     // Backing color in RGB (e.g. Green or Blue)
    float similarity;   // Similarity threshold range [0.0f, 1.0f]
    float smoothness;   // Boundary edge blend smoothness [0.0f, 1.0f]
    float spillRange;   // Spill suppression intensity range [0.0f, 1.0f]
    float2 padding;
};

struct PS_INPUT
{
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
};

float4 main(PS_INPUT input) : SV_TARGET
{
    float4 color = shaderTexture.Sample(Sampler, input.uv);
    
    // 1. Calculate color distance in RGB space to detect backing screen
    float colorDist = distance(color.rgb, keyColor);
    
    // 2. Derive alpha transparency map using smooth bounds
    float alpha = smoothstep(similarity - smoothness, similarity + smoothness, colorDist);
    
    // 3. Dynamic green/blue spill suppression based on key color dominance
    if (keyColor.g > max(keyColor.r, keyColor.b))
    {
        float maxRedBlue = max(color.r, color.b);
        if (color.g > maxRedBlue)
        {
            color.g = min(color.g, lerp(color.g, maxRedBlue, spillRange));
        }
    }
    else if (keyColor.b > max(keyColor.r, keyColor.g))
    {
        float maxRedGreen = max(color.r, color.g);
        if (color.b > maxRedGreen)
        {
            color.b = min(color.b, lerp(color.b, maxRedGreen, spillRange));
        }
    }
    
    color.a *= alpha;
    return color;
}
