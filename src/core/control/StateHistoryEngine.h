#pragma once

#include <array>
#include <mutex>
#include <cstdint>

struct ConsoleState {
    float channelVolumes[24] = {
        1.0f, 1.0f, 1.0f, 1.0f,  1.0f, 1.0f, 1.0f, 1.0f,
        1.0f, 1.0f, 1.0f, 1.0f,  1.0f, 1.0f, 1.0f, 1.0f,
        1.0f, 1.0f, 1.0f, 1.0f,  1.0f, 1.0f, 1.0f, 1.0f
    };
    bool channelMutes[24] = {
        false, false, false, false,  false, false, false, false,
        false, false, false, false,  false, false, false, false,
        false, false, false, false,  false, false, false, false
    };
    float masterVolume = 0.8f;
    bool masterMute = false;
    int programCameraIdx = 0;
    int previewCameraIdx = 1;
    bool fadeToBlack = false;
    uint64_t timestampMs = 0;
};

/**
 * @class StateHistoryEngine
 * @brief Thread-safe, zero-allocation circular buffer of size 10 storing pre-transition snapshots.
 */
class StateHistoryEngine {
public:
    static StateHistoryEngine& getInstance() {
        static StateHistoryEngine instance;
        return instance;
    }

    void pushState(const ConsoleState& state) noexcept {
        std::lock_guard<std::mutex> lock(mutex);
        buffer[writeIndex] = state;
        writeIndex = (writeIndex + 1) % Capacity;
        if (size < Capacity) {
            size++;
        }
    }

    bool popState(ConsoleState& state) noexcept {
        std::lock_guard<std::mutex> lock(mutex);
        if (size == 0) {
            return false;
        }
        
        writeIndex = (writeIndex - 1 + Capacity) % Capacity;
        state = buffer[writeIndex];
        size--;
        return true;
    }

    size_t getHistorySize() const noexcept {
        std::lock_guard<std::mutex> lock(mutex);
        return size;
    }

    void clear() noexcept {
        std::lock_guard<std::mutex> lock(mutex);
        writeIndex = 0;
        size = 0;
        buffer.fill({});
    }

private:
    StateHistoryEngine() = default;
    static constexpr size_t Capacity = 10;
    std::array<ConsoleState, Capacity> buffer{};
    size_t writeIndex = 0;
    size_t size = 0;
    mutable std::mutex mutex;
};
