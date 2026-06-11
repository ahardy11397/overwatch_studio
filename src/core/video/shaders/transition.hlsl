Texture2D textureA : register(t0);
Texture2D textureB : register(t1);
SamplerState Sampler : register(s0);

cbuffer TransitionBuffer : register(b0)
{
    float progress; // range [0.0f, 1.0f]
    uint32_t type;  // 0 = Cut, 1 = Mix, 2 = Horiz Wipe, 3 = Vert Wipe
    float2 padding;
};

struct PS_INPUT
{
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
};

float4 main(PS_INPUT input) : SV_TARGET
{
    float4 colorA = textureA.Sample(Sampler, input.uv);
    float4 colorB = textureB.Sample(Sampler, input.uv);

    if (type == 0)
    {
        return progress < 1.0f ? colorA : colorB;
    }
    else if (type == 1)
    {
        return lerp(colorA, colorB, progress);
    }
    else if (type == 2)
    {
        return input.uv.x < progress ? colorB : colorA;
    }
    else if (type == 3)
    {
        return input.uv.y < progress ? colorB : colorA;
    }

    return colorA;
}
