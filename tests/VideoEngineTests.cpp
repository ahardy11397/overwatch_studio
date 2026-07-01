#include <gtest/gtest.h>
#include "../src/core/video/VideoSyncManager.h"
#include "../src/core/video/GPUCompositor.h"
#include "../src/core/video/VideoEngineCore.h"

class VideoEngineTest : public ::testing::Test {
protected:
    void SetUp() override {}
    void TearDown() override {}
};

TEST_F(VideoEngineTest, SyncManagerFractionalQueueLockFree) {
    VideoSyncManager sync;
    
    // Simulate push from camera 0 at PTS 100
    void* texHandle1 = reinterpret_cast<void*>(0x1000);
    sync.pushFrame(0, texHandle1, 100);
    
    // Simulate push from camera 0 at PTS 116
    void* texHandle2 = reinterpret_cast<void*>(0x1001);
    sync.pushFrame(0, texHandle2, 116);
    
    // Master PTS is 115, it should pick the closest, which is 116
    void* best = sync.acquireGenlockFrame(0, 115);
    EXPECT_EQ(best, texHandle2);
}

TEST_F(VideoEngineTest, CompositorAlignmentChecks) {
    // Verify 16-byte alignment of structures to prevent D3D11 hard faults
    EXPECT_EQ(sizeof(ProcAmpBuffer) % 16, 0);
    EXPECT_EQ(sizeof(ChromaKeyBuffer) % 16, 0);
    EXPECT_EQ(sizeof(UpstreamKeyerBuffer) % 16, 0);
}

TEST_F(VideoEngineTest, EngineCoreFTBState) {
    VideoSyncManager sync;
    EXPECT_EQ(VideoSyncManager::InputChannels, 4);
    EXPECT_EQ(VideoSyncManager::RingBufferSize, 3);
}

TEST_F(VideoEngineTest, VerifyShaderCompilation) {
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    D3D_FEATURE_LEVEL featureLevel;
    
    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_NULL,
        nullptr,
        0,
        nullptr,
        0,
        D3D11_SDK_VERSION,
        device.GetAddressOf(),
        &featureLevel,
        context.GetAddressOf()
    );
    
    ASSERT_TRUE(SUCCEEDED(hr));
    ASSERT_NE(device, nullptr);
    ASSERT_NE(context, nullptr);
    
    GPUCompositor compositor;
    hr = compositor.initialize(device.Get(), context.Get());
    EXPECT_TRUE(SUCCEEDED(hr));
    
    EXPECT_NE(compositor.quadVS, nullptr);
    EXPECT_NE(compositor.procAmpPS, nullptr);
    EXPECT_NE(compositor.chromaKeyPS, nullptr);
    EXPECT_NE(compositor.upstreamKeyerPS, nullptr);
    EXPECT_NE(compositor.fillKeyBlendPS, nullptr);
    EXPECT_NE(compositor.transitionPS, nullptr);
    EXPECT_NE(compositor.dskPS, nullptr);
    EXPECT_NE(compositor.quadVB, nullptr);
    EXPECT_NE(compositor.quadInputLayout, nullptr);
}

TEST_F(VideoEngineTest, EngineCoreRenderLoop) {
    VideoSyncManager sync;
    VideoEngineCore engine;
    engine.setSyncManager(&sync);

    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    D3D_FEATURE_LEVEL featureLevel;

    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_NULL,
        nullptr,
        0,
        nullptr,
        0,
        D3D11_SDK_VERSION,
        device.GetAddressOf(),
        &featureLevel,
        context.GetAddressOf()
    );

    ASSERT_TRUE(SUCCEEDED(hr));

    hr = engine.getCompositor().initialize(device.Get(), context.Get());
    ASSERT_TRUE(SUCCEEDED(hr));

    // Push a mock texture
    void* mockTex = reinterpret_cast<void*>(0x1234);
    sync.pushFrame(0, mockTex, 0);

    engine.start();
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    engine.stop();

    // If we reached here without crashing, the render loop started and stopped correctly
    EXPECT_EQ(engine.getCompositor().inputTextures[0], mockTex);
}

