#pragma once

#include <atomic>
#include "RealtimeLogger.h"

/**
 * @class PanicSwitch
 * @brief Unified red-glowing Master Fade to Black (FTB) panic switch controller.
 */
class PanicSwitch {
public:
    static PanicSwitch& getInstance() {
        static PanicSwitch instance;
        return instance;
    }

    void setFadeToBlack(bool active) noexcept {
        if (ftbActive.exchange(active, std::memory_order_release) != active) {
            if (active) {
                RealtimeLogger::getInstance().log("PANIC SWITCH TRIGGERED: Fading to Black! Muting all audio, blacking out video!");
            } else {
                RealtimeLogger::getInstance().log("PANIC SWITCH RELEASED: Resuming normal outputs.");
            }
        }
    }

    bool isFadeToBlackActive() const noexcept {
        return ftbActive.load(std::memory_order_acquire);
    }

private:
    PanicSwitch() = default;

    std::atomic<bool> ftbActive{false};
};
