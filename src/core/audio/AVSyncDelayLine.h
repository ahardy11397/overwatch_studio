#pragma once

#include <array>
#include <algorithm>
#include <cstddef>

/**
 * @class AVSyncDelayLine
 * @brief Sample-accurate delay line utilizing a pre-allocated circular buffer to synchronize audio to lagging video frames.
 */
class AVSyncDelayLine {
public:
    // Contiguous pre-allocated buffer supports up to 200ms of delay at 48kHz (9600 samples)
    static constexpr size_t MaxDelaySamples = 9600;

    AVSyncDelayLine() noexcept : writeIndex(0), delaySamples(0) {
        buffer.fill(0.0f);
    }

    /**
     * @brief Set the delay time dynamically in milliseconds.
     */
    void setDelayMs(float ms, float sampleRate) noexcept {
        size_t requested = static_cast<size_t>((ms * sampleRate) / 1000.0f);
        delaySamples = std::min(requested, MaxDelaySamples - 1);
    }

    /**
     * @brief Resets the delay buffer history to absolute silence.
     */
    void reset() noexcept {
        buffer.fill(0.0f);
        writeIndex = 0;
    }

    /**
     * @brief Process a single audio sample through the delay line.
     */
    float processSample(float inputSample) noexcept [[clang::nonblocking]] {
        buffer[writeIndex] = inputSample;

        // Fetch delayed sample by calculating circular buffer read pointer
        const size_t readIndex = (writeIndex + MaxDelaySamples - delaySamples) % MaxDelaySamples;

        // Advance write pointer
        writeIndex = (writeIndex + 1) % MaxDelaySamples;

        return buffer[readIndex];
    }

    /**
     * @brief Process a block of audio samples through the delay line in-place.
     */
    void processBlock(float* samples, size_t numSamples) noexcept [[clang::nonblocking]] {
        for (size_t s = 0; s < numSamples; ++s) {
            samples[s] = processSample(samples[s]);
        }
    }

private:
    std::array<float, MaxDelaySamples> buffer;
    size_t writeIndex;
    size_t delaySamples;
};
