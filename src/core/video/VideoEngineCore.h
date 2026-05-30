#pragma once

#include "GPUCompositor.h"
#include <atomic>
#include <chrono>
#include <thread>

class VideoEngineCore {
public:
    VideoEngineCore() noexcept {
        isRunning.store(false);
        transitionProgress.store(0.0f);
        transitionType.store(0);
        dskActive.store(false);
        dskOpacity.store(0.0f);
    }

    ~VideoEngineCore() {
        stop();
    }

    void start() {
        if (!isRunning.load()) {
            isRunning.store(true);
            renderThread = std::thread(&VideoEngineCore::renderLoop, this);
        }
    }

    void stop() {
        if (isRunning.load()) {
            isRunning.store(false);
            if (renderThread.joinable()) {
                renderThread.join();
            }
        }
    }

    GPUCompositor& getCompositor() noexcept { return compositor; }

    float getTransitionProgress() const noexcept { return transitionProgress.load(std::memory_order_relaxed); }
    uint32_t getTransitionType() const noexcept { return transitionType.load(std::memory_order_relaxed); }
    bool getDSKActive() const noexcept { return dskActive.load(std::memory_order_relaxed); }
    float getDSKOpacity() const noexcept { return dskOpacity.load(std::memory_order_relaxed); }

private:
    void renderSweep() {
        // Mock rendering sweep
    }

    void renderLoop() {
        // Target 60 FPS (16.666ms per frame)
        const auto frameDuration = std::chrono::microseconds(16666);

        while (isRunning.load(std::memory_order_relaxed)) {
            auto start = std::chrono::steady_clock::now();

            renderSweep();

            auto end = std::chrono::steady_clock::now();
            auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
            if (elapsed < frameDuration) {
                std::this_thread::sleep_for(frameDuration - elapsed);
            }
        }
    }

    GPUCompositor compositor;
    std::atomic<float> transitionProgress{0.0f};
    std::atomic<uint32_t> transitionType{0};
    std::atomic<bool> dskActive{false};
    std::atomic<float> dskOpacity{0.0f};
    std::atomic<bool> isRunning{false};
    std::thread renderThread;
};
