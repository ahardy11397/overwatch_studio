#pragma once

#include "VideoSyncManager.h"
#include "FFmpegCaptureSource.h"
#include "WindowsGraphicsCapture.h"

#include <array>
#include <memory>
#include <string>
#include <optional>

struct ID3D11Device;

class VideoCaptureManager {
public:
    VideoCaptureManager() noexcept;
    ~VideoCaptureManager();

    bool initialize(ID3D11Device* device) noexcept;

    bool addStreamSource(int channelIdx, const std::string& url) noexcept;
    bool addWindowSource(int channelIdx, HWND hwnd) noexcept;
    bool addMonitorSource(int channelIdx, HMONITOR hmonitor) noexcept;
    void removeSource(int channelIdx) noexcept;

    void startAll() noexcept;
    void stopAll() noexcept;

    VideoSyncManager& getSyncManager() noexcept { return m_sync; }

private:
    void startWgcCapture(int channelIdx) noexcept;

    ID3D11Device* m_device = nullptr;
    VideoSyncManager m_sync;

    static constexpr size_t MaxChannels = VideoSyncManager::InputChannels;
    std::array<std::unique_ptr<FFmpegCaptureSource>, MaxChannels> m_ffmpegSources;
    std::array<std::unique_ptr<overwatch::video::WindowsGraphicsCapture>, MaxChannels> m_wgcSources;
    std::array<std::optional<HWND>, MaxChannels> m_wgcWindows;
    std::array<std::optional<HMONITOR>, MaxChannels> m_wgcMonitors;
};