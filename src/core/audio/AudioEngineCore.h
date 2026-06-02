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
#include "RoutingPatchMap.h"
#include "../control/SPSCQueue.h"
#include <random>

class AudioEngineCore : public juce::AudioIODeviceCallback {
public:
    static constexpr size_t InputChannelsCount = 24;
    static constexpr size_t OutputChannelsCount = 8;
    static constexpr size_t MaxBlockSize = 2048;

    static constexpr size_t MaxInputs = 64;
    static constexpr size_t MaxBuses = 16;
    static constexpr size_t MaxAuxes = 16;
    static constexpr size_t MaxFX = 8;
    static constexpr size_t MaxDCAs = 32;
    static constexpr size_t PoolSize = MaxInputs + MaxBuses + MaxAuxes + MaxFX + MaxDCAs;

    AudioEngineCore() noexcept : activeSampleRate(48000.0f), uiToDspQueue(1024) {
        inputBufferPtrs.fill(nullptr);
        outputBufferPtrs.fill(nullptr);

        // Initialize maps and queues
        inputPatchMap.fill(AudioSourcePatch{AudioSourceType::None, 0});
        outputPatchMap.fill(OutputPatch{false, 0});
        dcaVolumes.fill(1.0f);
        dcaMutes.fill(false);
        channelDcaMasks.fill(0);

        for (size_t i = 0; i < 24; ++i) {
            appCaptureQueues[i] = std::make_unique<SPSCQueue<float>>(16384);
        }

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

        // Initialize faderStrips pointers
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
        for (auto& strip : channelPool) {
            strip.prepareToPlay(activeSampleRate);
        }
    }

    void audioDeviceStopped() override {
        RealtimeLogger::getInstance().log("AudioEngineCore callback stopped.");
    }

    SPSCQueue<RoutingCommand>& getCommandQueue() noexcept { return uiToDspQueue; }

    SPSCQueue<float>* getAppCaptureQueue(size_t channelIdx) noexcept {
        if (channelIdx >= 24) return nullptr;
        return appCaptureQueues[channelIdx].get();
    }

    void setInputPatch(uint32_t channelIdx, AudioSourceType type, uint32_t index) noexcept {
        if (channelIdx < 24) {
            inputPatchMap[channelIdx] = AudioSourcePatch{type, index};
        }
    }

    void setRoute(uint32_t src, uint32_t dest, float gain, TapPoint tap) noexcept {
        if (src < 24 && dest < 8) {
            routingMatrix.setRoute(src, dest, gain, tap);
        }
    }

    void unpatchRoute(uint32_t src, uint32_t dest) noexcept {
        if (src < 24 && dest < 8) {
            routingMatrix.setRoute(src, dest, 0.0f, TapPoint::PostFader);
        }
    }

    void setOutputPatch(uint32_t hwOutputIdx, uint32_t busIdx) noexcept {
        if (hwOutputIdx < 8) {
            outputPatchMap[hwOutputIdx] = OutputPatch{true, busIdx};
        }
    }

    void clearOutputPatch(uint32_t hwOutputIdx) noexcept {
        if (hwOutputIdx < 8) {
            outputPatchMap[hwOutputIdx] = OutputPatch{false, 0};
        }
    }

    void updateChannelDCAMapping(uint32_t chIdx, uint32_t dcaIdx, bool active) noexcept {
        if (chIdx < 24 && dcaIdx < 8) {
            if (active) {
                channelDcaMasks[chIdx] |= (1 << dcaIdx);
            } else {
                channelDcaMasks[chIdx] &= ~(1 << dcaIdx);
            }
        }
    }

    void updateDCAVolume(uint32_t dcaIdx, float volume) noexcept {
        if (dcaIdx < 8) {
            dcaVolumes[dcaIdx] = volume;
        }
    }

    void updateDCAMute(uint32_t dcaIdx, bool mute) noexcept {
        if (dcaIdx < 8) {
            dcaMutes[dcaIdx] = mute;
        }
    }

