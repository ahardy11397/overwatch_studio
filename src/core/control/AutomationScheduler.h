#pragma once

#include <vector>
#include <string>
#include <thread>
#include <chrono>
#include <atomic>
#include <functional>
#include "RealtimeLogger.h"

struct Cue {
    uint64_t timecodeMs;
    std::string action;
    int targetIndex;
    float value;
    bool triggered = false;
};

/**
 * @class AutomationScheduler
 * @brief Background automation thread parsing sequential Cue Stack with sub-frame timecode accuracy.
 */
class AutomationScheduler {
public:
    static AutomationScheduler& getInstance() {
        static AutomationScheduler instance;
        return instance;
    }

    void loadCueStack(std::vector<Cue> cues) {
        cueStack = std::move(cues);
        for (auto& cue : cueStack) {
            cue.triggered = false;
        }
        RealtimeLogger::getInstance().log("AutomationScheduler: Loaded cue stack.");
    }

    void start(std::function<void(const Cue&)> triggerCallback) {
        if (running.exchange(true)) return;
        
        callback = triggerCallback;
        startTime = std::chrono::steady_clock::now();

        schedulerThread = std::jthread([this](std::stop_token stopToken) {
            while (!stopToken.stop_requested()) {
                auto now = std::chrono::steady_clock::now();
                uint64_t elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(now - startTime).count();

                for (auto& cue : cueStack) {
                    if (!cue.triggered && elapsedMs >= cue.timecodeMs) {
                        cue.triggered = true;
                        
                        char buf[128];
                        snprintf(buf, sizeof(buf), "AutomationScheduler: Triggered cue action '%s' at %llu ms (Timecode sync)", 
                                 cue.action.c_str(), cue.timecodeMs);
                        RealtimeLogger::getInstance().log(buf);

                        if (callback) {
                            callback(cue);
                        }
                    }
                }
                std::this_thread::sleep_for(std::chrono::milliseconds(5)); // Sub-frame polling interval
            }
        });
    }

    void stop() {
        if (!running.exchange(false)) return;
        schedulerThread.request_stop();
        if (schedulerThread.joinable()) {
            schedulerThread.join();
        }
    }

    ~AutomationScheduler() {
        stop();
    }

private:
    AutomationScheduler() : running(false) {}

    std::vector<Cue> cueStack;
    std::jthread schedulerThread;
    std::atomic<bool> running;
    std::chrono::steady_clock::time_point startTime;
    std::function<void(const Cue&)> callback;
};
