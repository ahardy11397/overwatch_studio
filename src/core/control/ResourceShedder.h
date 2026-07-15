#pragma once

#include <atomic>
#include <cstdio>
#include "RealtimeLogger.h"

/**
 * @class ResourceShedder
 * @brief Zero-allocation framework managing multi-stage shedding protocols when system experiences high jitter.
 */
class ResourceShedder {
public:
    static ResourceShedder& getInstance() {
        static ResourceShedder instance;
        return instance;
    }

    void setSheddingLevel(int level) noexcept {
        int current = currentLevel.load(std::memory_order_relaxed);
        if (level == current) return;
        
        currentLevel.store(level, std::memory_order_release);
        
        char buf[128];
        snprintf(buf, sizeof(buf), "ResourceShedder: Escalated shedding to Level %d", level);
        RealtimeLogger::getInstance().log(buf);

        switch (level) {
            case 1:
                uiThrottled.store(true, std::memory_order_release);
                dspBypassed.store(false, std::memory_order_release);
                vstSandboxed.store(false, std::memory_order_release);
                break;
            case 2:
                uiThrottled.store(true, std::memory_order_release);
                dspBypassed.store(true, std::memory_order_release);
                vstSandboxed.store(false, std::memory_order_release);
                break;
            case 3:
                uiThrottled.store(true, std::memory_order_release);
                dspBypassed.store(true, std::memory_order_release);
                vstSandboxed.store(true, std::memory_order_release);
                break;
            default:
                uiThrottled.store(false, std::memory_order_release);
                dspBypassed.store(false, std::memory_order_release);
                vstSandboxed.store(false, std::memory_order_release);
                break;
        }
    }

    int getSheddingLevel() const noexcept {
        return currentLevel.load(std::memory_order_relaxed);
    }

    bool isUIThrottled() const noexcept {
        return uiThrottled.load(std::memory_order_acquire);
    }

    bool isDSPBypassed() const noexcept {
        return dspBypassed.load(std::memory_order_acquire);
    }

    bool isVSTSandboxed() const noexcept {
        return vstSandboxed.load(std::memory_order_acquire);
    }

    void reset() noexcept {
        setSheddingLevel(0);
    }

private:
    ResourceShedder() = default;

    std::atomic<int> currentLevel{0};
    std::atomic<bool> uiThrottled{false};
    std::atomic<bool> dspBypassed{false};
    std::atomic<bool> vstSandboxed{false};
};