    void audioDeviceIOCallbackWithContext(
        const float** inputChannelData, int numInputChannels,
        float** outputChannelData, int numOutputChannels,
        int numSamples, const void* context
    ) override REALTIME_SAFE {
        (void)context;
        size_t samples = static_cast<size_t>(numSamples);
        if (samples > MaxBlockSize) {
            samples = MaxBlockSize;
        }
        size_t hardwareInputs = std::min(static_cast<size_t>(numInputChannels), InputChannelsCount);
        size_t hardwareOutputs = std::min(static_cast<size_t>(numOutputChannels), OutputChannelsCount);

        // Compute activeInputs and activeBuses
        size_t activeInputs = std::min(activeInputsCount.load(std::memory_order_relaxed), InputChannelsCount);
        size_t activeBuses = std::min(activeBusesCount.load(std::memory_order_relaxed), size_t(8));

        // 1. Process SPSC commands from the UI thread
        while (auto cmdOpt = uiToDspQueue.pop()) {
            const auto& cmd = *cmdOpt;
            switch (cmd.type) {
                case RoutingCommandType::SetInputPatch:
                    if (cmd.targetIdx <= static_cast<uint32_t>(AudioSourceType::AppCapture)) {
                        setInputPatch(cmd.channelIdx, static_cast<AudioSourceType>(cmd.targetIdx), cmd.flag);
                    }
                    break;
                case RoutingCommandType::SetRoute:
                    if (cmd.flag <= static_cast<uint32_t>(TapPoint::PostFader)) {
                        setRoute(cmd.channelIdx, cmd.targetIdx, cmd.gain, static_cast<TapPoint>(cmd.flag));
                    }
                    break;
                case RoutingCommandType::UnpatchRoute:
                    unpatchRoute(cmd.channelIdx, cmd.targetIdx);
                    break;
                case RoutingCommandType::SetOutputPatch:
                    if (cmd.flag != 0) {
                        setOutputPatch(cmd.channelIdx, cmd.targetIdx);
                    } else {
                        clearOutputPatch(cmd.channelIdx);
                    }
                    break;
                case RoutingCommandType::SetDCAMapping:
                    updateChannelDCAMapping(cmd.channelIdx, cmd.targetIdx, cmd.flag != 0);
                    break;
                case RoutingCommandType::SetDCAVolume:
                    updateDCAVolume(cmd.channelIdx, cmd.gain);
                    break;
                case RoutingCommandType::SetDCAMute:
                    updateDCAMute(cmd.channelIdx, cmd.flag != 0);
                    break;
            }
        }

        // Initialize output buffer pointers to silence first
        for (size_t o = 0; o < OutputChannelsCount; ++o) {
            outputBufferPtrs[o] = (o < hardwareOutputs && outputChannelData[o]) ? outputChannelData[o] : dummySummingBuffer.data();
            std::fill_n(outputBufferPtrs[o], samples, 0.0f);
        }

        // Zero out active ranges of pre-allocated buffers
        for (size_t c = 0; c < activeInputs; ++c) {
            std::fill_n(channelBuffers[c].data(), samples, 0.0f);
        }
        for (size_t b = 0; b < activeBuses; ++b) {
            std::fill_n(busBuffers[b].data(), samples, 0.0f);
        }
        std::fill_n(dummySummingBuffer.data(), samples, 0.0f);

        // 2. Stage 1: Input Patching (Source -> Temp Channels)
        for (size_t c = 0; c < activeInputs; ++c) {
            float* dest = channelBuffers[c].data();
            const auto& patch = inputPatchMap[c];

            if (patch.type == AudioSourceType::Hardware) {
                const float* hwSrc = (patch.index < hardwareInputs && inputChannelData[patch.index]) ? inputChannelData[patch.index] : dummyBuffer.data();
                std::copy_n(hwSrc, samples, dest);
            } else if (patch.type == AudioSourceType::Generator) {
                if (patch.index == 0) { // 1kHz Sine
                    const float freq = 1000.0f;
                    const float phaseInc = 2.0f * 3.14159265f * freq / activeSampleRate;
                    for (size_t s = 0; s < samples; ++s) {
                        dest[s] = 0.5f * std::sin(sinePhase);
                        sinePhase += phaseInc;
                        if (sinePhase >= 2.0f * 3.14159265f) sinePhase -= 2.0f * 3.14159265f;
                    }
                } else { // Pink Noise (Paul Kellet's refined method)
                    for (size_t s = 0; s < samples; ++s) {
                        noiseSeed = noiseSeed * 196314165 + 907633385;
                        float white = (static_cast<float>(noiseSeed) / 4294967295.0f) * 2.0f - 1.0f;
                        pinkB0 = 0.99886f * pinkB0 + white * 0.0555179f;
                        pinkB1 = 0.99332f * pinkB1 + white * 0.0750759f;
                        pinkB2 = 0.96900f * pinkB2 + white * 0.1538520f;
                        pinkB3 = 0.86650f * pinkB3 + white * 0.3104856f;
                        pinkB4 = 0.55000f * pinkB4 + white * 0.5329522f;
                        pinkB5 = -0.7616f * pinkB5 - white * 0.0168980f;
                        float pink = pinkB0 + pinkB1 + pinkB2 + pinkB3 + pinkB4 + pinkB5 + pinkB6 + white * 0.5362f;
                        pinkB6 = white * 0.115926f;
                        dest[s] = pink * 0.11f; // Normalize roughly to -12dBFS
                    }
                }
            } else if (patch.type == AudioSourceType::AppCapture) {
                // Pull from dedicated process capture queue
                auto* queue = appCaptureQueues[c].get();
                for (size_t s = 0; s < samples; ++s) {
                    if (auto sampleOpt = queue->pop()) {
                        dest[s] = *sampleOpt;
                    } else {
                        dest[s] = 0.0f;
                    }
                }
            } else {
                std::fill_n(dest, samples, 0.0f);
            }
        }

        // 3. Stage 2: Channel Strip DSP & DCA Scaling
        for (size_t c = 0; c < activeInputs; ++c) {
            float* buf = channelBuffers[c].data();
            
            // Scale volume target based on DCA mapping
            float dcaGainMultiplier = 1.0f;
            bool dcaMutedActive = false;
            uint32_t mask = channelDcaMasks[c];
            for (size_t d = 0; d < 8; ++d) {
                if (mask & (1 << d)) {
                    dcaGainMultiplier *= dcaVolumes[d];
                    if (dcaMutes[d]) {
                        dcaMutedActive = true;
                    }
                }
            }

            // Process using channelPool[c] directly
            channelPool[c].processBlock(buf, samples);
            
            // Apply DCA Gain multiplication and DCA Mutes
            float dcaFinalGain = dcaMutedActive ? 0.0f : dcaGainMultiplier;
            for (size_t s = 0; s < samples; ++s) {
                buf[s] *= dcaFinalGain;
            }
        }

        // 4. Stage 3: Internal Matrix Summing (Buses 0-7)
        std::array<const float*, 24> channelPtrs{};
        for (size_t c = 0; c < 24; ++c) {
            channelPtrs[c] = (c < activeInputs) ? channelBuffers[c].data() : dummyBuffer.data();
        }
        std::array<float*, 8> busPtrs{};
        for (size_t b = 0; b < 8; ++b) {
            busPtrs[b] = (b < activeBuses) ? busBuffers[b].data() : dummySummingBuffer.data();
        }

        routingMatrix.process(
            std::span<const float*>(channelPtrs.data(), 24),
            std::span<float*>(busPtrs.data(), 8),
            samples
        );

        // 5. Stage 4: Output Patching (Buses -> Outputs)
        for (size_t o = 0; o < OutputChannelsCount; ++o) {
            const auto& patch = outputPatchMap[o];
            if (patch.active && patch.busIdx < activeBuses) {
                std::copy_n(busBuffers[patch.busIdx].data(), samples, outputBufferPtrs[o]);
            }
        }

        // 6. Stage 5: Master Safety Limiter
        for (size_t o = 0; o < hardwareOutputs; ++o) {
            masterSafetyLimiters[o].process(outputBufferPtrs[o], samples);
        }

        // 7. Append to recording SPSC buffers if armed
        if (m_recordingArmed.load() && m_recorder != nullptr) {
            for (size_t c = 0; c < activeInputs; ++c) {
                auto& rb = m_recordBlocks[c];
                for (size_t s = 0; s < samples; ++s) {
                    rb.samples[rb.count++] = channelBuffers[c][s];
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

        size_t faderIdx = 0;
        for (size_t i = 0; i < activeInputsCount.load() && faderIdx < faderStrips.size(); ++i) {
            faderStrips[faderIdx++] = &channelPool[i];
        }
        
        size_t dcaStartIdx = MaxInputs + MaxBuses + MaxAuxes + MaxFX;
        for (size_t i = 0; i < activeDCAsCount.load() && faderIdx < faderStrips.size(); ++i) {
            faderStrips[faderIdx++] = &channelPool[dcaStartIdx + i];
        }

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
    alignas(64) std::array<LookAheadLimiter, OutputChannelsCount> masterSafetyLimiters;

    std::array<const float*, InputChannelsCount> inputBufferPtrs;
    std::array<float*, OutputChannelsCount> outputBufferPtrs;

    alignas(16) std::array<float, MaxBlockSize> dummyBuffer{};
    alignas(16) std::array<float, MaxBlockSize> dummySummingBuffer{};

    alignas(16) std::array<std::array<float, MaxBlockSize>, 24> channelBuffers{};
    alignas(16) std::array<std::array<float, MaxBlockSize>, 8> busBuffers{};

    std::atomic<size_t> activeInputsCount{24};
    std::atomic<size_t> activeBusesCount{8};
    std::atomic<size_t> activeAuxesCount{8};
    std::atomic<size_t> activeDCAsCount{8};

    // 3-Stage Patching backend state
    std::array<AudioSourcePatch, 24> inputPatchMap;
    std::array<OutputPatch, 8> outputPatchMap;
    std::array<float, 8> dcaVolumes;
    std::array<bool, 8> dcaMutes;
    std::array<uint32_t, 24> channelDcaMasks;

    std::array<std::unique_ptr<SPSCQueue<float>>, 24> appCaptureQueues;
    SPSCQueue<RoutingCommand> uiToDspQueue;

    // Test Signal Generator States
    float sinePhase = 0.0f;
    float pinkB0 = 0.0f;
    float pinkB1 = 0.0f;
    float pinkB2 = 0.0f;
    float pinkB3 = 0.0f;
    float pinkB4 = 0.0f;
    float pinkB5 = 0.0f;
    float pinkB6 = 0.0f;
    uint32_t noiseSeed{12345};

    AudioRecorderManager* m_recorder = nullptr;
    std::atomic<bool> m_recordingArmed{false};
    std::array<AudioRecordBlock, InputChannelsCount> m_recordBlocks{};
};

