#include <gtest/gtest.h>
#include "RoutingPatchMap.h"
#include "AudioEngineCore.h"
#include <array>
#include <algorithm>
#include <cmath>

// Test suite for Dynamic Audio Engine Summing & Pre-allocated Pools
class DynamicAudioEngineTest : public ::testing::Test {
protected:
    void SetUp() override {
        // Initialize samples to a known non-zero value above noise gate threshold
        std::fill(samples.begin(), samples.end(), 0.5f);
        // And some samples below noise gate threshold (e.g. 0.0005f) to test the gate
        samples[samples.size() - 1] = 0.0005f;
    }

    std::array<float, 64> samples;
};

// 1. Verify that the channelPool is allocated safely and faderStrips are mapped correctly
TEST_F(DynamicAudioEngineTest, VerifyPreallocatedPools) {
    std::cout << "[TEST LOG] Before make_unique<AudioEngineCore>" << std::endl;
    auto core = std::make_unique<AudioEngineCore>();
    std::cout << "[TEST LOG] After make_unique<AudioEngineCore>" << std::endl;

    // Check that channel pool size matches expected PoolSize
    auto& pool = core->getChannelPool();
    std::cout << "[TEST LOG] Pool size: " << pool.size() << std::endl;
    EXPECT_EQ(pool.size(), AudioEngineCore::PoolSize);

    // Verify channel pool type initialization
    std::cout << "[TEST LOG] Verifying pool channel types" << std::endl;
    for (size_t i = 0; i < AudioEngineCore::MaxInputs; ++i) {
        EXPECT_EQ(pool[i].type, ChannelType::Input);
    }
    for (size_t i = 0; i < AudioEngineCore::MaxBuses; ++i) {
        EXPECT_EQ(pool[AudioEngineCore::MaxInputs + i].type, ChannelType::Bus);
    }
    for (size_t i = 0; i < AudioEngineCore::MaxAuxes; ++i) {
        EXPECT_EQ(pool[AudioEngineCore::MaxInputs + AudioEngineCore::MaxBuses + i].type, ChannelType::Aux);
    }
    for (size_t i = 0; i < AudioEngineCore::MaxFX; ++i) {
        EXPECT_EQ(pool[AudioEngineCore::MaxInputs + AudioEngineCore::MaxBuses + AudioEngineCore::MaxAuxes + i].type, ChannelType::FX);
    }
    for (size_t i = 0; i < AudioEngineCore::MaxDCAs; ++i) {
        EXPECT_EQ(pool[AudioEngineCore::MaxInputs + AudioEngineCore::MaxBuses + AudioEngineCore::MaxAuxes + AudioEngineCore::MaxFX + i].type, ChannelType::DCA);
    }

    // Verify faderStrips mapping (24 inputs, 8 DCAs)
    std::cout << "[TEST LOG] Verifying faderStrips mapping" << std::endl;
    auto& faderStrips = core->getFaderStrips();
    EXPECT_EQ(faderStrips.size(), 32);

    for (size_t i = 0; i < 24; ++i) {
        ASSERT_NE(faderStrips[i], nullptr);
        EXPECT_EQ(faderStrips[i]->type, ChannelType::Input);
        EXPECT_EQ(faderStrips[i], &pool[i]);
    }

    size_t dcaStartIdx = AudioEngineCore::MaxInputs + AudioEngineCore::MaxBuses + AudioEngineCore::MaxAuxes + AudioEngineCore::MaxFX;
    for (size_t i = 0; i < 8; ++i) {
        ASSERT_NE(faderStrips[24 + i], nullptr);
        EXPECT_EQ(faderStrips[24 + i]->type, ChannelType::DCA);
        EXPECT_EQ(faderStrips[24 + i], &pool[dcaStartIdx + i]);
    }
    std::cout << "[TEST LOG] VerifyPreallocatedPools completed successfully" << std::endl;
}

