#include "WindowsGraphicsCapture.h"
#include "../control/RealtimeLogger.h"

// ponytail: WGC stub — C++/WinRT COM interop needs SDK component install
// Interactive WGC with C++/WinRT requires the Windows SDK C++/WinRT component.
// The FFmpegCaptureSource path (RTSP/NDI/file) works without it.
// To enable: install C++/WinRT via Visual Studio Installer → Windows SDK → C++/WinRT

namespace overwatch::video {

struct WindowsGraphicsCapture::Impl {
    // No-op stub
};

WindowsGraphicsCapture::WindowsGraphicsCapture(ID3D11Device* device)
    : m_impl(nullptr) {
    RealtimeLogger::getInstance().log("WGC: C++/WinRT not available — FFmpeg path active");
}

WindowsGraphicsCapture::~WindowsGraphicsCapture() = default;

bool WindowsGraphicsCapture::startWindowCapture(HWND, FrameCallback) {
    return false;
}

bool WindowsGraphicsCapture::startMonitorCapture(HMONITOR, FrameCallback) {
    return false;
}

void WindowsGraphicsCapture::stop() {}

bool WindowsGraphicsCapture::isActive() const { return false; }

} // namespace overwatch::video