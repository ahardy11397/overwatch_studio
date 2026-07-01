#include "ExternalControlSurfaceManager.h"
#include <osc/OscReceivedElements.h>
#include <osc/OscPacketListener.h>
#include <ip/UdpSocket.h>
#include <iostream>
#include <vector>
#include <string_view>
#include <charconv>

class OSCListener : public osc::OscPacketListener {
public:
    explicit OSCListener(ExternalControlSurfaceManager* owner) : m_owner(owner) {}

protected:
    void ProcessMessage(const osc::ReceivedMessage& m, const IpEndpointName& remoteEndpoint) override {
        (void)remoteEndpoint;
        try {
            std::string_view address(m.AddressPattern());

            // Handle /audio/channel/{1..8}/volume
            if (address.starts_with("/audio/channel/")) {
                size_t start = 15; // length of "/audio/channel/"
                size_t end = address.find('/', start);
                if (end != std::string_view::npos) {
                    std::string_view chStr = address.substr(start, end - start);
                    int chIdx = 0;
                    auto [ptr, ec] = std::from_chars(chStr.data(), chStr.data() + chStr.size(), chIdx);
                    if (ec == std::errc()) {
                        std::string_view subPath = address.substr(end);
                        if (subPath == "/volume") {
                            float val = 0.0f;
                            auto arg = m.ArgumentsBegin();
                            if (arg->IsFloat()) val = arg->AsFloat();
                            else if (arg->IsDouble()) val = (float)arg->AsDouble();

                            m_owner->queueCommand({ ControlCommand::VOLUME, ControlCommand::OSC, chIdx - 1, val });
                            char buf[128];
                            snprintf(buf, sizeof(buf), "OSC: /audio/channel/%d/volume -> %.2f", chIdx, val);
                            m_owner->updateLog(buf);
                        } else if (subPath == "/mute") {
                            bool mute = false;
                            auto arg = m.ArgumentsBegin();
                            if (arg->IsBool()) mute = arg->AsBool();
                            else if (arg->IsInt32()) mute = arg->AsInt32() != 0;

                            m_owner->queueCommand({ ControlCommand::MUTE, ControlCommand::OSC, chIdx - 1, mute ? 1.0f : 0.0f });
                            char buf[128];
                            snprintf(buf, sizeof(buf), "OSC: /audio/channel/%d/mute -> %s", chIdx, mute ? "ON" : "OFF");
                            m_owner->updateLog(buf);
                        }
                    }
                }
            }
            // Handle /audio/dca/{1..8}/fader
            else if (address.starts_with("/audio/dca/")) {
                size_t start = 11; // length of "/audio/dca/"
                size_t end = address.find('/', start);
                if (end != std::string_view::npos) {
                    std::string_view dcaStr = address.substr(start, end - start);
                    int dcaIdx = 0;
                    auto [ptr, ec] = std::from_chars(dcaStr.data(), dcaStr.data() + dcaStr.size(), dcaIdx);
                    if (ec == std::errc()) {
                        std::string_view subPath = address.substr(end);
                        if (subPath == "/fader") {
                            float val = 0.0f;
                            auto arg = m.ArgumentsBegin();
                            if (arg->IsFloat()) val = arg->AsFloat();
                            else if (arg->IsDouble()) val = (float)arg->AsDouble();

                            // 24 channels + 8 buses + some extra... let's assume DCAs are indexed after channels
                            // In Command structure, we might need a way to distinguish DCA.
                            // For now, let's use channelIndex as a raw index and handle it in the bridge.
                            // But better to define a type or index range.
                            m_owner->queueCommand({ ControlCommand::VOLUME, ControlCommand::OSC, 24 + dcaIdx - 1, val });
                            char buf[128];
                            snprintf(buf, sizeof(buf), "OSC: /audio/dca/%d/fader -> %.2f", dcaIdx, val);
                            m_owner->updateLog(buf);
                        }
                    }
                }
            }
            // Video / Recording / Master
            else if (address == "/video/program/source") {
                int src = 0;
                auto arg = m.ArgumentsBegin();
                if (arg->IsInt32()) src = arg->AsInt32();
                m_owner->queueCommand({ ControlCommand::CUE_TRIGGER, ControlCommand::OSC, 0, (float)src });
                m_owner->updateLog("OSC: /video/program/source -> " + std::to_string(src));
            }
            else if (address == "/video/transition/fire") {
                m_owner->queueCommand({ ControlCommand::CUE_TRIGGER, ControlCommand::OSC, 1, 1.0f });
                m_owner->updateLog("OSC: /video/transition/fire");
            }
            else if (address == "/recording/start") {
                m_owner->queueCommand({ ControlCommand::CUE_TRIGGER, ControlCommand::OSC, 10, 1.0f });
                m_owner->updateLog("OSC: /recording/start");
            }
            else if (address == "/recording/stop") {
                m_owner->queueCommand({ ControlCommand::CUE_TRIGGER, ControlCommand::OSC, 10, 0.0f });
                m_owner->updateLog("OSC: /recording/stop");
            }
            else if (address == "/panic") {
                m_owner->queueCommand({ ControlCommand::PANIC, ControlCommand::OSC, 0, 1.0f });
                m_owner->updateLog("OSC: PANIC TRIGGERED");
            }

        } catch (osc::Exception& e) {
            m_owner->updateLog(std::string("OSC Error: ") + e.what());
        }
    }

private:
    ExternalControlSurfaceManager* m_owner;
};