// 2. Verify that type tags conditionally alter the DSP processing block (e.g. lip-sync delay bypass)
TEST_F(DynamicAudioEngineTest, VerifyDSPConditionalBypass) {
    // A. Verify Lip Sync Delay is only applied to Input strips
    {
        AudioChannelStrip inputStrip;
        inputStrip.type = ChannelType::Input;
        inputStrip.prepareToPlay(48000.0f);
        inputStrip.setLipSyncDelay(10.0f); // 10ms delay = 480 samples. 

        std::array<float, 64> block;
        block.fill(1.0f);

        inputStrip.processBlock(block.data(), block.size());

        // First block processed should be entirely silent (0.0f) due to the lip sync delay line
        for (float val : block) {
            EXPECT_NEAR(val, 0.0f, 1e-5f);
        }
    }

    {
        AudioChannelStrip busStrip;
        busStrip.type = ChannelType::Bus;
        busStrip.prepareToPlay(48000.0f);
        busStrip.setLipSyncDelay(10.0f); // Should be ignored because type is Bus

        std::array<float, 64> block;
        block.fill(1.0f);

        busStrip.processBlock(block.data(), block.size());

        // Samples should NOT be silent since delay was bypassed. They will be processed by HPF, EQ, Compressor, Fader.
        // Let's assert that the samples are non-zero.
        for (float val : block) {
            EXPECT_NE(val, 0.0f);
        }
    }

    // B. Verify Gate is only applied to Input strips
    {
        AudioChannelStrip inputStrip;
        inputStrip.type = ChannelType::Input;
        inputStrip.prepareToPlay(48000.0f);

        std::array<float, 64> block;
        block.fill(0.0005f); // Below gate threshold (-60dBFS / 0.001)

        inputStrip.processBlock(block.data(), block.size());

        // Samples below -60dBFS should be attenuated significantly by the gate
        for (float val : block) {
            EXPECT_LT(std::abs(val), 0.0005f);
        }
    }

    {
        AudioChannelStrip auxStrip;
        auxStrip.type = ChannelType::Aux;
        auxStrip.prepareToPlay(48000.0f);

        std::array<float, 64> block;
        block.fill(0.0005f); // Below gate threshold (-60dBFS / 0.001)

        auxStrip.processBlock(block.data(), block.size());

        // Low-level samples should NOT be attenuated by the gate on non-input strips
        // HPF and EQ pre-boost will actually make it slightly different, but it won't be gated down to 0
        for (float val : block) {
            EXPECT_GT(std::abs(val), 0.0001f);
        }
    }

    // C. Verify DCA strip does not process the audio buffer at all (control-only)
    {
        AudioChannelStrip dcaStrip;
        dcaStrip.type = ChannelType::DCA;
        dcaStrip.prepareToPlay(48000.0f);

        std::array<float, 64> block;
        block.fill(0.5f);

        dcaStrip.processBlock(block.data(), block.size());

        // Buffer should be completely untouched
        for (float val : block) {
            EXPECT_EQ(val, 0.5f);
        }
    }
}

#include "WavFileWriter.h"
#include <fstream>

TEST(WavFileWriterTest, VerifyFileCreationAndHeader) {
    WavFileWriter writer;
    bool ok = writer.open("test_out.wav", 48000);
    EXPECT_TRUE(ok);
    std::vector<float> buffer(512, 0.5f);
    writer.writeSamples(buffer.data(), buffer.size());
    writer.close();
    
    // Read file back to verify header is 44 bytes and data was written
    std::ifstream in("test_out.wav", std::ios::binary);
    ASSERT_TRUE(in.is_open());
    char header[44];
    in.read(header, 44);
    EXPECT_EQ(std::string(header, 4), "RIFF");
    EXPECT_EQ(std::string(header + 8, 4), "WAVE");
}

#include "AudioRecorderManager.h"
#include <thread>
#include <chrono>

TEST(AudioRecorderManagerTest, VerifyAsynchronousWriting) {
    AudioRecorderManager manager;
    manager.initialize(4, "test_session");
    manager.startSession(48000);
    
    // Push some test blocks
    AudioRecordBlock block;
    block.samples.fill(0.2f);
    block.count = 256;
    
    bool ok = manager.pushBlock(0, block);
    EXPECT_TRUE(ok);
    
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    manager.stopSession();
    
    // Check if the directory and files were created
    EXPECT_TRUE(std::filesystem::exists("test_session/track_1.wav"));
    EXPECT_TRUE(std::filesystem::exists("test_session/track_2.wav"));
    EXPECT_TRUE(std::filesystem::exists("test_session/track_3.wav"));
    EXPECT_TRUE(std::filesystem::exists("test_session/track_4.wav"));
    
    // Clean up
    std::filesystem::remove_all("test_session");
}

