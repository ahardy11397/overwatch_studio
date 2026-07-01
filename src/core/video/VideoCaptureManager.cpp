#include "VideoCaptureManager.h"

VideoCaptureManager::VideoCaptureManager() noexcept = default;
VideoCaptureManager::~VideoCaptureManager() = default;

bool VideoCaptureManager::initialize(ID3D11Device* device) noexcept {
    m_device = device;
    return true;
}

bool VideoCaptureManager::addStreamSource(int channelIdx, const std::string& url) noexcept {
    if (channelIdx < 0 || channelIdx >= static_cast<int>(MaxChannels)) return false;
    auto source = std::make_unique<FFmpegCaptureSource>();
    if (!source->open(url, m_device)) return false;
    m_ffmpegSources[channelIdx] = std::move(source);
    return true;
}

void VideoCaptureManager::removeSource(int channelIdx) noexcept {
    if (channelIdx < 0 || channelIdx >= static_cast<int>(MaxChannels)) return;
    if (m_ffmpegSources[channelIdx]) {
        m_ffmpegSources[channelIdx]->stop();
        m_ffmpegSources[channelIdx].reset();
    }
}

void VideoCaptureManager::startAll() noexcept {
    for (int i = 0; i < static_cast<int>(MaxChannels); ++i) {
        if (m_ffmpegSources[i]) {
            m_ffmpegSources[i]->start([this, i](ID3D11Texture2D* tex, uint64_t pts) {
                m_sync.pushFrame(i, tex, pts);
            });
        }
    }
}

void VideoCaptureManager::stopAll() noexcept {
    for (int i = 0; i < static_cast<int>(MaxChannels); ++i) {
        if (m_ffmpegSources[i]) m_ffmpegSources[i]->stop();
    }
}