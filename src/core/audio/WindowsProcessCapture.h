#pragma once
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <thread>
#include <atomic>
#include "../control/SPSCQueue.h"

/**
 * @class WindowsProcessCapture
 * @brief High-performance loopback audio capturer that isolates individual process audio using IAudioClient3/AUDIOCAPTURE_MONITOR
 */
class WindowsProcessCapture {
public:
    WindowsProcessCapture() noexcept : running(false), fallbackActive(false) {}
    ~WindowsProcessCapture() { stop(); }

    bool start(DWORD processId, SPSCQueue<float>& outputQueue) noexcept;
    void stop() noexcept;

    bool isRunning() const noexcept { return running.load(std::memory_order_relaxed); }
    bool isFallbackActive() const noexcept { return fallbackActive.load(std::memory_order_relaxed); }

private:
    void captureLoop(DWORD pid, SPSCQueue<float>& queue) noexcept;
    std::thread captureThread;
    std::atomic<bool> running;
    std::atomic<bool> fallbackActive;
};