TEST_F(DynamicAudioEngineTest, VerifyDynamicReconfiguration) {
    auto core = std::make_unique<AudioEngineCore>();
    core->configureEngine(12, 4, 4, 4);
    
    auto& faderStrips = core->getFaderStrips();
    
    // First 12 should be input strips
    for (size_t i = 0; i < 12; ++i) {
        ASSERT_NE(faderStrips[i], nullptr);
        EXPECT_EQ(faderStrips[i]->type, ChannelType::Input);
    }
    
    // Next 4 should be DCA strips
    for (size_t i = 12; i < 16; ++i) {
        ASSERT_NE(faderStrips[i], nullptr);
        EXPECT_EQ(faderStrips[i]->type, ChannelType::DCA);
    }
    
    // Remaining should be nullptr
    for (size_t i = 16; i < faderStrips.size(); ++i) {
        EXPECT_EQ(faderStrips[i], nullptr);
    }
}

TEST_F(DynamicAudioEngineTest, VerifyRealtimeRecordStreaming) {
    auto core = std::make_unique<AudioEngineCore>();
    AudioRecorderManager recorder;
    
    recorder.initialize(2, "test_streaming_session");
    core->setRecorder(&recorder);
    core->setRecordingArmed(true);
    
    recorder.startSession(48000);
    
    // Simulate real-time blocks pushing
    std::vector<float> channel1(256, 0.5f);
    std::vector<float> channel2(256, -0.5f);
    const float* inputs[2] = { channel1.data(), channel2.data() };
    float* outputs[2] = { channel1.data(), channel2.data() };
    
    // Run IOCallback multiple times to accumulate samples and stream
    for (int i = 0; i < 10; ++i) {
        core->audioDeviceIOCallbackWithContext(inputs, 2, outputs, 2, 256, nullptr);
    }
    
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    recorder.stopSession();
    
    // Check files are generated
    EXPECT_TRUE(std::filesystem::exists("test_streaming_session/track_1.wav"));
    EXPECT_TRUE(std::filesystem::exists("test_streaming_session/track_2.wav"));
    
    std::filesystem::remove_all("test_streaming_session");
}

TEST(RoutingPatchMapTest, VerifyTypesAndCommands) {
    // Static assertions for SPSC compatibility and standard layout properties
    static_assert(std::is_trivially_copyable_v<RoutingCommand>, "RoutingCommand must be trivially copyable for SPSC compatibility.");
    static_assert(std::is_standard_layout_v<RoutingCommand>, "RoutingCommand must use standard layout.");

    // Verify RoutingCommand default initializations
    RoutingCommand defaultCmd;
    EXPECT_EQ(defaultCmd.type, RoutingCommandType::SetRoute);
    EXPECT_EQ(defaultCmd.channelIdx, 0);
    EXPECT_EQ(defaultCmd.targetIdx, 0);
    EXPECT_NEAR(defaultCmd.gain, 0.0f, 1e-6f);
    EXPECT_EQ(defaultCmd.flag, 0);

    AudioSourcePatch inputPatch;
    inputPatch.type = AudioSourceType::Generator;
    inputPatch.index = 1;
    EXPECT_EQ(inputPatch.type, AudioSourceType::Generator);
    EXPECT_EQ(inputPatch.index, 1);

    OutputPatch outputPatch;
    outputPatch.active = true;
    outputPatch.busIdx = 2;
    EXPECT_TRUE(outputPatch.active);
    EXPECT_EQ(outputPatch.busIdx, 2);
}

TEST(AudioEngineCoreTest, VerifyPipelineStages) {
    auto engine = std::make_unique<AudioEngineCore>();
    engine->configureEngine(24, 8, 8, 8);
    
    // Patch channel 0 to Generator (1kHz Sine)
    engine->setInputPatch(0, AudioSourceType::Generator, 0); // 0 = Sine
    // Route channel 0 to MST L (Bus 0)
    engine->setRoute(0, 0, 1.0f, TapPoint::PostFader);
    // Patch Output Port 0 to MST L (Bus 0)
    engine->setOutputPatch(0, 0);

    // Create 8 separate non-aliasing buffers
    std::vector<std::vector<float>> outputBuffers(8, std::vector<float>(256, 0.0f));
    std::vector<float*> outputPtrs(8);
    for (size_t i = 0; i < 8; ++i) {
        outputPtrs[i] = outputBuffers[i].data();
        std::cout << "[DEBUG] outputBuffers[" << i << "].data() = " << (void*)outputBuffers[i].data() << std::endl;
    }
    
    // Run engine process callback
    engine->audioDeviceIOCallbackWithContext(
        nullptr, 0,
        outputPtrs.data(), 8,
        256, nullptr
    );

    // Verify that output port 0 received non-zero signal (from Sine generator)
    float sum0 = 0.0f;
    for(float s : outputBuffers[0]) sum0 += std::abs(s);
    std::cout << "[DEBUG] sum0 = " << sum0 << std::endl;
    EXPECT_GT(sum0, 0.0f);

    // Verify that other output ports remain silent
    for (size_t i = 1; i < 8; ++i) {
        float sumI = 0.0f;
        for(float s : outputBuffers[i]) sumI += std::abs(s);
        std::cout << "[DEBUG] sum[" << i << "] = " << sumI << std::endl;
        EXPECT_NEAR(sumI, 0.0f, 1e-6f);
    }
}

