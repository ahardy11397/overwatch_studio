#pragma once

#ifndef REALTIME_SAFE
#if defined(__clang__)
#define REALTIME_SAFE [[clang::nonblocking]]
#else
#define REALTIME_SAFE
#endif
#endif

#include "AudioChannelStrip.h"
#include "SparseRoutingMatrix.h"
#include "LookAheadLimiter.h"
#include "AudioRecorderManager.h"
#include "../control/RealtimeLogger.h"
#include <span>
#include <vector>
#include <memory>
#include <algorithm>
#include <atomic>

#ifndef JUCE_ASIO
namespace juce {
class AudioIODeviceCallback {
public:
    virtual ~AudioIODeviceCallback() = default;
    virtual void audioDeviceIOCallbackWithContext(
        const float** inputChannelData, int numInputChannels,
        float** outputChannelData, int numOutputChannels,
        int numSamples, const void* context
    ) = 0;
    virtual void audioDeviceAboutToStart(void* device) = 0;
    virtual void audioDeviceStopped() = 0;
};
}
#else
#include <juce_audio_devices/juce_audio_devices.h>
#endif

enum class RoutingCommandType : uint8_t {
    SetRoute,
    UnpatchRoute,
    ClearAllRoutes,
    SetDeviceConfig
};

struct alignas(16) RoutingCommand {
    RoutingCommandType type;
    uint32_t sourceId;
    uint32_t destId;
    float gain;
    TapPoint tap;
    uint32_t sampleRate;
    uint32_t bufferSize;
};

class AudioEngineCore : public juce::AudioIODeviceCallback {
public:
    static constexpr size_t InputChannelsCount = 24;
    static constexpr size_t OutputChannelsCount = 8;

    static constexpr size_t MaxInputs = 64;
    static constexpr size_t MaxBuses = 16;
    static constexpr size_t MaxAuxes = 16;
    static constexpr size_t MaxFX = 8;
    static constexpr size_t MaxDCAs = 32;
    static constexpr size_t PoolSize = MaxInputs + MaxBuses + MaxAuxes + MaxFX + MaxDCAs;

    AudioEngineCore() noexcept : activeSampleRate(48000.0f) {
        inputBufferPtrs.fill(nullptr);
        outputBufferPtrs.fill(nullptr);

        // Initialize pool item types
        for (size_t i = 0; i < MaxInputs; ++i) {
            channelPool[i].type = ChannelType::Input;
        }
        for (size_t i = 0; i < MaxBuses; ++i) {
            channelPool[MaxInputs + i].type = ChannelType::Bus;
        }
        for (size_t i = 0; i < MaxAuxes; ++i) {
            channelPool[MaxInputs + MaxBuses + i].type = ChannelType::Aux;
        }
        for (size_t i = 0; i < MaxFX; ++i) {
            channelPool[MaxInputs + MaxBuses + MaxAuxes + i].type = ChannelType::FX;
        }
        for (size_t i = 0; i < MaxDCAs; ++i) {
            channelPool[MaxInputs + MaxBuses + MaxAuxes + MaxFX + i].type = ChannelType::DCA;
        }

        // Initialize faderStrips pointers: 24 inputs, 8 DCAs
        for (size_t i = 0; i < 24; ++i) {
            faderStrips[i] = &channelPool[i];
        }
        for (size_t i = 0; i < 8; ++i) {
            faderStrips[24 + i] = &channelPool[MaxInputs + MaxBuses + MaxAuxes + MaxFX + i];
        }
    }

    void audioDeviceAboutToStart(void* device) override {
        (void)device;
        RealtimeLogger::getInstance().log("AudioEngineCore callback started.");
    }

    void audioDeviceStopped() override {
        RealtimeLogger::getInstance().log("AudioEngineCore callback stopped.");
    }

