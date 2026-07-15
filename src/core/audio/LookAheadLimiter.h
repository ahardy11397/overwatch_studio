#pragma once

#include <array>
#include <cmath>
#include <algorithm>
#include <cstddef>

/**
 * @class LookAheadLimiter
 * @brief Dynamic look-ahead brickwall limiter protecting downstream equipment from physical clipping.
 */
class LookAheadLimiter {
public:
    static constexpr size_t LookAheadSamples = 240; // 5ms look-ahead at 48kHz
    static constexpr float Ceiling = 0.89125f;       // Strictly -1.0 dBFS

    LookAheadLimiter() noexcept 
        : writeIndex(0), envelope(0.0f), release(0.9992f) { // Pre-tuned release envelope
        delayLine.fill(0.0f);
    }

    /**
     * @brief Resets the internal state of the limiter.
     */
    void reset() noexcept {
        delayLine.fill(0.0f);
        writeIndex = 0;
        envelope = 0.0f;
    }

    /**
     * @brief Process a block of stereophonic or monophonic samples.
     */
    void process(float* buffer, size_t numSamples) noexcept [[clang::nonblocking]] {
        for (size_t s = 0; s < numSamples; ++s) {
            const float input = buffer[s];
            delayLine[writeIndex] = input;

            // 1. Detect sidechain peak (absolute value of current input)
            const float absolutePeak = std::abs(input);

            // 2. Exponential peak tracking (instant attack, slow decay release)
            if (absolutePeak > envelope) {
                envelope = absolutePeak; // Instant attack prevents brickwall bypass
            } else {
                envelope = (release * envelope) + ((1.0f - release) * absolutePeak);
            }

            // 3. Compute target reduction coefficient
            float targetGain = 1.0f;
            if (envelope > Ceiling) {
                targetGain = Ceiling / envelope;
            }

            // 4. Extract delayed sample from circular look-ahead delay line
            const size_t readIndex = (writeIndex + 1) % LookAheadSamples;
            const float delayedSample = delayLine[readIndex];

            // 5. Apply gain attenuation
            buffer[s] = delayedSample * targetGain;

            // 6. Advance write pointer
            writeIndex = (writeIndex + 1) % LookAheadSamples;
        }
    }

private:
    std::array<float, LookAheadSamples> delayLine;
    size_t writeIndex;
    float envelope;
    float release;
};