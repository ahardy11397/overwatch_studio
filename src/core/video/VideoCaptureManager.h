#pragma once

#include "VideoSyncManager.h"
#include "FFmpegCaptureSource.h"

// ponytail: WGC deferred — add WindowsGraphicsCapture.h include and m_wgcSources member when WinRT interop is fixed
#include <array>
#include <memory>
#include <string>

struct ID3D11Device;

class VideoCaptureManager {
public:
    VideoCaptureManager() noexcept;
    ~VideoCaptureManager();

    bool initialize(ID3D11Device* device) noexcept;

    bool addStreamSource(int channelIdx, const std::string& url) noexcept;
    void removeSource(int channelIdx) noexcept;

    void startAll() noexcept;
    void stopAll() noexcept;

    VideoSyncManager& getSyncManager() noexcept { return m_sync; }

private:
    ID3D11Device* m_device = nullptr;
    VideoSyncManager m_sync;

    static constexpr size_t MaxChannels = VideoSyncManager::InputChannels;
    std::array<std::unique_ptr<FFmpegCaptureSource>, MaxChannels> m_ffmpegSources;
};