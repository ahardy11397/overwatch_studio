#pragma once

#include <cstddef>

/**
 * @class ParameterSmoother
 * @brief First-order IIR low-pass filter to smooth parameter changes and eliminate zipper noise.
 */
class ParameterSmoother {
public:
    ParameterSmoother() noexcept : current(0.0f), target(0.0f), alpha(0.00868f) {}

    /**
     * @brief Set a new target value for the parameter.
     */
    void setTarget(float newTarget) noexcept {
        target = newTarget;
    }

    /**
     * @brief Reset the smoother instantly to a specific value.
     */
    void reset(float initialValue) noexcept {
        current = initialValue;
        target = initialValue;
    }

    /**
     * @brief Retrieve the next smoothed sample value.
     */
    float getNextValue() noexcept [[clang::nonblocking]] {
        current = (alpha * target) + ((1.0f - alpha) * current);
        return current;
    }

    /**
     * @brief Smooth a buffer of values by multiplying each sample by the interpolated parameter.
     */
    void processBlock(float* buffer, size_t numSamples) noexcept [[clang::nonblocking]] {
        for (size_t i = 0; i < numSamples; ++i) {
            current = (alpha * target) + ((1.0f - alpha) * current);
            buffer[i] *= current;
        }
    }

private:
    float current;
    float target;
    const float alpha; // Pre-calculated smoothing constant for 15ms ramp-time at 48kHz
};
