#pragma once

#include <atomic>
#include <chrono>
#include <thread>
#include <functional>
#include "RealtimeLogger.h"

/**
 * @class SystemWatchdog
 * @brief High-priority background system watchdog thread polling audio/video buffer jitter at 10ms intervals.
 */
class SystemWatchdog {
public:
    static SystemWatchdog& getInstance() {
        static SystemWatchdog instance;
        return instance;
    }

    void start() {
        if (running.exchange(true)) return;
        
        lastAudioCallbackTime.store(getCurrentTimeUs(), std::memory_order_relaxed);
        lastUIHeartbeatTime.store(getCurrentTimeUs(), std::memory_order_relaxed);

        watchdogThread = std::jthread([this](std::stop_token stopToken) {
            RealtimeLogger::getInstance().log("SystemWatchdog thread started.");
            while (!stopToken.stop_requested()) {
                uint64_t now = getCurrentTimeUs();
                int targetLevel = 0;
                
                // Check Audio thread (critical limit: 100ms to prevent false-triggers during offline simulation)
                uint64_t lastAudio = lastAudioCallbackTime.load(std::memory_order_relaxed);
                uint64_t audioDiffMs = 0;
                if (now > lastAudio) {
                    audioDiffMs = (now - lastAudio) / 1000;
                }
                
                if (audioDiffMs > 100) {
                    char buf[128];
                    
                    RealtimeLogger::getInstance().log(buf);
                    
                    if (targetLevel < 1) {
                        targetLevel = 1; // Level 1: Throttle UI framerate
                    }
                }

                if (targetLevel > 0) {
                    triggerResourceShedding(targetLevel);
                }

                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
        });
    }

    void stop() {
        if (!running.exchange(false)) return;
        watchdogThread.request_stop();
        if (watchdogThread.joinable()) {
            watchdogThread.join();
        }
    }

    void registerAudioCallback() noexcept {
        lastAudioCallbackTime.store(getCurrentTimeUs(), std::memory_order_relaxed);
    }

    void registerUIHeartbeat() noexcept {
        lastUIHeartbeatTime.store(getCurrentTimeUs(), std::memory_order_relaxed);
    }

    void setSheddingCallback(std::function<void(int)> callback) {
        sheddingCallback = callback;
    }

    ~SystemWatchdog() {
        stop();
    }

private:
    SystemWatchdog() : running(false) {}

    uint64_t getCurrentTimeUs() const noexcept {
        return std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now().time_since_epoch()
        ).count();
    }

    void triggerResourceShedding(int level) {
        if (sheddingCallback) {
            sheddingCallback(level);
        }
    }

    std::jthread watchdogThread;
    std::atomic<bool> running;
    std::atomic<uint64_t> lastAudioCallbackTime{0};
    std::atomic<uint64_t> lastUIHeartbeatTime{0};
    std::function<void(int)> sheddingCallback;
};
