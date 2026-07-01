#pragma once

#ifndef REALTIME_SAFE
#if defined(__clang__)
#define REALTIME_SAFE [[clang::nonblocking]]
#else
#define REALTIME_SAFE
#endif
#endif

#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <DirectXMath.h>
#include <cassert>
#include <string>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")

using Microsoft::WRL::ComPtr;

// Constant Buffers
struct alignas(16) ProcAmpBuffer {
    float brightness; // range [-1.0f, 1.0f]
    float contrast;   // range [0.0f, 2.0f]
    float saturation; // range [0.0f, 2.0f]
    float gamma;      // range [0.01f, 3.0f]
    float hueAngle;   // Hue rotation in radians
    float padding[3];
};

struct alignas(16) ChromaKeyBuffer {
    DirectX::XMFLOAT3 keyColor;
    float similarity;
    float smoothness;
    float spillRange;
    float padding[2];
};

struct alignas(16) UpstreamKeyerBuffer {
    DirectX::XMFLOAT2 scale;
    DirectX::XMFLOAT2 position;
    DirectX::XMFLOAT4 crop; // [Left, Right, Top, Bottom]
};

struct alignas(16) TransitionBuffer {
    float progress; // range [0.0f, 1.0f]
    uint32_t type;  // 0 = Cut, 1 = Mix/Crossfade, 2 = Horiz Wipe, 3 = Vert Wipe
    float padding[2];
};

struct alignas(16) DSKBuffer {
    float opacity;  // range [0.0f, 1.0f]
    float padding[3];
};

// Embedded HLSL Code
namespace Shaders {
    inline const char* quadVS = R"(
        struct VS_INPUT
        {
            float3 pos : POSITION;
            float2 uv : TEXCOORD0;
        };
        struct VS_OUTPUT
        {
            float4 pos : SV_POSITION;
            float2 uv : TEXCOORD0;
        };
        VS_OUTPUT main(VS_INPUT input)
        {
            VS_OUTPUT output;
            output.pos = float4(input.pos, 1.0f);
            output.uv = input.uv;
            return output;
        }
    )";

    inline const char* procAmpPS = R"(
        Texture2D shaderTexture : register(t0);
        SamplerState Sampler : register(s0);
        cbuffer ProcAmpBuffer : register(b0)
        {
            float brightness;
            float contrast;
            float saturation;
            float gamma;
            float hueAngle;
        };
        float3 HueRotate(float3 color, float angle)
        {
            float3 k = float3(0.57735, 0.57735, 0.57735);
            float cosAngle = cos(angle);
            return color * cosAngle + cross(k, color) * sin(angle) + k * dot(k, color) * (1.0 - cosAngle);
        }
        struct PS_INPUT { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
        float4 main(PS_INPUT input) : SV_TARGET
        {
            float4 color = shaderTexture.Sample(Sampler, input.uv);
            color.rgb += brightness;
            color.rgb = (color.rgb - 0.5f) * contrast + 0.5f;
            float luma = dot(color.rgb, float3(0.299f, 0.587f, 0.114f));
            color.rgb = lerp(float3(luma, luma, luma), color.rgb, saturation);
            color.rgb = pow(max(color.rgb, 0.0f), gamma);
            color.rgb = HueRotate(color.rgb, hueAngle);
            return saturate(color);
        }
    )";

    inline const char* chromaKeyPS = R"(
        Texture2D shaderTexture : register(t0);
        SamplerState Sampler : register(s0);
        cbuffer ChromaKeyBuffer : register(b0)
        {
            float3 keyColor;
            float similarity;
            float smoothness;
            float spillRange;
        };
        struct PS_INPUT { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
        float4 main(PS_INPUT input) : SV_TARGET
        {
            float4 color = shaderTexture.Sample(Sampler, input.uv);
            float colorDist = distance(color.rgb, keyColor);
            float alpha = smoothstep(similarity - smoothness, similarity + smoothness, colorDist);
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
    )";

    inline const char* upstreamKeyerPS = R"(
        Texture2D shaderTexture : register(t0);
        SamplerState Sampler : register(s0);
        cbuffer UpstreamKeyerBuffer : register(b0)
        {
            float2 scale;
            float2 position;
            float4 crop;
        };
        struct PS_INPUT { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
        float4 main(PS_INPUT input) : SV_TARGET
        {
            float2 uv = input.uv;
            if (uv.x < crop.x || uv.x > crop.y || uv.y < crop.z || uv.y > crop.w) {
                return float4(0.0f, 0.0f, 0.0f, 0.0f);
            }
            float2 pipUV = (uv - position) / scale;
            if (pipUV.x >= 0.0f && pipUV.x <= 1.0f && pipUV.y >= 0.0f && pipUV.y <= 1.0f) {
                return shaderTexture.Sample(Sampler, pipUV);
            }
            return float4(0.0f, 0.0f, 0.0f, 0.0f);
        }
    )";

    inline const char* fillKeyBlendPS = R"(
        Texture2D fillTexture : register(t0);
        Texture2D keyTexture  : register(t1);
        Texture2D bgTexture   : register(t2);
        SamplerState Sampler  : register(s0);
        struct PS_INPUT { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
        float4 main(PS_INPUT input) : SV_TARGET
        {
            float4 fill = fillTexture.Sample(Sampler, input.uv);
            float4 key = keyTexture.Sample(Sampler, input.uv);
            float4 bg = bgTexture.Sample(Sampler, input.uv);
            float alpha = key.r;
            float4 finalColor;
            finalColor.rgb = fill.rgb * alpha + bg.rgb * (1.0f - alpha);
            finalColor.a = max(fill.a * alpha, bg.a);
            return finalColor;
        }
    )";

    inline const char* transitionPS = R"(
        Texture2D textureA : register(t0);
        Texture2D textureB : register(t1);
        SamplerState Sampler : register(s0);
        cbuffer TransitionBuffer : register(b0)
        {
            float progress;
            uint type;
        };
        struct PS_INPUT { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
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
    )";

    inline const char* dskPS = R"(
        Texture2D bgTexture : register(t0);
        Texture2D dskTexture : register(t1);
        SamplerState Sampler : register(s0);
        cbuffer DSKBuffer : register(b0)
        {
            float opacity;
        };
        struct PS_INPUT { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
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
    )";
}