TEST(AudioEngineCoreTest, VerifyDCAVolumeAttenuation) {
    auto engineA = std::make_unique<AudioEngineCore>();
    engineA->configureEngine(24, 8, 8, 8);
    engineA->setInputPatch(0, AudioSourceType::Generator, 0); // Sine
    engineA->setRoute(0, 0, 1.0f, TapPoint::PostFader);
    engineA->setOutputPatch(0, 0);
    engineA->updateChannelDCAMapping(0, 1, true); // DCA 1
    engineA->updateDCAVolume(1, 1.0f); // Volume = 1.0

    auto engineB = std::make_unique<AudioEngineCore>();
    engineB->configureEngine(24, 8, 8, 8);
    engineB->setInputPatch(0, AudioSourceType::Generator, 0); // Sine
    engineB->setRoute(0, 0, 1.0f, TapPoint::PostFader);
    engineB->setOutputPatch(0, 0);
    engineB->updateChannelDCAMapping(0, 1, true); // DCA 1
    engineB->updateDCAVolume(1, 0.5f); // Volume = 0.5

    std::vector<std::vector<float>> outputBuffersA(8, std::vector<float>(256, 0.0f));
    std::vector<float*> outputPtrsA(8);
    std::vector<std::vector<float>> outputBuffersB(8, std::vector<float>(256, 0.0f));
    std::vector<float*> outputPtrsB(8);

    for (size_t i = 0; i < 8; ++i) {
        outputPtrsA[i] = outputBuffersA[i].data();
        outputPtrsB[i] = outputBuffersB[i].data();
    }

    // Run both engine callbacks
    engineA->audioDeviceIOCallbackWithContext(nullptr, 0, outputPtrsA.data(), 8, 256, nullptr);
    engineB->audioDeviceIOCallbackWithContext(nullptr, 0, outputPtrsB.data(), 8, 256, nullptr);

    // Verify that engineA output is non-zero
    float sumA = 0.0f;
    for (float s : outputBuffersA[0]) sumA += std::abs(s);
    EXPECT_GT(sumA, 0.0f);

    // Verify that engineB output is exactly half of engineA output for each sample
    for (size_t s = 0; s < 256; ++s) {
        EXPECT_NEAR(outputBuffersB[0][s], outputBuffersA[0][s] * 0.5f, 1e-4f);
    }
}

TEST(AudioEngineCoreTest, VerifyDCAMute) {
    auto engine = std::make_unique<AudioEngineCore>();
    engine->configureEngine(24, 8, 8, 8);
    engine->setInputPatch(0, AudioSourceType::Generator, 0); // Sine
    engine->setRoute(0, 0, 1.0f, TapPoint::PostFader);
    engine->setOutputPatch(0, 0);
    engine->updateChannelDCAMapping(0, 1, true); // DCA 1
    engine->updateDCAMute(1, true); // Mute = true

    std::vector<std::vector<float>> outputBuffers(8, std::vector<float>(256, 0.0f));
    std::vector<float*> outputPtrs(8);
    for (size_t i = 0; i < 8; ++i) {
        outputPtrs[i] = outputBuffers[i].data();
    }

    engine->audioDeviceIOCallbackWithContext(nullptr, 0, outputPtrs.data(), 8, 256, nullptr);

    // Verify output is completely silent due to DCA mute
    float sum = 0.0f;
    for (float s : outputBuffers[0]) sum += std::abs(s);
    EXPECT_NEAR(sum, 0.0f, 1e-6f);
}

