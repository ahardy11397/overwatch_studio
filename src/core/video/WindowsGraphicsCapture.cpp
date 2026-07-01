#include "WindowsGraphicsCapture.h"
#include "../control/RealtimeLogger.h"

// C++/WinRT SDK component not available on this build machine.
// WGC capture is compiled as a stub that logs and returns false.
// To enable: install Windows SDK with C++/WinRT support, then rebuild.
//
// Upgrade path:
//   1. Open "Visual Studio Installer" → Modify → check "C++/WinRT" under
//      "Windows SDK" components, or install via standalone Windows SDK installer.
//   2. The /ZW compiler flag and windowsapp/runtimeobject linkage handle the rest.

namespace overwatch::video {

struct WindowsGraphicsCapture::Impl {
    // No-op stub — C++/WinRT SDK not available
};

WindowsGraphicsCapture::WindowsGraphicsCapture(ID3D11Device* device)
    : m_impl(nullptr)
{
    RealtimeLogger::getInstance().log(
        "WGC: C++/WinRT not available, capture disabled. "
        "Install Windows SDK with C++/WinRT support to enable.");
}

WindowsGraphicsCapture::~WindowsGraphicsCapture() = default;

bool WindowsGraphicsCapture::startWindowCapture(HWND /*hwnd*/, FrameCallback /*callback*/) {
    RealtimeLogger::getInstance().log("WGC: startWindowCapture — C++/WinRT not available.");
    return false;
}

bool WindowsGraphicsCapture::startMonitorCapture(HMONITOR /*hmonitor*/, FrameCallback /*callback*/) {
    RealtimeLogger::getInstance().log("WGC: startMonitorCapture — C++/WinRT not available.");
    return false;
}

void WindowsGraphicsCapture::stop() {
    // no-op stub
}

bool WindowsGraphicsCapture::isActive() const {
    return false;
}

} // namespace overwatch::video