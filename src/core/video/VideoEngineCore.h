#pragma once

#include "GPUCompositor.h"
#include <atomic>
#include <chrono>
#include <thread>

struct ID3D11Texture2D;

/// Global pointer to the latest composited frame — read by VideoCanvasMock each frame
extern std::atomic<ID3D11Texture2D*> g_videoOutputTexture;

class VideoSyncManager;

class VideoEngineCore {
public:
    VideoEngineCore() noexcept {
        isRunning.store(false);
        transitionProgress.store(0.0f);
        transitionType.store(0);
        dskActive.store(false);
        dskOpacity.store(0.0f);
        m_latestOutput = nullptr;
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

    void setSyncManager(VideoSyncManager* sync) noexcept { syncManager = sync; }
    HRESULT initialize(ID3D11Device* device, ID3D11DeviceContext* context) noexcept {
        return compositor.initialize(device, context);
    }
    GPUCompositor& getCompositor() noexcept { return compositor; }

    float getTransitionProgress() const noexcept { return transitionProgress.load(std::memory_order_relaxed); }
    uint32_t getTransitionType() const noexcept { return transitionType.load(std::memory_order_relaxed); }
    bool getDSKActive() const noexcept { return dskActive.load(std::memory_order_relaxed); }
    float getDSKOpacity() const noexcept { return dskOpacity.load(std::memory_order_relaxed); }

    /// Latest composited output texture — polled by VideoCanvasMock each frame
    ID3D11Texture2D* latestOutput() const noexcept { return m_latestOutput.load(std::memory_order_acquire); }
    void setLatestOutput(ID3D11Texture2D* tex) noexcept { m_latestOutput.store(tex, std::memory_order_release); }

private:
    void renderLoop();

    GPUCompositor compositor;
    VideoSyncManager* syncManager = nullptr;
    std::atomic<float> transitionProgress{0.0f};
    std::atomic<uint32_t> transitionType{0};
    std::atomic<bool> dskActive{false};
    std::atomic<float> dskOpacity{0.0f};
    std::atomic<bool> isRunning{false};
    std::atomic<ID3D11Texture2D*> m_latestOutput{nullptr};
    std::thread renderThread;
};