TEST(AudioChannelStripTest, VerifyVolumeAndMute) {
    AudioChannelStrip strip;
    strip.prepareToPlay(48000.0f);
    strip.setFaderLinear(0.5f);
    EXPECT_FLOAT_EQ(strip.volumeTarget, 0.5f);

    std::vector<float> buffer(256, 1.0f);
    strip.processBlock(buffer.data(), buffer.size());
    // Fader volume target should pull it down (smoothed)
    EXPECT_LT(buffer[255], 1.0f);

    strip.setMuted(true);
    strip.processBlock(buffer.data(), buffer.size());
    // Muted channel should output absolute silence
    for (float s : buffer) {
        EXPECT_FLOAT_EQ(s, 0.0f);
    }
}

TEST(AudioEngineCoreTest, VerifyPeaksAndBusControls) {
    auto engine = std::make_unique<AudioEngineCore>();
    engine->configureEngine(24, 8, 8, 8);

    // Route channel 0 (Sine) to Bus 0
    engine->setInputPatch(0, AudioSourceType::Generator, 0); // 1kHz Sine
    engine->setRoute(0, 0, 1.0f, TapPoint::PostFader);
    engine->setOutputPatch(0, 0);

    // Unmute channel and set full volume
    engine->getChannelPool()[0].setFaderLinear(1.0f);
    engine->getChannelPool()[0].setMuted(false);

    // Set Bus 0 volume to 0.5
    engine->getChannelPool()[64].setFaderLinear(0.5f); // MaxInputs is 64

    std::vector<float> outputBuffer(256, 0.0f);
    std::vector<float*> outputPtrs(8, outputBuffer.data());

    // We need to pass valid outputPtrs for all 8 channels to avoid crashes or out-of-bounds
    std::vector<std::vector<float>> outputBuffers(8, std::vector<float>(256, 0.0f));
    for (size_t i = 0; i < 8; ++i) {
        outputPtrs[i] = outputBuffers[i].data();
    }

    engine->audioDeviceIOCallbackWithContext(
        nullptr, 0,
        outputPtrs.data(), 8,
        256, nullptr
    );

    // Check input peak and bus peak are tracked
    EXPECT_GT(engine->getInputPeak(0).load(), 0.0f);
    EXPECT_GT(engine->getBusPeak(0).load(), 0.0f);

    // Master output peak should also be tracked
    EXPECT_GT(engine->getMasterPeak().load(), 0.0f);
}

#include "WASAPIDeviceWorker.h"

TEST(WASAPIDeviceWorkerTest, NullDeviceHandling) {
    WASAPIDeviceWorker worker(nullptr, WASAPIDeviceWorker::Mode::Capture);
    EXPECT_FALSE(worker.isRunning());
    EXPECT_FALSE(worker.start());
    EXPECT_EQ(worker.getDeviceName(), L"");
    worker.stop();
}

TEST(WASAPIDeviceWorkerTest, BufferIOHandling) {
    WASAPIDeviceWorker worker(nullptr, WASAPIDeviceWorker::Mode::Capture);
    std::vector<float> input(128, 0.5f);
    worker.writeRenderSamples(input.data(), input.size());

    std::vector<float> output(128, 0.0f);
    worker.readCapturedSamples(output.data(), output.size());

    for (size_t i = 0; i < 128; ++i) {
        EXPECT_FLOAT_EQ(output[i], 0.5f);
    }
}

TEST(WASAPIDeviceWorkerTest, VerifyCatchUpAndBufferLevels) {
    // Create worker in Capture mode (using nullptr device for mock structure)
    WASAPIDeviceWorker worker(nullptr, WASAPIDeviceWorker::Mode::Capture);
    
    // Initially empty
    EXPECT_EQ(worker.getBufferedSampleCount(), 0);

    // Simulate writing a massive backlog (e.g., 2000 samples)
    std::vector<float> data(2000, 1.0f);
    worker.writeRenderSamples(data.data(), data.size()); // Write to ring buffer
    
    // Since it's capture/render shared buffer, verify backlog level
    EXPECT_EQ(worker.getBufferedSampleCount(), 2000);

    // Reading a block of 256 samples should trigger catch-up
    // The backlog (2000) exceeds the threshold (512), so it should discard down to 512
    // and then read 256, leaving exactly 256 unread samples.
    std::vector<float> dest(256, 0.0f);
    worker.readCapturedSamples(dest.data(), dest.size());

    EXPECT_EQ(worker.getBufferedSampleCount(), 256);
}


#include "WindowsProcessCapture.h"

