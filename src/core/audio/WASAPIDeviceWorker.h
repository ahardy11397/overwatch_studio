#pragma once
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <thread>
#include <atomic>
#include <vector>
#include <mutex>
#include <string>

class WASAPIDeviceWorker {
public:
    enum class Mode { Capture, Render };

    WASAPIDeviceWorker(IMMDevice* device, Mode mode) noexcept;
    ~WASAPIDeviceWorker();

    bool start() noexcept;
    void stop() noexcept;

    // For Capture: Pulls latest mono/stereo samples, converts format to float
    void readCapturedSamples(int deviceChannelIdx, float* destBuffer, size_t numSamples) noexcept;
    void readCapturedSamples(float* destBuffer, size_t numSamples) noexcept;

    // For Render: Pushes mono/stereo float samples, converts to device format
    void writeRenderSamples(const float* srcBuffer, size_t numSamples) noexcept;

    bool isRunning() const noexcept { return m_running.load(std::memory_order_relaxed); }
    std::wstring getDeviceName() const noexcept { return m_deviceName; }
    int getChannelCount() const noexcept;
    size_t getBufferedSampleCount() const noexcept;

    WAVEFORMATEX* getMixFormat() const noexcept { return m_mixFormat; }
    bool isExclusive() const noexcept { return m_exclusive; }
    void setExclusive(bool exclusive) noexcept { m_exclusive = exclusive; }

private:
    void runLoop() noexcept;

    IMMDevice* m_device;
    Mode m_mode;
    std::wstring m_deviceName;
    std::atomic<bool> m_running{false};
    std::thread m_workerThread;

    IAudioClient* m_audioClient = nullptr;
    IAudioCaptureClient* m_captureClient = nullptr;
    IAudioRenderClient* m_renderClient = nullptr;

    WAVEFORMATEX* m_mixFormat = nullptr;
    UINT32 m_bufferFrameCount = 0;

    // Thread-safe ring buffers for decoupling I/O threads
    std::vector<std::vector<float>> m_channelRingBuffers;
    size_t m_ringWritePos = 0;
    std::vector<size_t> m_ringReadPos;
    size_t m_ringBufferSize = 16384;
    bool m_exclusive = false;
    mutable std::mutex m_ringMutex;
};
