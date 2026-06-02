#include <gtest/gtest.h>
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

TEST(DynamicAudioEngineTest, VerifyDynamicReconfiguration) {
    AudioEngineCore core;
    core.configureEngine(12, 4, 4, 4);
    
    auto& faderStrips = core.getFaderStrips();
    
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

TEST(DynamicAudioEngineTest, VerifyRealtimeRecordStreaming) {
    AudioEngineCore core;
    AudioRecorderManager recorder;
    
    recorder.initialize(2, "test_streaming_session");
    core.setRecorder(&recorder);
    core.setRecordingArmed(true);
    
    recorder.startSession(48000);
    
    // Simulate real-time blocks pushing
    std::vector<float> channel1(256, 0.5f);
    std::vector<float> channel2(256, -0.5f);
    const float* inputs[2] = { channel1.data(), channel2.data() };
    float* outputs[2] = { channel1.data(), channel2.data() };
    
    // Run IOCallback multiple times to accumulate samples and stream
    for (int i = 0; i < 10; ++i) {
        core.audioDeviceIOCallbackWithContext(inputs, 2, outputs, 2, 256, nullptr);
    }
    
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    recorder.stopSession();
    
    // Check files are generated
    EXPECT_TRUE(std::filesystem::exists("test_streaming_session/track_1.wav"));
    EXPECT_TRUE(std::filesystem::exists("test_streaming_session/track_2.wav"));
    
    std::filesystem::remove_all("test_streaming_session");
}
