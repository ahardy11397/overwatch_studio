// Touch for Task 1: Summing Engine & C++ Device Selector
#include "AudioEngineBridge.h"
#include "../core/control/PanicSwitch.h"
#include "../core/control/SystemWatchdog.h"
#include "../core/control/DeviceReclamationEngine.h"
#include "../core/control/ResourceShedder.h"
#include "../core/control/StateHistoryEngine.h"
#include "../core/control/ExternalControlSurfaceManager.h"
#include "../core/control/RealtimeLogger.h"
#include <cstdlib>
#include <QDebug>

AudioEngineBridge::AudioEngineBridge(QObject* parent) 
    : QObject(parent), uiToDspQueue(1024), dspToUiQueue(1024) {
    
    m_running = true;
    m_simulatedAudioThread = std::jthread([this](std::stop_token stopToken) {
        while (!stopToken.stop_requested() && m_running.load()) {
            SystemWatchdog::getInstance().registerAudioCallback();
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }
    });

    // Start the universal control surface server engines
    ExternalControlSurfaceManager::getInstance().start();

    m_feedbackTimer = new QTimer(this);
    connect(m_feedbackTimer, &QTimer::timeout, this, &AudioEngineBridge::processAudioFeedback);
    m_feedbackTimer->start(16); // ~60fps UI updates

    // Initialize 8 DCA volumes and mutes
    for (int i = 0; i < 8; ++i) {
        m_dcaVolumes.append(1.0);
        m_dcaMutes.append(false);
    }
    
    // Initialize 24 channels of masks and DSP states
    for (int i = 0; i < 24; ++i) {
        m_channelDcaMasks.append(0);
        m_channelMuteMasks.append(0);
        m_channelSoloStates.append(false);
        m_channelSoloModes.append(false); // false = PFL, true = AFL

        m_channelTrims.append(0.0);
        m_channelPhases.append(false);
        m_channelHPFCutoffs.append(80.0);
        m_channelHPFSlopes.append(12);
        m_channelHPFBypasses.append(true);

        m_channelLPFCutoffs.append(20000.0);
        m_channelLPFSlopes.append(12);
        m_channelLPFBypasses.append(true);

        m_channelSatDrives.append(1.0);
        m_channelSatMixes.append(0.0);
        m_channelSatModes.append(0); // 0 = Tube
        m_channelSatBypasses.append(true);

        m_channelDeEsserFreqs.append(6000.0);
        m_channelDeEsserThresholds.append(-24.0);
        m_channelDeEsserBypasses.append(true);

        m_channelTransientAttacks.append(0.0);
        m_channelTransientSustains.append(0.0);
        m_channelTransientBypasses.append(true);

        m_channelEQBand0Gains.append(0.0);
        m_channelEQBand1Gains.append(0.0);
        m_channelEQBand2Gains.append(0.0);
        m_channelEQBand3Gains.append(0.0);

        m_channelEQBand0Dynamics.append(false);
        m_channelEQBand1Dynamics.append(false);
        m_channelEQBand2Dynamics.append(false);
        m_channelEQBand3Dynamics.append(false);

        m_channelCompThresholds.append(-18.0);
        m_channelCompRatios.append(4.0);
        m_channelCompMakeups.append(0.0);
        m_channelCompModes.append(0); // 0 = VCA
        m_channelCompBypasses.append(true);

        m_channelGateThresholds.append(-60.0);
        m_channelGateRanges.append(40.0);
        m_channelGateHysteresis.append(3.0);
        m_channelGateSidechains.append(false);
        m_channelGateBypasses.append(true);

        m_channelLimiterThresholds.append(-0.2);
        m_channelLimiterBypasses.append(false);

        m_channelEQBand0Freqs.append(80.0);
        m_channelEQBand1Freqs.append(400.0);
        m_channelEQBand2Freqs.append(2000.0);
        m_channelEQBand3Freqs.append(8000.0);

        m_channelEQBand0Qs.append(0.707);
        m_channelEQBand1Qs.append(0.707);
        m_channelEQBand2Qs.append(0.707);
        m_channelEQBand3Qs.append(0.707);

        m_channelEQBand0Types.append(0); // 0 = Shelf, 1 = Bell
        m_channelEQBand3Types.append(0); // 0 = Shelf, 1 = Bell

        m_channelCompAttacks.append(10.0);
        m_channelCompReleases.append(100.0);

        m_channelGateAttacks.append(2.0);
        m_channelGateReleases.append(150.0);
        m_channelGateHolds.append(50.0);
    }
}