    void audioDeviceIOCallbackWithContext(
        const float** inputChannelData, int numInputChannels,
        float** outputChannelData, int numOutputChannels,
        int numSamples, const void* context
    ) override REALTIME_SAFE {
        (void)context;
        size_t samples = static_cast<size_t>(numSamples);
        size_t inputs = std::min(static_cast<size_t>(numInputChannels), InputChannelsCount);
        size_t outputs = std::min(static_cast<size_t>(numOutputChannels), OutputChannelsCount);

        // 1. Map pointers safely with bounds checking
        for (size_t i = 0; i < InputChannelsCount; ++i) {
            inputBufferPtrs[i] = (i < inputs && inputChannelData[i]) ? inputChannelData[i] : dummyBuffer.data();
        }
        for (size_t o = 0; o < OutputChannelsCount; ++o) {
            outputBufferPtrs[o] = (o < outputs && outputChannelData[o]) ? outputChannelData[o] : dummySummingBuffer.data();
            std::fill_n(outputBufferPtrs[o], samples, 0.0f);
        }

        // 2. Process channel strips (In-place) using faderStrips pointers
        for (size_t c = 0; c < inputs; ++c) {
            float* dest = outputBufferPtrs[c % outputs];
            std::copy_n(inputBufferPtrs[c], samples, dest);
            if (c < faderStrips.size() && faderStrips[c] != nullptr) {
                faderStrips[c]->processBlock(dest, samples);
            }
        }

        // 3. Process matrix sums
        std::span<const float*> sourceSpan(inputBufferPtrs.data(), InputChannelsCount);
        std::span<float*> destSpan(outputBufferPtrs.data(), OutputChannelsCount);
        routingMatrix.process(sourceSpan, destSpan, samples);

        // 4. Limiter safety
        for (size_t o = 0; o < outputs; ++o) {
            masterSafetyLimiter.process(outputBufferPtrs[o], samples);
        }

        // 5. Append to recording SPSC buffers if armed
        if (m_recordingArmed.load() && m_recorder != nullptr) {
            for (size_t c = 0; c < inputs; ++c) {
                auto& rb = m_recordBlocks[c];
                for (size_t s = 0; s < samples; ++s) {
                    rb.samples[rb.count++] = inputBufferPtrs[c][s];
                    if (rb.count >= AudioRecordBlock::BlockSize) {
                        m_recorder->pushBlock(c, rb);
                        rb.count = 0;
                    }
                }
            }
        }
    }

    AudioChannelStrip& getChannelStrip(size_t index) noexcept {
        return *faderStrips[index % faderStrips.size()];
    }

    SparseRoutingMatrix& getRoutingMatrix() noexcept {
        return routingMatrix;
    }

    std::array<AudioChannelStrip, PoolSize>& getChannelPool() noexcept {
        return channelPool;
    }

    std::array<AudioChannelStrip*, 32>& getFaderStrips() noexcept {
        return faderStrips;
    }

    size_t getActiveSampleRate() const noexcept { return static_cast<size_t>(activeSampleRate); }
    
    void setRecorder(AudioRecorderManager* recorder) noexcept {
        m_recorder = recorder;
    }
    
    bool isRecordingArmed() const noexcept { return m_recordingArmed.load(); }
    void setRecordingArmed(bool armed) noexcept { m_recordingArmed.store(armed); }

    void configureEngine(size_t numInputs, size_t numBuses, size_t numAuxes, size_t numDCAs) noexcept {
        activeInputsCount.store(std::min(numInputs, MaxInputs));
        activeBusesCount.store(std::min(numBuses, MaxBuses));
        activeAuxesCount.store(std::min(numAuxes, MaxAuxes));
        activeDCAsCount.store(std::min(numDCAs, MaxDCAs));

        // Dynamic visual fader strips remapping
        size_t faderIdx = 0;
        for (size_t i = 0; i < activeInputsCount.load() && faderIdx < faderStrips.size(); ++i) {
            faderStrips[faderIdx++] = &channelPool[i];
        }
        
        size_t dcaStartIdx = MaxInputs + MaxBuses + MaxAuxes + MaxFX;
        for (size_t i = 0; i < activeDCAsCount.load() && faderIdx < faderStrips.size(); ++i) {
            faderStrips[faderIdx++] = &channelPool[dcaStartIdx + i];
        }

        // Null-out remaining fader strips
        while (faderIdx < faderStrips.size()) {
            faderStrips[faderIdx++] = nullptr;
        }

        routingMatrix.clear();
    }

private:
    float activeSampleRate;
    alignas(64) std::array<AudioChannelStrip, PoolSize> channelPool;
    alignas(64) std::array<AudioChannelStrip*, 32> faderStrips;
    alignas(64) SparseRoutingMatrix routingMatrix;
    alignas(64) LookAheadLimiter masterSafetyLimiter;

    std::array<const float*, InputChannelsCount> inputBufferPtrs;
    std::array<float*, OutputChannelsCount> outputBufferPtrs;

    alignas(16) std::array<float, 1024> dummyBuffer{};
    alignas(16) std::array<float, 1024> dummySummingBuffer{};

    std::atomic<size_t> activeInputsCount{24};
    std::atomic<size_t> activeBusesCount{8};
    std::atomic<size_t> activeAuxesCount{8};
    std::atomic<size_t> activeDCAsCount{8};

    AudioRecorderManager* m_recorder = nullptr;
    std::atomic<bool> m_recordingArmed{false};
    std::array<AudioRecordBlock, InputChannelsCount> m_recordBlocks{};
};
