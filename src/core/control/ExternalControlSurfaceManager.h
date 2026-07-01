#pragma once

#include <string>
#include <thread>
#include <atomic>
#include <chrono>
#include <array>
#include <mutex>
#include <algorithm>
#include "SPSCQueue.h"
#include "RealtimeLogger.h"

struct alignas(64) ControlCommand {
    enum Type { VOLUME, MUTE, CUE_TRIGGER, PANIC };
    enum Source { OSC, MIDI, STREAM_DECK };

    Type type = VOLUME;
    Source source = OSC;
    int channelIndex = 0; // 0-23 (channels) or 24 (master)
    float value = 0.0f;
};

/**
 * @class ExternalControlSurfaceManager
 * @brief Thread-safe, multi-threaded translation engine for OSC, MIDI MCU, and Stream Deck WebSockets.
 */
class ExternalControlSurfaceManager {
public:
    static ExternalControlSurfaceManager& getInstance();

    void start();
    void stop();

    void adjustStreamDeckClients(int delta) {
        int target = std::max(0, m_streamDeckClients.load() + delta);
        m_streamDeckClients.store(target);

        char buf[128];
        snprintf(buf, sizeof(buf), "[WS SERVER] Stream Deck client connection delta: %d (Total: %d)", delta, target);
        updateLog(buf);
    }

    int getStreamDeckClients() const {
        return m_streamDeckClients.load();
    }

    std::string getLastLog() const {
        std::lock_guard<std::mutex> lock(logMutex);
        return m_lastLog;
    }

    void queueCommand(const ControlCommand& cmd);
    std::optional<ControlCommand> popCommand();

    void updateLog(const std::string& log);

    ~ExternalControlSurfaceManager();

private:
    ExternalControlSurfaceManager();

    std::jthread oscThread;
    std::jthread midiThread;
    std::jthread wsThread;
    std::atomic<bool> running;
    std::atomic<int> m_streamDeckClients;

    mutable std::mutex logMutex;
    std::string m_lastLog;

    SPSCQueue<ControlCommand> m_commandQueue;
};
