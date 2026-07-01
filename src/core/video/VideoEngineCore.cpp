#include "VideoEngineCore.h"
#include "VideoSyncManager.h"
#include <chrono>

std::atomic<ID3D11Texture2D*> g_videoOutputTexture{nullptr};

void VideoEngineCore::renderLoop() {
    // Target 60 FPS (16.666ms per frame)
    const auto frameDuration = std::chrono::microseconds(16666);
    uint64_t masterPts = 0;

    while (isRunning.load(std::memory_order_relaxed)) {
        auto start = std::chrono::steady_clock::now();

        // 1. Acquire genlock frames for all 4 input channels
        if (syncManager) {
            for (size_t i = 0; i < 4; ++i) {
                void* texHandle = syncManager->acquireGenlockFrame(i, masterPts);
                if (texHandle) {
                    compositor.uploadInputTexture(i, texHandle);
                }
            }
        }

        // 2. Run the compositor
        compositor.process();

        // 3. Increment master clock (16.66ms per frame at 60Hz)
        masterPts += 16666;

        auto end = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
        if (elapsed < frameDuration) {
            std::this_thread::sleep_for(frameDuration - elapsed);
        }
    }
}
