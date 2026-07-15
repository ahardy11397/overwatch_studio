#include "ExternalControlSurfaceManager.h"
#include <osc/OscReceivedElements.h>
#include <osc/OscPacketListener.h>
#include <ip/UdpSocket.h>
#include <iostream>
#include <vector>
#include <string_view>
#include <charconv>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <wincrypt.h>
#include <mmeapi.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <vector>

#pragma comment(lib, "ws2_32.lib")

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

// MIDI input callback — called by Windows MME from the MIDI input thread
static void CALLBACK midiInCallback(HMIDIIN hMidiIn, UINT wMsg, DWORD_PTR dwInstance,
                                     DWORD_PTR dwParam1, DWORD_PTR dwParam2) {
    (void)hMidiIn;
    (void)dwParam2;
    if (wMsg != MIM_DATA) return;

    auto* owner = reinterpret_cast<ExternalControlSurfaceManager*>(dwInstance);
    DWORD midiMsg = static_cast<DWORD>(dwParam1);

    BYTE status = LOBYTE(LOWORD(midiMsg));
    BYTE data1 = HIBYTE(LOWORD(midiMsg));
    BYTE data2 = LOBYTE(HIWORD(midiMsg));

    BYTE channel = status & 0x0F;
    BYTE msgType = status & 0xF0;

    switch (msgType) {
        case 0xB0: { // Control Change
            BYTE cc = data1;
            BYTE value = data2;
            float normVal = static_cast<float>(value) / 127.0f;

            // Map CC numbers to channels/controls
            // CC 0-7: channel faders (ch 1-8)
            // CC 16-23: channel mutes (ch 1-8)
            // CC 80-87: DCA faders (ch 1-8)
            // CC 90: Master fader
            if (cc <= 7) {
                int chIdx = static_cast<int>(cc);
                owner->queueCommand({ ControlCommand::VOLUME, ControlCommand::MIDI, chIdx, normVal });
                char buf[128];
                snprintf(buf, sizeof(buf), "MIDI: CC%d (CH%d) -> ch%d volume = %.2f", cc, channel + 1, chIdx + 1, normVal);
                owner->updateLog(buf);
            } else if (cc >= 16 && cc <= 23) {
                int chIdx = static_cast<int>(cc - 16);
                bool mute = value >= 64;
                owner->queueCommand({ ControlCommand::MUTE, ControlCommand::MIDI, chIdx, mute ? 1.0f : 0.0f });
                char buf[128];
                snprintf(buf, sizeof(buf), "MIDI: CC%d (CH%d) -> ch%d mute = %s", cc, channel + 1, chIdx + 1, mute ? "ON" : "OFF");
                owner->updateLog(buf);
            } else if (cc >= 80 && cc <= 87) {
                int dcaIdx = static_cast<int>(cc - 80);
                owner->queueCommand({ ControlCommand::VOLUME, ControlCommand::MIDI, 24 + dcaIdx, normVal });
                char buf[128];
                snprintf(buf, sizeof(buf), "MIDI: CC%d (CH%d) -> DCA%d = %.2f", cc, channel + 1, dcaIdx + 1, normVal);
                owner->updateLog(buf);
            } else if (cc == 90) {
                owner->queueCommand({ ControlCommand::VOLUME, ControlCommand::MIDI, 32, normVal }); // master
                char buf[128];
                snprintf(buf, sizeof(buf), "MIDI: CC90 (CH%d) -> master = %.2f", channel + 1, normVal);
                owner->updateLog(buf);
            }
            break;
        }
        case 0x90: { // Note On (button press)
            BYTE note = data1;
            BYTE velocity = data2;
            bool pressed = velocity > 0;

            // Map notes 0-7 to channel mutes, note 127 to panic
            if (note < 8) {
                int chIdx = static_cast<int>(note);
                owner->queueCommand({ ControlCommand::MUTE, ControlCommand::MIDI, chIdx, pressed ? 1.0f : 0.0f });
                char buf[128];
                snprintf(buf, sizeof(buf), "MIDI: Note%d -> ch%d %s", note, chIdx + 1, pressed ? "ON" : "OFF");
                owner->updateLog(buf);
            } else if (note == 127) {
                if (pressed) {
                    owner->queueCommand({ ControlCommand::PANIC, ControlCommand::MIDI, 0, 1.0f });
                    owner->updateLog("MIDI: Note127 -> PANIC");
                }
            }
            break;
        }
        default:
            break;
    }
}

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
        UINT numDevices = midiInGetNumDevs();
        if (numDevices == 0) {
            updateLog("MIDI: No MIDI input devices found.");
            return;
        }

        // Open the first available MIDI input device
        HMIDIIN hMidiIn = nullptr;
        MIDIINCAPS caps;
        for (UINT i = 0; i < numDevices; ++i) {
            if (midiInGetDevCaps(i, &caps, sizeof(caps)) == MMSYSERR_NOERROR) {
                MMRESULT result = midiInOpen(&hMidiIn, i, reinterpret_cast<DWORD_PTR>(midiInCallback),
                                             reinterpret_cast<DWORD_PTR>(this), CALLBACK_FUNCTION);
                if (result == MMSYSERR_NOERROR) {
                    char buf[256];
                    char deviceName[64];
                    WideCharToMultiByte(CP_UTF8, 0, caps.szPname, -1, deviceName, sizeof(deviceName), nullptr, nullptr);
                    snprintf(buf, sizeof(buf), "MIDI: Opened device %d — %s", i, deviceName);
                    updateLog(buf);
                    break;
                }
            }
        }

        if (!hMidiIn) {
            updateLog("MIDI: Failed to open any MIDI input device.");
            return;
        }

        midiInStart(hMidiIn);

        // Block until stop requested
        while (!stopToken.stop_requested()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }

        midiInStop(hMidiIn);
        midiInClose(hMidiIn);
        updateLog("MIDI: Device closed.");
    });

    wsThread = std::jthread([this](std::stop_token stopToken) {
        // Initialize Winsock
        WSADATA wsaData;
        if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
            updateLog("WebSocket: WSAStartup failed.");
            return;
        }

        SOCKET listenSock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if (listenSock == INVALID_SOCKET) {
            updateLog("WebSocket: Failed to create socket.");
            WSACleanup();
            return;
        }

        // Allow address reuse
        int optVal = 1;
        setsockopt(listenSock, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&optVal), sizeof(optVal));

        sockaddr_in addr = {};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK); // localhost only
        addr.sin_port = htons(8100);

        if (bind(listenSock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == SOCKET_ERROR) {
            updateLog("WebSocket: Failed to bind to port 8100.");
            closesocket(listenSock);
            WSACleanup();
            return;
        }

        if (listen(listenSock, 4) == SOCKET_ERROR) {
            updateLog("WebSocket: Failed to listen.");
            closesocket(listenSock);
            WSACleanup();
            return;
        }

        updateLog("WebSocket: Listening on localhost:8100 for Stream Deck connections.");

        // Set non-blocking for stop checking
        u_long nonBlocking = 1;
        ioctlsocket(listenSock, FIONBIO, &nonBlocking);

        std::vector<SOCKET> clients;

        while (!stopToken.stop_requested()) {
            // Accept new connections
            sockaddr_in clientAddr = {};
            int clientAddrLen = sizeof(clientAddr);
            SOCKET clientSock = accept(listenSock, reinterpret_cast<sockaddr*>(&clientAddr), &clientAddrLen);
            if (clientSock != INVALID_SOCKET) {
                // Read HTTP upgrade request
                char buf[4096];
                int bytesRecv = recv(clientSock, buf, sizeof(buf) - 1, 0);
                if (bytesRecv > 0) {
                    buf[bytesRecv] = '\0';
                    std::string request(buf);

                    // Check for WebSocket upgrade
                    if (request.find("Upgrade: websocket") != std::string::npos ||
                        request.find("Upgrade: WebSocket") != std::string::npos) {

                        // Extract Sec-WebSocket-Key
                        size_t keyPos = request.find("Sec-WebSocket-Key: ");
                        if (keyPos != std::string::npos) {
                            keyPos += 19;
                            size_t keyEnd = request.find("\r\n", keyPos);
                            std::string key = request.substr(keyPos, keyEnd - keyPos);

                            // Compute accept key: SHA1(key + magic) base64'd
                            static const char* magic = "258EAFA5-E914-47DA-95CA-5AB9D111B111";
                            std::string acceptInput = key + magic;

                            // Simple SHA1 implementation
                            unsigned char sha1Hash[20];
                            // Using Windows CryptoAPI for SHA1
                            HCRYPTPROV hProv = 0;
                            HCRYPTHASH hHash = 0;
                            CryptAcquireContext(&hProv, nullptr, nullptr, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT);
                            CryptCreateHash(hProv, CALG_SHA1, 0, 0, &hHash);
                            CryptHashData(hHash, reinterpret_cast<const BYTE*>(acceptInput.data()),
                                         static_cast<DWORD>(acceptInput.size()), 0);
                            DWORD hashLen = 20;
                            CryptGetHashParam(hHash, HP_HASHVAL, sha1Hash, &hashLen, 0);
                            CryptDestroyHash(hHash);
                            CryptReleaseContext(hProv, 0);

                            // Base64 encode
                            static const char b64chars[] =
                                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
                            std::string acceptKey;
                            for (int i = 0; i < 20; i += 3) {
                                unsigned int triple = (static_cast<unsigned int>(sha1Hash[i]) << 16) |
                                                     (static_cast<unsigned int>(sha1Hash[i + 1]) << 8) |
                                                     (static_cast<unsigned int>(sha1Hash[i + 2]));
                                acceptKey += b64chars[(triple >> 18) & 0x3F];
                                acceptKey += b64chars[(triple >> 12) & 0x3F];
                                acceptKey += b64chars[(triple >> 6) & 0x3F];
                                acceptKey += b64chars[triple & 0x3F];
                            }
                            // Fix padding
                            if (acceptKey.size() > 2) {
                                acceptKey[acceptKey.size() - 1] = '=';
                                acceptKey[acceptKey.size() - 2] = '=';
                            }

                            // Send handshake response
                            std::string response =
                                "HTTP/1.1 101 Switching Protocols\r\n"
                                "Upgrade: websocket\r\n"
                                "Connection: Upgrade\r\n"
                                "Sec-WebSocket-Accept: " + acceptKey + "\r\n\r\n";
                            send(clientSock, response.c_str(), static_cast<int>(response.size()), 0);

                            clients.push_back(clientSock);
                            adjustStreamDeckClients(1);

                            char logBuf[128];
                            snprintf(logBuf, sizeof(logBuf), "WebSocket: Stream Deck client connected (total: %d)",
                                     static_cast<int>(clients.size()));
                            updateLog(logBuf);
                        }
                    }
                }
            }

            // Read from existing clients
            for (auto it = clients.begin(); it != clients.end(); ) {
                char frameBuf[4096];
                int bytesRecv = recv(*it, frameBuf, sizeof(frameBuf), 0);
                if (bytesRecv > 0 && bytesRecv >= 2) {
                    // Parse WebSocket frame
                    unsigned char* data = reinterpret_cast<unsigned char*>(frameBuf);
                    bool fin = (data[0] & 0x80) != 0;
                    uint8_t opcode = data[0] & 0x0F;
                    bool masked = (data[1] & 0x80) != 0;
                    uint64_t payloadLen = data[1] & 0x7F;
                    size_t offset = 2;

                    if (payloadLen == 126) {
                        payloadLen = (static_cast<uint64_t>(data[2]) << 8) | data[3];
                        offset = 4;
                    } else if (payloadLen == 127) {
                        payloadLen = 0;
                        for (int i = 0; i < 8; ++i) {
                            payloadLen = (payloadLen << 8) | data[2 + i];
                        }
                        offset = 10;
                    }

                    unsigned char mask[4] = {};
                    if (masked) {
                        memcpy(mask, data + offset, 4);
                        offset += 4;
                    }

                    // Unmask payload
                    std::string payload;
                    payload.reserve(static_cast<size_t>(payloadLen));
                    for (uint64_t i = 0; i < payloadLen && (offset + i) < static_cast<uint64_t>(bytesRecv); ++i) {
                        payload += static_cast<char>(data[offset + i] ^ mask[i % 4]);
                    }

                    if (opcode == 0x01 && fin) { // Text frame
                        // Basic Stream Deck JSON parsing (no external JSON library)
                        // Look for "event" field
                        std::string msg = payload;
                        if (msg.find("\"event\":\"keyDown\"") != std::string::npos ||
                            msg.find("\"event\": \"keyDown\"") != std::string::npos) {
                            // Extract "action" or "context" to identify which button
                            int keyIdx = -1;
                            size_t pos = msg.find("\"coordinates\":");
                            if (pos != std::string::npos) {
                                size_t rowPos = msg.find("\"row\":", pos);
                                size_t colPos = msg.find("\"column\":", pos);
                                if (rowPos != std::string::npos && colPos != std::string::npos) {
                                    int row = 0, col = 0;
                                    auto [rPtr, rEc] = std::from_chars(
                                        msg.data() + rowPos + 6, msg.data() + msg.size(), row);
                                    auto [cPtr, cEc] = std::from_chars(
                                        msg.data() + colPos + 9, msg.data() + msg.size(), col);
                                    if (rEc == std::errc() && cEc == std::errc()) {
                                        keyIdx = row * 8 + col;
                                    }
                                }
                            }
                            if (keyIdx >= 0) {
                                queueCommand({ ControlCommand::CUE_TRIGGER, ControlCommand::STREAM_DECK,
                                              keyIdx, 1.0f });
                                char logBuf[128];
                                snprintf(logBuf, sizeof(logBuf), "WebSocket: Stream Deck keyDown [%d]", keyIdx);
                                updateLog(logBuf);
                            }
                        } else if (msg.find("\"event\":\"keyUp\"") != std::string::npos ||
                                   msg.find("\"event\": \"keyUp\"") != std::string::npos) {
                            // Key release — could use for toggle logic
                        }
                    } else if (opcode == 0x08) { // Close frame
                        closesocket(*it);
                        it = clients.erase(it);
                        adjustStreamDeckClients(-1);
                        continue;
                    }
                } else if (bytesRecv == 0 || bytesRecv == SOCKET_ERROR) {
                    closesocket(*it);
                    it = clients.erase(it);
                    adjustStreamDeckClients(-1);
                    continue;
                }
                ++it;
            }

            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }

        // Cleanup
        for (SOCKET s : clients) closesocket(s);
        closesocket(listenSock);
        WSACleanup();
        updateLog("WebSocket: Server shut down.");
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
