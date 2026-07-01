#include "VideoCaptureManager.h"
#include "../control/RealtimeLogger.h"

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

bool VideoCaptureManager::addWindowSource(int channelIdx, HWND hwnd) noexcept {
    if (channelIdx < 0 || channelIdx >= static_cast<int>(MaxChannels)) return false;
    auto source = std::make_unique<overwatch::video::WindowsGraphicsCapture>(m_device);
    m_wgcSources[channelIdx] = std::move(source);
    m_wgcWindows[channelIdx] = hwnd;
    return true;
}

bool VideoCaptureManager::addMonitorSource(int channelIdx, HMONITOR hmonitor) noexcept {
    if (channelIdx < 0 || channelIdx >= static_cast<int>(MaxChannels)) return false;
    auto source = std::make_unique<overwatch::video::WindowsGraphicsCapture>(m_device);
    m_wgcSources[channelIdx] = std::move(source);
    m_wgcMonitors[channelIdx] = hmonitor;
    return true;
}

void VideoCaptureManager::removeSource(int channelIdx) noexcept {
    if (channelIdx < 0 || channelIdx >= static_cast<int>(MaxChannels)) return;
    if (m_ffmpegSources[channelIdx]) {
        m_ffmpegSources[channelIdx]->stop();
        m_ffmpegSources[channelIdx].reset();
    }
    if (m_wgcSources[channelIdx]) {
        m_wgcSources[channelIdx]->stop();
        m_wgcSources[channelIdx].reset();
    }
    m_wgcWindows[channelIdx].reset();
    m_wgcMonitors[channelIdx].reset();
}

void VideoCaptureManager::startWgcCapture(int channelIdx) noexcept {
    auto& src = m_wgcSources[channelIdx];
    if (!src) return;

    auto callback = [this, channelIdx](ID3D11Texture2D* tex, uint64_t pts) {
        m_sync.pushFrame(channelIdx, tex, pts);
    };

    if (m_wgcWindows[channelIdx].has_value()) {
        if (src->startWindowCapture(m_wgcWindows[channelIdx].value(), callback)) {
            RealtimeLogger::getInstance().log("WGC window capture started on channel " + std::to_string(channelIdx));
        } else {
            RealtimeLogger::getInstance().log("WGC window capture FAILED on channel " + std::to_string(channelIdx));
        }
    } else if (m_wgcMonitors[channelIdx].has_value()) {
        if (src->startMonitorCapture(m_wgcMonitors[channelIdx].value(), callback)) {
            RealtimeLogger::getInstance().log("WGC monitor capture started on channel " + std::to_string(channelIdx));
        } else {
            RealtimeLogger::getInstance().log("WGC monitor capture FAILED on channel " + std::to_string(channelIdx));
        }
    }
}

void VideoCaptureManager::startAll() noexcept {
    for (int i = 0; i < static_cast<int>(MaxChannels); ++i) {
        if (m_ffmpegSources[i]) {
            m_ffmpegSources[i]->start([this, i](ID3D11Texture2D* tex, uint64_t pts) {
                m_sync.pushFrame(i, tex, pts);
            });
        }
        if (m_wgcSources[i]) {
            startWgcCapture(i);
        }
    }
}

void VideoCaptureManager::stopAll() noexcept {
    for (int i = 0; i < static_cast<int>(MaxChannels); ++i) {
        if (m_ffmpegSources[i]) m_ffmpegSources[i]->stop();
        if (m_wgcSources[i]) m_wgcSources[i]->stop();
    }
}