#include <gtest/gtest.h>
#include "AudioEngineCore.h"
#include "WASAPIDeviceWorker.h"
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <chrono>
#include <vector>
#include <iostream>

class AudioEngineTest : public ::testing::Test {
protected:
    void SetUp() override {
        // Clear summing maps
        inputBuffer.fill(1.0f);
        outputBuffer.fill(0.0f);
        sourceChannels[0] = inputBuffer.data();
        destChannels[0] = outputBuffer.data();
    }

    std::array<float, 64> inputBuffer{};
    std::array<float, 64> outputBuffer{};
    std::array<const float*, 1> sourceChannels{};
    std::array<float*, 1> destChannels{};
};

// 1. Verify mathematical correctness of the Sparse Routing Matrix
TEST_F(AudioEngineTest, VerifySparseMatrixMath) {
    SparseRoutingMatrix matrix;
    
    // Add routing node: Channel 0 -> Destination 0 with -6.02dB (0.5 linear fader gain)
    matrix.setRoute(0, 0, 0.5f, TapPoint::PostFader);

    std::span<const float*> sourceSpan(sourceChannels.data(), 1);
    std::span<float*> destSpan(destChannels.data(), 1);
    matrix.process(sourceSpan, destSpan, 64);

    // Assert mathematical gain factor matching within target float tolerance
    for (float sample : outputBuffer) {
        EXPECT_NEAR(sample, 0.5f, 1e-6f);
    }
}

// 2. Verify First-Order IIR Parameter Smoother transitions without digital pops
TEST_F(AudioEngineTest, VerifyParameterSmoothing) {
    ParameterSmoother smoother;
    smoother.reset(0.0f);
    smoother.setTarget(1.0f);

    std::array<float, 64> block{};
    block.fill(1.0f);

    smoother.processBlock(block.data(), block.size());

    // Fader should slowly glide upwards from 0.0f to 1.0f (not snap instantly)
    EXPECT_GT(block[0], 0.0f);
    EXPECT_LT(block[0], 0.5f);
    EXPECT_GT(block[63], block[0]); // Upward glide assertion
}

// 3. Verify AVSyncDelayLine calculation latency offsets
TEST_F(AudioEngineTest, VerifyAVSyncDelayLine) {
    AVSyncDelayLine delay;
    delay.setDelayMs(10.0f, 48000.0f); // 10ms at 48kHz = 480 samples delay

    // Circular check
    delay.reset();
    
    // We expect 480 samples of latency before seeing our input
    float inputSample = 1.0f;
    bool foundSignal = false;
    int latencyCounter = 0;
    
    for (int i = 0; i < 1000; ++i) {
        float out = delay.processSample(inputSample);
        if (out > 0.0f && !foundSignal) {
            foundSignal = true;
            latencyCounter = i;
        }
    }
    
    EXPECT_TRUE(foundSignal);
    EXPECT_EQ(latencyCounter, 480);
}

// 4. Verify Route Toggling and Gain in SparseRoutingMatrix (Step 4 of plan)
TEST_F(AudioEngineTest, VerifyRouteTogglingAndGain) {
    SparseRoutingMatrix matrix;
    matrix.setRoute(0, 0, 0.707f, TapPoint::PreFader);
    
    std::span<const float*> sourceSpan(sourceChannels.data(), 1);
    std::span<float*> destSpan(destChannels.data(), 1);
    matrix.process(sourceSpan, destSpan, 64);
    
    EXPECT_NEAR(outputBuffer[0], 0.707f, 1e-5f);
}

TEST_F(AudioEngineTest, WASAPIDeviceWorkerDefaultFormatQuery) {
    HRESULT coInitHr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    IMMDeviceEnumerator* enumerator = nullptr;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator), (void**)&enumerator
    );
    ASSERT_TRUE(SUCCEEDED(hr));
    IMMDevice* device = nullptr;
    hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
    if (FAILED(hr)) {
        enumerator->Release();
        if (coInitHr == S_OK || coInitHr == S_FALSE) CoUninitialize();
        GTEST_SKIP() << "No capture device available";
    }
    WASAPIDeviceWorker worker(device, WASAPIDeviceWorker::Mode::Capture);
    worker.start();
    WAVEFORMATEX* fmt = worker.getMixFormat();
    EXPECT_NE(fmt, nullptr);
    if (fmt) {
        EXPECT_GT(fmt->nSamplesPerSec, 0u);
    }
    worker.stop();
    device->Release();
    enumerator->Release();
    if (coInitHr == S_OK || coInitHr == S_FALSE) CoUninitialize();
}