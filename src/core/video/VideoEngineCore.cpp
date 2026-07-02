#include "VideoEngineCore.h"
#include "VideoSyncManager.h"
#include <chrono>
#include <d3d11.h>

std::atomic<ID3D11Texture2D*> g_videoOutputTexture{nullptr};

void VideoEngineCore::renderLoop() {
    const auto frameDuration = std::chrono::microseconds(16666);
    uint64_t masterPts = 0;
    bool rtvInitialized = false;

    while (isRunning.load(std::memory_order_relaxed)) {
        auto start = std::chrono::steady_clock::now();

        // 0. Lazy-init render target on first frame
        if (!rtvInitialized && syncManager) {
            // Use a default 1920x1080 output size
            if (SUCCEEDED(compositor.createOutputRenderTarget(1920, 1080))) {
                rtvInitialized = true;
            }
        }

        // 1. Acquire genlock frames for all 4 input channels
        if (syncManager) {
            for (size_t i = 0; i < 4; ++i) {
                void* texHandle = syncManager->acquireGenlockFrame(i, masterPts);
                if (texHandle) {
                    compositor.uploadInputTexture(i, texHandle);
                }
            }
        }

        // 2. Run the compositor — renders input[0] through proc amp into output RTV
        compositor.process();

        // 3. Publish output texture for VideoCanvasMock to read
        ID3D11Texture2D* outputTex = compositor.getOutputTexture();
        setLatestOutput(outputTex);
        g_videoOutputTexture.store(outputTex, std::memory_order_release);

        // 4. Increment master clock (16.66ms per frame at 60Hz)
        masterPts += 16666;

        auto end = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        if (elapsed < frameDuration) {
            std::this_thread::sleep_for(frameDuration - elapsed);
        }
    }
}
