#pragma once

#ifndef REALTIME_SAFE
#if defined(__clang__)
#define REALTIME_SAFE [[clang::nonblocking]]
#else
#define REALTIME_SAFE
#endif
#endif

#include <readerwriterqueue.h>
#include <optional>

/**
 * @class SPSCQueue
 * @brief Zero-allocation, lock-free communication queue.
 * Wraps moodycamel::ReaderWriterQueue to ensure safe passing of
 * parameters from the UI (Producer) to the real-time DSP/Video engines (Consumer).
 */
template <typename T>
class SPSCQueue {
public:
    SPSCQueue(size_t maxSize = 1024) 
        : queue(maxSize) {}

    // Producer thread
    bool push(const T& item) noexcept {
        return queue.try_enqueue(item);
    }

    bool push(T&& item) noexcept {
        return queue.try_enqueue(std::move(item));
    }

    // Consumer thread (Real-Time DSP/Video Loop)
    std::optional<T> REALTIME_SAFE pop() noexcept {
        T item;
        if (queue.try_dequeue(item)) {
            return item;
        }
        return std::nullopt;
    }

    size_t REALTIME_SAFE size_approx() const noexcept {
        return queue.size_approx();
    }

private:
    moodycamel::ReaderWriterQueue<T> queue;
};