AudioEngineBridge::~AudioEngineBridge() {
    m_running = false;
    m_simulatedAudioThread.request_stop();
    if (m_simulatedAudioThread.joinable()) {
        m_simulatedAudioThread.join();
    }
    ExternalControlSurfaceManager::getInstance().stop();
}

void AudioEngineBridge::setFaderVolume(float vol) {
    if (!qFuzzyCompare(m_faderVolume, vol)) {
        m_faderVolume = vol;
        emit faderVolumeChanged();
    }
}

void AudioEngineBridge::setFadeToBlack(bool active) {
    if (m_fadeToBlack != active) {
        m_fadeToBlack = active;
        PanicSwitch::getInstance().setFadeToBlack(active);
        emit fadeToBlackChanged();
    }
}

void AudioEngineBridge::updateDCAVolume(int dcaIdx, double volume) {
    if (dcaIdx >= 0 && dcaIdx < m_dcaVolumes.size()) {
        if (!qFuzzyCompare(m_dcaVolumes[dcaIdx], volume)) {
            m_dcaVolumes[dcaIdx] = volume;
            emit dcaVolumesChanged();
        }
    }
}

void AudioEngineBridge::updateMuteGroupState(int groupIdx, bool state) {
    if (groupIdx >= 0 && groupIdx < m_dcaMutes.size()) {
        if (m_dcaMutes[groupIdx] != state) {
            m_dcaMutes[groupIdx] = state;
            emit dcaMutesChanged();
        }
    }
}

void AudioEngineBridge::updateChannelDCAMapping(int chIdx, int dcaIdx, bool active) {
    if (chIdx >= 0 && chIdx < m_channelDcaMasks.size() && dcaIdx >= 0 && dcaIdx < 32) {
        int oldMask = m_channelDcaMasks[chIdx];
        if (active) {
            m_channelDcaMasks[chIdx] |= (1 << dcaIdx);
        } else {
            m_channelDcaMasks[chIdx] &= ~(1 << dcaIdx);
        }
        if (m_channelDcaMasks[chIdx] != oldMask) {
            emit channelDcaMasksChanged();
        }
    }
}

void AudioEngineBridge::updateChannelMuteMapping(int chIdx, int groupIdx, bool active) {
    if (chIdx >= 0 && chIdx < m_channelMuteMasks.size() && groupIdx >= 0 && groupIdx < 32) {
        int oldMask = m_channelMuteMasks[chIdx];
        if (active) {
            m_channelMuteMasks[chIdx] |= (1 << groupIdx);
        } else {
            m_channelMuteMasks[chIdx] &= ~(1 << groupIdx);
        }
        if (m_channelMuteMasks[chIdx] != oldMask) {
            emit channelMuteMasksChanged();
        }
    }
}

void AudioEngineBridge::updateChannelSoloState(int chIdx, bool active) {
    if (chIdx >= 0 && chIdx < m_channelSoloStates.size()) {
        if (m_channelSoloStates[chIdx] != active) {
            m_channelSoloStates[chIdx] = active;
            emit channelSoloStatesChanged();
        }
    }
}

void AudioEngineBridge::updateChannelSoloMode(int chIdx, bool isAFL) {
    if (chIdx >= 0 && chIdx < m_channelSoloModes.size()) {
        if (m_channelSoloModes[chIdx] != isAFL) {
            m_channelSoloModes[chIdx] = isAFL;
            emit channelSoloModesChanged();
        }
    }
}

void AudioEngineBridge::clearAllSolos() {
    bool changed = false;
    for (int i = 0; i < m_channelSoloStates.size(); ++i) {
        if (m_channelSoloStates[i]) {
            m_channelSoloStates[i] = false;
            changed = true;
        }
    }
    if (changed) {
        emit channelSoloStatesChanged();
    }
}