class GPUCompositor {
public:
    GPUCompositor() noexcept = default;

    HRESULT initialize(ID3D11Device* device, ID3D11DeviceContext* context) noexcept {
        if (!device || !context) return E_INVALIDARG;
        d3dDevice = device;
        d3dContext = context;

        ComPtr<ID3DBlob> blob;
        HRESULT hr;

        // 1. Compile Shaders
        hr = compileShaderHelper(Shaders::quadVS, "main", "vs_4_0", blob.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;
        hr = d3dDevice->CreateVertexShader(blob->GetBufferPointer(), blob->GetBufferSize(), nullptr, quadVS.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;

        D3D11_INPUT_ELEMENT_DESC layoutDesc[] = {
            { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0 },
            { "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0 }
        };
        hr = d3dDevice->CreateInputLayout(layoutDesc, 2, blob->GetBufferPointer(), blob->GetBufferSize(), quadInputLayout.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;

        auto compilePS = [this](const char* src, ID3D11PixelShader** ps) -> HRESULT {
            ComPtr<ID3DBlob> b;
            HRESULT h = compileShaderHelper(src, "main", "ps_4_0", b.GetAddressOf());
            if (FAILED(h)) return h;
            return d3dDevice->CreatePixelShader(b->GetBufferPointer(), b->GetBufferSize(), nullptr, ps);
        };

        hr = compilePS(Shaders::procAmpPS, procAmpPS.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;
        hr = compilePS(Shaders::chromaKeyPS, chromaKeyPS.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;
        hr = compilePS(Shaders::upstreamKeyerPS, upstreamKeyerPS.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;
        hr = compilePS(Shaders::fillKeyBlendPS, fillKeyBlendPS.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;
        hr = compilePS(Shaders::transitionPS, transitionPS.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;
        hr = compilePS(Shaders::dskPS, dskPS.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;

        // 2. Create Constant Buffers
        auto createCb = [this](UINT size, ID3D11Buffer** cb) -> HRESULT {
            D3D11_BUFFER_DESC desc = {};
            desc.Usage = D3D11_USAGE_DYNAMIC;
            desc.ByteWidth = size;
            desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
            desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
            return d3dDevice->CreateBuffer(&desc, nullptr, cb);
        };

        hr = createCb(sizeof(ProcAmpBuffer), procAmpCb.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;
        hr = createCb(sizeof(ChromaKeyBuffer), chromaKeyCb.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;
        hr = createCb(sizeof(UpstreamKeyerBuffer), upstreamKeyerCb.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;
        hr = createCb(sizeof(TransitionBuffer), transitionCb.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;
        hr = createCb(sizeof(DSKBuffer), dskCb.ReleaseAndGetAddressOf());
        if (FAILED(hr)) return hr;

        // 3. Create full-screen quad vertex buffer
        struct Vertex {
            DirectX::XMFLOAT3 pos;
            DirectX::XMFLOAT2 uv;
        };
        Vertex vertices[] = {
            { DirectX::XMFLOAT3(-1.0f,  1.0f, 0.0f), DirectX::XMFLOAT2(0.0f, 0.0f) },
            { DirectX::XMFLOAT3( 1.0f,  1.0f, 0.0f), DirectX::XMFLOAT2(1.0f, 0.0f) },
            { DirectX::XMFLOAT3(-1.0f, -1.0f, 0.0f), DirectX::XMFLOAT2(0.0f, 1.0f) },
            { DirectX::XMFLOAT3( 1.0f, -1.0f, 0.0f), DirectX::XMFLOAT2(1.0f, 1.0f) }
        };

        D3D11_BUFFER_DESC vbDesc = {};
        vbDesc.Usage = D3D11_USAGE_DEFAULT;
        vbDesc.ByteWidth = sizeof(vertices);
        vbDesc.BindFlags = D3D11_BIND_VERTEX_BUFFER;

        D3D11_SUBRESOURCE_DATA subData = {};
        subData.pSysMem = vertices;
        hr = d3dDevice->CreateBuffer(&vbDesc, &subData, quadVB.ReleaseAndGetAddressOf());
        return hr;
    }

    HRESULT compileShaderHelper(const char* source, const char* entryPoint, const char* target, ID3DBlob** blob) {
        ComPtr<ID3DBlob> errorBlob;
        HRESULT hr = D3DCompile(source, strlen(source), nullptr, nullptr, nullptr, entryPoint, target, 0, 0, blob, &errorBlob);
        if (FAILED(hr) && errorBlob) {
            OutputDebugStringA(static_cast<const char*>(errorBlob->GetBufferPointer()));
        }
        return hr;
    }

    void REALTIME_SAFE uploadInputTexture(size_t index, void* textureHandle) noexcept {
        if (index >= 4) return;
        inputTextures[index] = static_cast<ID3D11ShaderResourceView*>(textureHandle);
    }

    void REALTIME_SAFE process() noexcept {
        if (!d3dContext) return;

        // Basic render process:
        // 1. Set generic state
        struct Vertex {
            DirectX::XMFLOAT3 pos;
            DirectX::XMFLOAT2 uv;
        };
        UINT stride = sizeof(Vertex);
        UINT offset = 0;
        d3dContext->IASetVertexBuffers(0, 1, quadVB.GetAddressOf(), &stride, &offset);
        d3dContext->IASetInputLayout(quadInputLayout.Get());
        d3dContext->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);
        d3dContext->VSSetShader(quadVS.Get(), nullptr, 0);

        // 2. Perform composition passes (placeholders for now)
        // In a real implementation, we'd render to offscreen targets
    }

    ID3D11ShaderResourceView* inputTextures[4] = {nullptr, nullptr, nullptr, nullptr};

    ComPtr<ID3D11Device> d3dDevice;
    ComPtr<ID3D11DeviceContext> d3dContext;

    ComPtr<ID3D11Buffer> procAmpCb;
    ComPtr<ID3D11Buffer> chromaKeyCb;
    ComPtr<ID3D11Buffer> upstreamKeyerCb;
    ComPtr<ID3D11Buffer> transitionCb;
    ComPtr<ID3D11Buffer> dskCb;

    ComPtr<ID3D11VertexShader> quadVS;
    ComPtr<ID3D11PixelShader> procAmpPS;
    ComPtr<ID3D11PixelShader> chromaKeyPS;
    ComPtr<ID3D11PixelShader> upstreamKeyerPS;
    ComPtr<ID3D11PixelShader> fillKeyBlendPS;
    ComPtr<ID3D11PixelShader> transitionPS;
    ComPtr<ID3D11PixelShader> dskPS;

    ComPtr<ID3D11InputLayout> quadInputLayout;
    ComPtr<ID3D11Buffer> quadVB;
};