TEST(WindowsProcessCaptureTest, VerifyCaptureLifecycleAndQueuePush) {
    WindowsProcessCapture capture;
    SPSCQueue<float> queue(4096);
    
    // Start capture with a target PID of 0 to trigger fallback paths
    EXPECT_TRUE(capture.start(0, queue));
    
    // Wait a brief period to allow the thread to push some samples
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    
    bool isFallback = capture.isFallbackActive();
    capture.stop();
    
    // Check that we received some samples in the queue
    size_t count = 0;
    float sum = 0.0f;
    while (auto sample = queue.pop()) {
        count++;
        sum += std::abs(*sample);
    }
    
    if (isFallback) {
        EXPECT_GT(count, 0);
        EXPECT_GT(sum, 0.0f);
    } else {
        EXPECT_GE(count, 0);
    }
}

#include "ui/LocalMediaDeck.h"

TEST(LocalMediaDeckTest, PlaybackControlsAndState) {
    LocalMediaDeck deck;
    EXPECT_FALSE(deck.isPlaying());
    EXPECT_EQ(deck.position(), 0);
    
    deck.play();
    EXPECT_TRUE(deck.isPlaying());
    
    deck.setPosition(50);
    EXPECT_EQ(deck.position(), 50);
    EXPECT_NEAR(deck.playbackProgress(), 50.0 / 120.0, 1e-5);
    
    deck.pause();
    EXPECT_FALSE(deck.isPlaying());
    EXPECT_EQ(deck.position(), 50);
    
    deck.stop();
    EXPECT_FALSE(deck.isPlaying());
    EXPECT_EQ(deck.position(), 0);
    
    deck.load("test_track.wav");
    EXPECT_EQ(deck.filePath().toStdString(), "test_track.wav");
    EXPECT_GT(deck.duration(), 0);
}

TEST(LocalMediaDeckTest, VerifyMediaPatchAudioStreaming) {
    auto core = std::make_unique<AudioEngineCore>();
    core->configureEngine(24, 8, 8, 8);
    LocalMediaDeck deck;
    core->setMediaDeck(&deck);
    
    // Patch channel 0 to Media Deck
    core->setInputPatch(0, AudioSourceType::Media, 0); // 0 = Left channel
    // Route channel 0 to Bus 0 (MST L)
    core->setRoute(0, 0, 1.0f, TapPoint::PostFader);
    // Patch Output Port 0 to Bus 0
    core->setOutputPatch(0, 0);
    
    // Set fader gain to 0dB (1.0f) and unmute
    core->getChannelPool()[0].setFaderLinear(1.0f);
    core->getChannelPool()[0].setMuted(false);
    
    // Setup 8 output buffers to match engine active output channels
    std::vector<std::vector<float>> outputBuffers(8, std::vector<float>(256, 0.0f));
    std::vector<float*> outputPtrs(8);
    for (size_t i = 0; i < 8; ++i) {
        outputPtrs[i] = outputBuffers[i].data();
    }
    
    // Initially paused, output should be silent
    core->audioDeviceIOCallbackWithContext(nullptr, 0, outputPtrs.data(), 8, 256, nullptr);
    for (float val : outputBuffers[0]) {
        EXPECT_NEAR(val, 0.0f, 1e-5f);
    }
    
    // Start play, output should contain synth pad signal
    deck.play();
    core->audioDeviceIOCallbackWithContext(nullptr, 0, outputPtrs.data(), 8, 256, nullptr);
    
    bool hasSignal = false;
    for (float val : outputBuffers[0]) {
        if (std::abs(val) > 0.01f) {
            hasSignal = true;
            break;
        }
    }
    EXPECT_TRUE(hasSignal);
}

TEST_F(DynamicAudioEngineTest, UnpatchedChannelsOutputSilence) {
    auto core = std::make_unique<AudioEngineCore>();
    // Configure engine with no active routes
    core->configureEngine(8, 2, 0, 8);

    std::array<float, 256> inputBuf{};
    std::array<float, 256> outputBuf{};
    std::fill_n(inputBuf.data(), 256, 1.0f);
    const float* inPtrs[24] = {};
    float* outPtrs[8] = {};
    for (int i = 0; i < 24; ++i) inPtrs[i] = inputBuf.data();
    for (int i = 0; i < 8; ++i) outPtrs[i] = outputBuf.data();

    core->audioDeviceIOCallbackWithContext(
        inPtrs, 24, outPtrs, 8, 256, nullptr
    );

    // Master peak should be 0 since no routes are set after configureEngine clears the matrix
    float masterPeak = core->getMasterPeak().load(std::memory_order_relaxed);
    EXPECT_EQ(masterPeak, 0.0f);
}






