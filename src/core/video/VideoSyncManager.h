#pragma once

#ifndef REALTIME_SAFE
#if defined(__clang__)
#define REALTIME_SAFE [[clang::nonblocking]]
#else
#define REALTIME_SAFE
#endif
#endif

#include <array>
#include <atomic>
#include <cstdint>
#include <algorithm>

struct alignas(64) VideoFrame {
    uint64_t pts = 0;
    void* textureHandle = nullptr; // GPU texture binding pointer
    bool isValid = false;
};

/**
 * @class VideoSyncManager
 * @brief Zero-allocation software-defined Genlock.
 * Maintains fractional VRAM queues to lock asynchronous camera sources to master output sync frames.
 */
class VideoSyncManager {
public:
    static constexpr size_t InputChannels = 4;
    static constexpr size_t RingBufferSize = 3; // 3-frame synchronization buffer

    VideoSyncManager() noexcept {
        for (auto& queue : channelQueues) {
            for (auto& frame : queue) {
                frame = {};
            }
        }
        for (auto& idx : writeIndices) {
            idx.store(0, std::memory_order_relaxed);
        }
    }

    /**
     * @brief Ingest a new frame texture directly from a camera stream.
     */
    void REALTIME_SAFE pushFrame(size_t channelIndex, void* textureHandle, uint64_t pts) noexcept {
        if (channelIndex >= InputChannels) return;
        
        size_t idx = writeIndices[channelIndex].load(std::memory_order_relaxed);
        auto& frame = channelQueues[channelIndex][idx];
        frame.textureHandle = textureHandle;
        frame.pts = pts;
        frame.isValid = true;

        writeIndices[channelIndex].store((idx + 1) % RingBufferSize, std::memory_order_release);
    }

    /**
     * @brief Acquire the frame texture closest to the master compositing timestamp.
     */
    void* REALTIME_SAFE acquireGenlockFrame(size_t channelIndex, uint64_t masterPTS) noexcept {
        if (channelIndex >= InputChannels) return nullptr;

        const auto& queue = channelQueues[channelIndex];
        void* bestTexture = nullptr;
        uint64_t minDiff = UINT64_MAX;

        for (size_t i = 0; i < RingBufferSize; ++i) {
            if (!queue[i].isValid) continue;

            uint64_t diff = (queue[i].pts > masterPTS) ? (queue[i].pts - masterPTS) : (masterPTS - queue[i].pts);
            if (diff < minDiff) {
                minDiff = diff;
                bestTexture = queue[i].textureHandle;
            }
        }

        return bestTexture;
    }

    void clear() noexcept {
        for (auto& queue : channelQueues) {
            for (auto& frame : queue) {
                frame = {};
            }
        }
        for (auto& idx : writeIndices) {
            idx.store(0, std::memory_order_relaxed);
        }
    }

private:
    std::array<std::array<VideoFrame, RingBufferSize>, InputChannels> channelQueues;
    std::array<std::atomic<size_t>, InputChannels> writeIndices;
};
