#pragma once

#include <windows.h>
#include <d3d11.h>
#include <functional>
#include <memory>
#include <string>
#include <cstdint>

namespace overwatch::video {

/**
 * @brief Manages Windows Graphics Capture (WGC) sessions for screen and window capture.
 *
 * Uses C++/WinRT to interface with Windows.Graphics.Capture APIs.
 * This class is designed to be used in a background thread or UI thread,
 * and reports frames via a callback.
 */
class WindowsGraphicsCapture {
public:
    using FrameCallback = std::function<void(ID3D11Texture2D* texture, uint64_t timestamp)>;

    explicit WindowsGraphicsCapture(ID3D11Device* device);
    ~WindowsGraphicsCapture();

    // Delete copy/move for safety with WinRT types in PIMPL
    WindowsGraphicsCapture(const WindowsGraphicsCapture&) = delete;
    WindowsGraphicsCapture& operator=(const WindowsGraphicsCapture&) = delete;
    WindowsGraphicsCapture(WindowsGraphicsCapture&&) noexcept = delete;
    WindowsGraphicsCapture& operator=(WindowsGraphicsCapture&&) noexcept = delete;

    /**
     * @brief Start capturing a window.
     * @param hwnd Handle to the window to capture.
     * @param callback Function to call when a new frame is available.
     * @return true if session started successfully.
     */
    bool startWindowCapture(HWND hwnd, FrameCallback callback);

    /**
     * @brief Start capturing a monitor.
     * @param hmonitor Handle to the monitor to capture.
     * @param callback Function to call when a new frame is available.
     * @return true if session started successfully.
     */
    bool startMonitorCapture(HMONITOR hmonitor, FrameCallback callback);

    /**
     * @brief Stop the current capture session.
     */
    void stop();

    /**
     * @brief Check if a capture session is currently active.
     */
    [[nodiscard]] bool isActive() const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace overwatch::video