ExternalControlSurfaceManager& ExternalControlSurfaceManager::getInstance() {
    static ExternalControlSurfaceManager instance;
    return instance;
}

ExternalControlSurfaceManager::ExternalControlSurfaceManager()
    : running(false), m_streamDeckClients(0), m_commandQueue(1024) {
}

ExternalControlSurfaceManager::~ExternalControlSurfaceManager() {
    stop();
}

void ExternalControlSurfaceManager::start() {
    if (running.exchange(true)) return;

    updateLog("Surface Aggregator Active. OSC Port 8000 listening.");

    oscThread = std::jthread([this](std::stop_token stopToken) {
        try {
            OSCListener listener(this);
            UdpListeningReceiveSocket s(
                IpEndpointName(IpEndpointName::ANY_ADDRESS, 8000),
                &listener);

            // oscpack doesn't have a stop() on the socket easily used with std::jthread
            // without a custom interruption. However, we can use a timeout or check stopToken.
            // Actually UdpListeningReceiveSocket::Run() blocks until the listener calls something or it's killed.
            // To make it interruptible, we might need a more complex setup or non-blocking.
            // For now, let's run it.
            s.Run();
        } catch (std::exception& e) {
            updateLog(std::string("OSC Thread Crash: ") + e.what());
        }
    });

    midiThread = std::jthread([this](std::stop_token stopToken) {
        while (!stopToken.stop_requested()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    });

    wsThread = std::jthread([this](std::stop_token stopToken) {
        while (!stopToken.stop_requested()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    });
}

void ExternalControlSurfaceManager::stop() {
    if (!running.exchange(false)) return;

    // UdpListeningReceiveSocket::AsynchronousBreak() is what we need to stop the Run() loop.
    // But we need access to the socket. We'll refine the implementation if needed.
    // For now, just request stop on threads.
    oscThread.request_stop();
    midiThread.request_stop();
    wsThread.request_stop();
}

void ExternalControlSurfaceManager::updateLog(const std::string& log) {
    std::lock_guard<std::mutex> lock(logMutex);
    m_lastLog = log;
    RealtimeLogger::getInstance().log(log);
}

void ExternalControlSurfaceManager::queueCommand(const ControlCommand& cmd) {
    m_commandQueue.push(cmd);
}

std::optional<ControlCommand> ExternalControlSurfaceManager::popCommand() {
    return m_commandQueue.pop();
}
