#include "WindowsGraphicsCapture.h"

// WinRT Headers
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <windows.graphics.capture.interop.h>
#include <winrt/base.h>

// DirectX interop - Note: this is the standard header for the interop interface, NOT a WinRT one.
#include <windows.graphics.directx.direct3d11.interop.h>

#include <iostream>
#include <mutex>

namespace overwatch::video {

namespace {

// Helper to convert ID3D11Device to winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice
auto CreateDirect3DDevice(ID3D11Device* d3dDevice) {
    winrt::com_ptr<IDXGIDevice> dxgiDevice;
    winrt::check_hresult(d3dDevice->QueryInterface(IID_PPV_ARGS(dxgiDevice.put())));

    winrt::com_ptr<IInspectable> inspectable;
    winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.get(), inspectable.put()));

    return inspectable.as<winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice>();
}

} // namespace

struct WindowsGraphicsCapture::Impl {
    ID3D11Device* m_d3dDevice;
    winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice m_winrtDevice{ nullptr };
    winrt::Windows::Graphics::Capture::GraphicsCaptureItem m_captureItem{ nullptr };
    winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool m_framePool{ nullptr };
    winrt::Windows::Graphics::Capture::GraphicsCaptureSession m_session{ nullptr };
    winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool::FrameArrived_revoker m_frameArrivedRevoker;

    FrameCallback m_callback;
    std::mutex m_mutex;
    bool m_isActive = false;

    Impl(ID3D11Device* device) : m_d3dDevice(device) {
        // C++/WinRT must be initialized in the thread or globally.
        // Assuming thread is already initialized or this is main.
        m_winrtDevice = CreateDirect3DDevice(m_d3dDevice);
    }

    ~Impl() {
        stop();
    }

    bool startCapture(winrt::Windows::Graphics::Capture::GraphicsCaptureItem item, FrameCallback callback) {
        std::lock_guard lock(m_mutex);
        if (m_isActive) stop();

        m_captureItem = item;
        m_callback = std::move(callback);

        auto size = m_captureItem.Size();

        m_framePool = winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool::CreateFreeThreaded(
            m_winrtDevice,
            winrt::Windows::Graphics::DirectX::DirectXPixelFormat::B8G8R8A8UintNormalized,
            2,
            size
        );

        m_session = m_framePool.CreateCaptureSession(m_captureItem);

        m_frameArrivedRevoker = m_framePool.FrameArrived(winrt::auto_revoke, [this](auto const& sender, auto const&) {
            onFrameArrived(sender);
        });

        m_session.StartCapture();
        m_isActive = true;
        return true;
    }

    void stop() {
        std::lock_guard lock(m_mutex);
        if (!m_isActive) return;

        m_frameArrivedRevoker.revoke();
        if (m_session) {
            m_session.Close();
            m_session = nullptr;
        }
        if (m_framePool) {
            m_framePool.Close();
            m_framePool = nullptr;
        }
        m_captureItem = nullptr;
        m_isActive = false;
    }

    void onFrameArrived(winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool const& sender) {
        auto frame = sender.TryGetNextFrame();
        if (!frame) return;

        auto timestamp = frame.SystemRelativeTime().count();
        auto surface = frame.Surface();

        // Use the COM interface from the WinRT surface
        winrt::com_ptr<::IDirect3DDxgiInterfaceAccess> access;
        winrt::check_hresult(surface.as(IID_PPV_ARGS(access.put())));

        winrt::com_ptr<ID3D11Texture2D> texture;
        winrt::check_hresult(access->GetInterface(IID_PPV_ARGS(texture.put())));

        if (m_callback) {
            m_callback(texture.get(), static_cast<uint64_t>(timestamp));
        }
    }
};

WindowsGraphicsCapture::WindowsGraphicsCapture(ID3D11Device* device)
    : m_impl(std::make_unique<Impl>(device)) {}

WindowsGraphicsCapture::~WindowsGraphicsCapture() = default;

bool WindowsGraphicsCapture::startWindowCapture(HWND hwnd, FrameCallback callback) {
    auto activation_factory = winrt::get_activation_factory<winrt::Windows::Graphics::Capture::GraphicsCaptureItem>();
    auto interop_factory = activation_factory.as<IGraphicsCaptureItemInterop>();

    winrt::Windows::Graphics::Capture::GraphicsCaptureItem item{ nullptr };
    winrt::check_hresult(interop_factory->CreateForWindow(hwnd, winrt::guid_of<winrt::Windows::Graphics::Capture::GraphicsCaptureItem>(), winrt::put_abi(item)));

    return m_impl->startCapture(item, std::move(callback));
}

bool WindowsGraphicsCapture::startMonitorCapture(HMONITOR hmonitor, FrameCallback callback) {
    auto activation_factory = winrt::get_activation_factory<winrt::Windows::Graphics::Capture::GraphicsCaptureItem>();
    auto interop_factory = activation_factory.as<IGraphicsCaptureItemInterop>();

    winrt::Windows::Graphics::Capture::GraphicsCaptureItem item{ nullptr };
    winrt::check_hresult(interop_factory->CreateForMonitor(hmonitor, winrt::guid_of<winrt::Windows::Graphics::Capture::GraphicsCaptureItem>(), winrt::put_abi(item)));

    return m_impl->startCapture(item, std::move(callback));
}

void WindowsGraphicsCapture::stop() {
    m_impl->stop();
}

bool WindowsGraphicsCapture::isActive() const {
    return m_impl->m_isActive;
}

} // namespace overwatch::video
