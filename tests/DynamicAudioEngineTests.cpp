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
