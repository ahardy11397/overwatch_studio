#pragma once

#include <atomic>
#include <string>
#include <functional>
#include "RealtimeLogger.h"

/**
 * @class DeviceReclamationEngine
 * @brief Manages real-time audio driver failure and seamless reclamation / hot-plug redirection.
 */
class DeviceReclamationEngine {
public:
    static DeviceReclamationEngine& getInstance() {
        static DeviceReclamationEngine instance;
        return instance;
    }

    bool isUsingFallback() const noexcept {
        return usingFallback.load(std::memory_order_acquire);
    }

    std::string getActiveDeviceName() const {
        if (usingFallback.load(std::memory_order_relaxed)) {
            return "WASAPI Shared (Fallback Output)";
        }
        return "ASIO Dante Virtual Soundcard (Primary)";
    }

    /**
     * @brief Mimic a hardware hot-plug event or audio device dropout.
     * Redirects to WASAPI shared fallback seamlessly.
     */
    void triggerDeviceFailure() noexcept {
        if (usingFallback.exchange(true, std::memory_order_release) == false) {
            RealtimeLogger::getInstance().log("CRITICAL: Primary ASIO device disconnected! Redirecting to WASAPI Shared...");
            
            if (statusChangeCallback) {
                statusChangeCallback(true);
            }
        }
    }

    void recoverPrimaryDevice() noexcept {
        if (usingFallback.exchange(false, std::memory_order_release) == true) {
            RealtimeLogger::getInstance().log("INFO: Primary ASIO device reclaimed! Rerouting back to ASIO...");
            
            if (statusChangeCallback) {
                statusChangeCallback(false);
            }
        }
    }

    void setStatusChangeCallback(std::function<void(bool)> callback) {
        statusChangeCallback = callback;
    }

private:
    DeviceReclamationEngine() = default;

    std::atomic<bool> usingFallback{false};
    std::function<void(bool)> statusChangeCallback;
};
