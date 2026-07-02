#include "VideoCaptureManager.h"

VideoCaptureManager::VideoCaptureManager() noexcept = default;
VideoCaptureManager::~VideoCaptureManager() = default;

bool VideoCaptureManager::initialize(ID3D11Device* device) noexcept {
    m_device = device;
    return true;
}

bool VideoCaptureManager::addWindowSource(int channelIdx, void* windowHandle) noexcept {
    if (channelIdx < 0 || channelIdx >= VideoSyncManager::InputChannels) return false;
    auto source = std::make_unique<WGC>(m_device);
    // WGC needs actual HWND — stored and started in startAll
    m_wgcSources[channelIdx] = std::move(source);
    return true;
}

bool VideoCaptureManager::addMonitorSource(int channelIdx, void* monitorHandle) noexcept {
    if (channelIdx < 0 || channelIdx >= VideoSyncManager::InputChannels) return false;
    auto source = std::make_unique<WGC>(m_device);
    m_wgcSources[channelIdx] = std::move(source);
    return true;
}

bool VideoCaptureManager::addStreamSource(int channelIdx, const std::string& url) noexcept {
    if (channelIdx < 0 || channelIdx >= VideoSyncManager::InputChannels) return false;
    auto source = std::make_unique<FFmpegCaptureSource>();
    if (!source->open(url, m_device)) return false;
    m_ffmpegSources[channelIdx] = std::move(source);
    return true;
}

void VideoCaptureManager::removeSource(int channelIdx) noexcept {
    if (channelIdx < 0 || channelIdx >= VideoSyncManager::InputChannels) return;
    if (m_wgcSources[channelIdx]) {
        m_wgcSources[channelIdx]->stop();
        m_wgcSources[channelIdx].reset();
    }
    if (m_ffmpegSources[channelIdx]) {
        m_ffmpegSources[channelIdx]->stop();
        m_ffmpegSources[channelIdx].reset();
    }
}

void VideoCaptureManager::startAll() noexcept {
    for (int i = 0; i < VideoSyncManager::InputChannels; ++i) {
        if (m_wgcSources[i]) {
            m_wgcSources[i]->startWindowCapture(nullptr, [this, i](ID3D11Texture2D* tex, uint64_t pts) {
                m_sync.pushFrame(i, static_cast<void*>(tex), pts);
            });
        }
        if (m_ffmpegSources[i]) {
            m_ffmpegSources[i]->start([this, i](ID3D11Texture2D* tex, uint64_t pts) {
                m_sync.pushFrame(i, static_cast<void*>(tex), pts);
            });
        }
    }
}

void VideoCaptureManager::stopAll() noexcept {
    for (int i = 0; i < VideoSyncManager::InputChannels; ++i) {
        if (m_wgcSources[i]) m_wgcSources[i]->stop();
        if (m_ffmpegSources[i]) m_ffmpegSources[i]->stop();
    }
}
