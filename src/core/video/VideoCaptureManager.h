#pragma once

#include "VideoSyncManager.h"
#include "WindowsGraphicsCapture.h"
#include "FFmpegCaptureSource.h"
#include <array>
#include <memory>
#include <string>

struct ID3D11Device;

class VideoCaptureManager {
public:
    VideoCaptureManager() noexcept;
    ~VideoCaptureManager();

    bool initialize(ID3D11Device* device) noexcept;

    bool addWindowSource(int channelIdx, void* windowHandle) noexcept;
    bool addMonitorSource(int channelIdx, void* monitorHandle) noexcept;
    bool addStreamSource(int channelIdx, const std::string& url) noexcept;
    void removeSource(int channelIdx) noexcept;

    void startAll() noexcept;
    void stopAll() noexcept;

    VideoSyncManager& getSyncManager() noexcept { return m_sync; }

private:
    ID3D11Device* m_device = nullptr;
    VideoSyncManager m_sync;
    using WGC = overwatch::video::WindowsGraphicsCapture;
    std::array<std::unique_ptr<WGC>, VideoSyncManager::InputChannels> m_wgcSources;
    std::array<std::unique_ptr<FFmpegCaptureSource>, VideoSyncManager::InputChannels> m_ffmpegSources;
};
