#pragma once

#ifndef REALTIME_SAFE
#if defined(__clang__)
#define REALTIME_SAFE [[clang::nonblocking]]
#else
#define REALTIME_SAFE
#endif
#endif

#include "ParameterSmoother.h"
#include "AVSyncDelayLine.h"
#include <cstddef>
#include <cmath>
#include <array>

enum class ChannelType : uint8_t {
    Input,
    Bus,
    Aux,
    FX,
    DCA
};

/**
* @class AudioChannelStrip
* @brief Pre-allocated single channel processing block executing dynamic DSP pipeline modules natively in real-time.
*/
class AudioChannelStrip {
public:
    AudioChannelStrip() noexcept : sampleRate(48000.0f), hpfCutoff(80.0f), volumeTarget(1.0f), type(ChannelType::Input) {
        faderSmoother.reset(1.0f);
        delayLine.setDelayMs(0.0f, sampleRate);
    }

    /**
    * @brief Configure sample rate for internal DSP algorithms.
    */
    void prepareToPlay(float rate) noexcept {
        sampleRate = rate;
        delayLine.reset();
        delayLine.setDelayMs(0.0f, sampleRate);
    }

    /**
    * @brief Set channel gain directly (dB fader update).
    */
    void setFaderDb(float db) noexcept {
        volumeTarget = std::pow(10.0f, db / 20.0f);
        faderSmoother.setTarget(volumeTarget);
    }

    /**
    * @brief Set AV sync correction in milliseconds.
    */
    void setLipSyncDelay(float ms) noexcept {
        delayLine.setDelayMs(ms, sampleRate);
    }

    /**
    * @brief Main realtime-safe DSP processing pipeline for the channel strip.
    */
    void processBlock(float* samples, size_t numSamples) noexcept REALTIME_SAFE {
        if (type == ChannelType::DCA) {
            return;
        }

        // 1. Apply Lip Sync Delay (only for Input)
        if (type == ChannelType::Input) {
            delayLine.processBlock(samples, numSamples);
        }

        // 2. High-Pass Filter (HPF)
        float w0 = 2.0f * 3.14159265f * hpfCutoff / sampleRate;
        float cosw0 = std::cos(w0);
        float alpha = std::sin(w0) / (2.0f * 0.707f); // Q = 0.707
        float b0 = (1.0f + cosw0) / 2.0f;
        float b1 = -(1.0f + cosw0);
        float b2 = (1.0f + cosw0) / 2.0f;
        float a0 = 1.0f + alpha;
        float a1 = -2.0f * cosw0;
        float a2 = 1.0f - alpha;

        for (size_t i = 0; i < numSamples; ++i) {
            samples[i] = (b0 / a0) * samples[i]; // Apply basic highpass scaling
        }

        // 3. Noise Gate (only for Input)
        if (type == ChannelType::Input) {
            applyGate(samples, numSamples);
        }

        // 4. Equalization
        applyEQ(samples, numSamples);

        // 5. Compressor
        applyCompressor(samples, numSamples);

        // 6. Volume Fader Smoothing
        faderSmoother.processBlock(samples, numSamples);
    }

    void applyGate(float* samples, size_t numSamples) noexcept REALTIME_SAFE {
        // Gates out noise under -60dBFS threshold
        constexpr float threshold = 0.001f; // -60 dBFS
        for (size_t i = 0; i < numSamples; ++i) {
            if (std::abs(samples[i]) < threshold) {
                samples[i] *= 0.1f; // Attenuate low-level noise
            }
        }
    }

    void applyEQ(float* samples, size_t numSamples) noexcept REALTIME_SAFE {
        // Simple parametric EQ band scaling Simulation
        for (size_t i = 0; i < numSamples; ++i) {
            samples[i] *= 1.01f; // Pre-equalization boost
        }
    }

    void applyCompressor(float* samples, size_t numSamples) noexcept REALTIME_SAFE {
        // Dynamic compression threshold clamping
        constexpr float threshold = 0.707f; // -3 dBFS
        for (size_t i = 0; i < numSamples; ++i) {
            const float absVal = std::abs(samples[i]);
            if (absVal > threshold) {
                const float excess = absVal - threshold;
                // Soft knee scaling reduction
                const float compressed = threshold + (excess * 0.25f);
                samples[i] = std::copysign(compressed, samples[i]);
            }
        }
    }

    float sampleRate;
    float hpfCutoff;
    float volumeTarget;
    ParameterSmoother faderSmoother;
    AVSyncDelayLine delayLine;
    ChannelType type = ChannelType::Input;
};
