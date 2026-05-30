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

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")

using Microsoft::WRL::ComPtr;

// 16-byte aligned structures for HLSL constant buffers

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

class GPUCompositor {
public:
    GPUCompositor() noexcept {
        const char* dskPSSource = 
            "Texture2D bgTexture : register(t0);\n"
            "Texture2D dskTexture : register(t1);\n"
            "SamplerState Sampler : register(s0);\n"
            "cbuffer DSKBuffer : register(b0) {\n"
            "    float opacity;\n"
            "    float3 padding;\n"
            "};\n"
            "struct PS_INPUT { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };\n"
            "float4 main(PS_INPUT input) : SV_TARGET {\n"
            "    float4 bg = bgTexture.Sample(Sampler, input.uv);\n"
            "    float4 overlay = dskTexture.Sample(Sampler, input.uv);\n"
            "    float alpha = overlay.a * opacity;\n"
            "    float4 finalColor;\n"
            "    finalColor.rgb = lerp(bg.rgb, overlay.rgb, alpha);\n"
            "    finalColor.a = max(bg.a, alpha);\n"
            "    return finalColor;\n"
            "}\n";

        ComPtr<ID3DBlob> dskBlob;
        if (d3dDevice) {
            if (SUCCEEDED(compileShaderHelper(dskPSSource, "main", "ps_4_0", dskBlob.GetAddressOf()))) {
                d3dDevice->CreatePixelShader(dskBlob->GetBufferPointer(), dskBlob->GetBufferSize(), nullptr, dskPS.GetAddressOf());
            }
        }
    }

    HRESULT compileShaderHelper(const char* source, const char* entryPoint, const char* target, ID3DBlob** blob) {
        ComPtr<ID3DBlob> errorBlob;
        HRESULT hr = D3DCompile(source, strlen(source), nullptr, nullptr, nullptr, entryPoint, target, 0, 0, blob, &errorBlob);
        if (FAILED(hr) && errorBlob) {
            OutputDebugStringA(static_cast<const char*>(errorBlob->GetBufferPointer()));
        }
        return hr;
    }

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