// DSP Update Functions
void AudioEngineBridge::updateChannelTrim(int ch, double val) {
    if (ch >= 0 && ch < 24) {
        m_channelTrims[ch] = val;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelHPF(int ch, double cutoff, int slope, bool bypass) {
    if (ch >= 0 && ch < 24) {
        m_channelHPFCutoffs[ch] = cutoff;
        m_channelHPFSlopes[ch] = slope;
        m_channelHPFBypasses[ch] = bypass;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelHPF(int ch, double cutoff, bool bypass) {
    updateChannelHPF(ch, cutoff, m_channelHPFSlopes[ch], bypass);
}

void AudioEngineBridge::updateChannelLPF(int ch, double cutoff, int slope, bool bypass) {
    if (ch >= 0 && ch < 24) {
        m_channelLPFCutoffs[ch] = cutoff;
        m_channelLPFSlopes[ch] = slope;
        m_channelLPFBypasses[ch] = bypass;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelPhase(int ch, bool invert) {
    if (ch >= 0 && ch < 24) {
        m_channelPhases[ch] = invert;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelSaturation(int ch, double drive, double mix, int mode, bool bypass) {
    if (ch >= 0 && ch < 24) {
        m_channelSatDrives[ch] = drive;
        m_channelSatMixes[ch] = mix;
        m_channelSatModes[ch] = mode;
        m_channelSatBypasses[ch] = bypass;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelDeEsser(int ch, double freq, double thresh, bool bypass) {
    if (ch >= 0 && ch < 24) {
        m_channelDeEsserFreqs[ch] = freq;
        m_channelDeEsserThresholds[ch] = thresh;
        m_channelDeEsserBypasses[ch] = bypass;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelTransient(int ch, double attack, double sustain, bool bypass) {
    if (ch >= 0 && ch < 24) {
        m_channelTransientAttacks[ch] = attack;
        m_channelTransientSustains[ch] = sustain;
        m_channelTransientBypasses[ch] = bypass;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelEQ(int ch, int band, double gain) {
    if (ch >= 0 && ch < 24) {
        if (band == 0) m_channelEQBand0Gains[ch] = gain;
        else if (band == 1) m_channelEQBand1Gains[ch] = gain;
        else if (band == 2) m_channelEQBand2Gains[ch] = gain;
        else if (band == 3) m_channelEQBand3Gains[ch] = gain;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelEQFreq(int ch, int band, double freq) {
    if (ch >= 0 && ch < 24) {
        if (band == 0) m_channelEQBand0Freqs[ch] = freq;
        else if (band == 1) m_channelEQBand1Freqs[ch] = freq;
        else if (band == 2) m_channelEQBand2Freqs[ch] = freq;
        else if (band == 3) m_channelEQBand3Freqs[ch] = freq;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelEQQ(int ch, int band, double q) {
    if (ch >= 0 && ch < 24) {
        if (band == 0) m_channelEQBand0Qs[ch] = q;
        else if (band == 1) m_channelEQBand1Qs[ch] = q;
        else if (band == 2) m_channelEQBand2Qs[ch] = q;
        else if (band == 3) m_channelEQBand3Qs[ch] = q;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelEQDynamic(int ch, int band, bool active) {
    if (ch >= 0 && ch < 24) {
        if (band == 0) m_channelEQBand0Dynamics[ch] = active;
        else if (band == 1) m_channelEQBand1Dynamics[ch] = active;
        else if (band == 2) m_channelEQBand2Dynamics[ch] = active;
        else if (band == 3) m_channelEQBand3Dynamics[ch] = active;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelEQType(int ch, int band, int type) {
    if (ch >= 0 && ch < 24) {
        if (band == 0) m_channelEQBand0Types[ch] = type;
        else if (band == 3) m_channelEQBand3Types[ch] = type;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelCompressor(int ch, double thresh, double ratio, double makeup, int mode, bool bypass) {
    updateChannelCompressor(ch, thresh, ratio, makeup, m_channelCompAttacks[ch], m_channelCompReleases[ch], mode, bypass);
}

void AudioEngineBridge::updateChannelCompressor(int ch, double thresh, double ratio, double makeup, bool bypass) {
    updateChannelCompressor(ch, thresh, ratio, makeup, m_channelCompAttacks[ch], m_channelCompReleases[ch], m_channelCompModes[ch], bypass);
}

void AudioEngineBridge::updateChannelCompressor(int ch, double thresh, double ratio, double makeup, double attack, double release, int mode, bool bypass) {
    if (ch >= 0 && ch < 24) {
        m_channelCompThresholds[ch] = thresh;
        m_channelCompRatios[ch] = ratio;
        m_channelCompMakeups[ch] = makeup;
        m_channelCompAttacks[ch] = attack;
        m_channelCompReleases[ch] = release;
        m_channelCompModes[ch] = mode;
        m_channelCompBypasses[ch] = bypass;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelCompressor(int ch, double thresh, double ratio, double makeup, double attack, double release, bool bypass) {
    updateChannelCompressor(ch, thresh, ratio, makeup, attack, release, m_channelCompModes[ch], bypass);
}

void AudioEngineBridge::updateChannelGate(int ch, double thresh, double range, bool bypass) {
    updateChannelGate(ch, thresh, range, m_channelGateAttacks[ch], m_channelGateReleases[ch], m_channelGateHolds[ch], m_channelGateHysteresis[ch], m_channelGateSidechains[ch], bypass);
}

void AudioEngineBridge::updateChannelGate(int ch, double thresh, double range, double hysteresis, bool filterSidechain, bool bypass) {
    updateChannelGate(ch, thresh, range, m_channelGateAttacks[ch], m_channelGateReleases[ch], m_channelGateHolds[ch], hysteresis, filterSidechain, bypass);
}

void AudioEngineBridge::updateChannelGate(int ch, double thresh, double range, double attack, double release, double hold, double hysteresis, bool filterSidechain, bool bypass) {
    if (ch >= 0 && ch < 24) {
        m_channelGateThresholds[ch] = thresh;
        m_channelGateRanges[ch] = range;
        m_channelGateAttacks[ch] = attack;
        m_channelGateReleases[ch] = release;
        m_channelGateHolds[ch] = hold;
        m_channelGateHysteresis[ch] = hysteresis;
        m_channelGateSidechains[ch] = filterSidechain;
        m_channelGateBypasses[ch] = bypass;
        emit dspChanged();
    }
}

void AudioEngineBridge::updateChannelGate(int ch, double thresh, double range, double attack, double release, double hold, bool bypass) {
    updateChannelGate(ch, thresh, range, attack, release, hold, m_channelGateHysteresis[ch], m_channelGateSidechains[ch], bypass);
}

void AudioEngineBridge::updateChannelLimiter(int ch, double thresh, bool bypass) {
    if (ch >= 0 && ch < 24) {
        m_channelLimiterThresholds[ch] = thresh;
        m_channelLimiterBypasses[ch] = bypass;
        emit dspChanged();
    }
}

// Simulated core operations
void AudioEngineBridge::captureUndoSnapshot(QVariantList channelVolumes, double masterVolume, int activeBank, int programCamera, int previewCamera) {
    m_historySize = qMin(m_historySize + 1, 10);
    emit historySizeChanged();
}

void AudioEngineBridge::triggerUndo(int step, QVariantList channelVolumes, double masterVolume) {
    m_undoActive = true;
    emit undoActiveChanged();
    QTimer::singleShot(200, this, [this]() {
        m_undoActive = false;
        emit undoActiveChanged();
    });
}

void AudioEngineBridge::simulateOSCFader(int ch, double val) {
    m_lastControlSurface = "OSC Input";
    m_lastControlSurfaceMsg = QString("OSC Fader /channel/%1/volume: %2").arg(ch).arg(val, 0, 'f', 2);
    emit controlSurfaceChanged();
}

void AudioEngineBridge::simulateMIDIFader(int ch, double val) {
    m_lastControlSurface = "MIDI Input";
    m_lastControlSurfaceMsg = QString("MIDI CC 7 (Volume) Channel %1: %2").arg(ch + 1).arg(static_cast<int>(val * 127));
    emit controlSurfaceChanged();
}

void AudioEngineBridge::simulateStreamDeckCue(int val) {
    m_lastControlSurface = "StreamDeck App";
    m_lastControlSurfaceMsg = QString("StreamDeck Button press: CUE %1").arg(val);
    emit controlSurfaceChanged();
}

void AudioEngineBridge::adjustStreamDeckClients(int val) {
    m_streamDeckClients = qMax(0, m_streamDeckClients + val);
    emit controlSurfaceChanged();
}

void AudioEngineBridge::simulateDeviceFailure() {
    m_usingFallback = true;
    m_activeDevice = "Fallback DirectSound Driver [HOT-SWAP FAILOVER]";
    emit activeDeviceChanged();
}

void AudioEngineBridge::recoverDevice() {
    m_usingFallback = false;
    m_activeDevice = "Primary ASIO Driver";
    emit activeDeviceChanged();
}

void AudioEngineBridge::setSheddingLevel(int level) {
    m_sheddingLevel = level;
    ResourceShedder::getInstance().setSheddingLevel(level);
    emit sheddingLevelChanged();
}

void AudioEngineBridge::notifyFaderChanged(int chIdx, double val) {
    // Notify control surfaces
    QString logMsg = QString("Channel %1 Volume Target Updated -> %2").arg(chIdx + 1).arg(20 * log10(val), 0, 'f', 1) + " dB";
    qDebug() << logMsg;
}

void AudioEngineBridge::processAudioFeedback() {
    // Simulate real-time level feedback
    static double angle = 0.0;
    angle += 0.05;
    m_peakMeter = static_cast<float>(0.3 + 0.1 * std::sin(angle));
    emit peakMeterChanged();
}

void AudioEngineBridge::setActiveSampleRate(int rate) {
    if (m_activeSampleRate != rate) {
        m_activeSampleRate = rate;
        emit deviceSettingsChanged();
    }
}

void AudioEngineBridge::setActiveBufferSize(int size) {
    if (m_activeBufferSize != size) {
        m_activeBufferSize = size;
        emit deviceSettingsChanged();
    }
}

void AudioEngineBridge::patchRoute(int src, int dest, double gain, int tapType) {
    // 1. Thread-safe SPSC serialization command
    // In physical system, we push a command to the DSP queue:
    // RoutingCommand cmd{ RoutingCommandType::SetRoute, (uint32_t)src, (uint32_t)dest, (float)gain, (TapPoint)tapType };
    // uiToDspQueue.enqueue(cmd);

    // 2. Synchronize UI list for QML rendering
    bool found = false;
    for (int i = 0; i < m_uiRoutes.size(); ++i) {
        if (m_uiRoutes[i].src == src && m_uiRoutes[i].dest == dest) {
            m_uiRoutes[i].gain = gain;
            m_uiRoutes[i].tap = tapType;
            found = true;
            break;
        }
    }
    if (!found) {
        m_uiRoutes.append({src, dest, gain, tapType});
    }
    emit patchesChanged();
}

void AudioEngineBridge::unpatchRoute(int src, int dest) {
    for (int i = 0; i < m_uiRoutes.size(); ++i) {
        if (m_uiRoutes[i].src == src && m_uiRoutes[i].dest == dest) {
            m_uiRoutes.removeAt(i);
            break;
        }
    }
    emit patchesChanged();
}

void AudioEngineBridge::configureDevice(QString driver, QString deviceName, int sampleRate, int bufferSize) {
    m_activeDevice = deviceName;
    m_activeSampleRate = sampleRate;
    m_activeBufferSize = bufferSize;
    emit activeDeviceChanged();
    emit deviceSettingsChanged();
    RealtimeLogger::getInstance().log("Audio Device configured successfully: " + deviceName.toStdString());
}

QVariantList AudioEngineBridge::getActivePatches() const {
    QVariantList res;
    for (const auto& r : m_uiRoutes) {
        QVariantMap map;
        map["src"] = r.src;
        map["dest"] = r.dest;
        map["gain"] = r.gain;
        map["tap"] = r.tap;
        res.append(map);
    }
    return res;
}

QVariantMap AudioEngineBridge::availableProcesses() const {
    QVariantMap map;
    map["Discord.exe"] = 1420;
    map["chrome.exe"] = 9812;
    map["spotify.exe"] = 4322;
    return map;
}

void AudioEngineBridge::startApplicationCapture(int channelIdx, QString processName, int pid) {
    if (channelIdx < 0 || channelIdx >= 32) return;
    
    // Stop any existing capture on this channel first
    stopApplicationCapture(channelIdx);
    
    m_processCaptures[channelIdx] = std::make_unique<WindowsProcessCapture>();
    m_processCaptures[channelIdx]->start(static_cast<DWORD>(pid), uiToDspQueue);
    
    RealtimeLogger::getInstance().log("Starting process capture on CH " + std::to_string(channelIdx) + 
                                      " (" + processName.toStdString() + ", PID: " + std::to_string(pid) + ")");
}

void AudioEngineBridge::stopApplicationCapture(int channelIdx) {
    if (channelIdx < 0 || channelIdx >= 32) return;
    
    if (m_processCaptures[channelIdx]) {
        m_processCaptures[channelIdx]->stop();
        m_processCaptures[channelIdx].reset();
        RealtimeLogger::getInstance().log("Stopping process capture on CH " + std::to_string(channelIdx));
    }
}
