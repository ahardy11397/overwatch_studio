// Touch for Task 1: Summing Engine & C++ Device Selector
#include "AudioEngineBridge.h"
#include <windows.h>
#include <tlhelp32.h>
#include <timeapi.h>
#pragma comment(lib, "winmm.lib")
#include "../core/audio/AudioEngineCore.h"
#include "../core/control/PanicSwitch.h"
#include "../core/control/SystemWatchdog.h"
#include "../core/control/DeviceReclamationEngine.h"
#include "../core/control/ResourceShedder.h"
#include "../core/control/StateHistoryEngine.h"
#include "../core/control/ExternalControlSurfaceManager.h"
#include "../core/control/RealtimeLogger.h"
#include <cstdlib>
#include <cmath>
#include <QDebug>
#include <QDateTime>

AudioEngineBridge::AudioEngineBridge(QObject* parent) 
    : QObject(parent), dspToUiQueue(1024) {
    
    // Initialize COM
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);

    // Enumerate active capture and render devices
    {
        IMMDeviceEnumerator* enumerator = nullptr;
        HRESULT hr = CoCreateInstance(
            __uuidof(MMDeviceEnumerator),
            nullptr,
            CLSCTX_ALL,
            __uuidof(IMMDeviceEnumerator),
            (void**)&enumerator
        );

        if (SUCCEEDED(hr) && enumerator) {
            // Enumerate Capture endpoints
            IMMDeviceCollection* captureCollection = nullptr;
            hr = enumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE, &captureCollection);
            if (SUCCEEDED(hr) && captureCollection) {
                UINT count = 0;
                captureCollection->GetCount(&count);
                UINT maxCapture = (count < 8) ? count : 8;
                for (UINT i = 0; i < maxCapture; ++i) {
                    IMMDevice* device = nullptr;
                    if (SUCCEEDED(captureCollection->Item(i, &device)) && device) {
                        auto worker = std::make_unique<WASAPIDeviceWorker>(device, WASAPIDeviceWorker::Mode::Capture);
                        if (worker->start()) {
                            m_captureWorkers.push_back(std::move(worker));
                        }
                        device->Release();
                    }
                }
                captureCollection->Release();
            }

            // Enumerate Render endpoints
            IMMDeviceCollection* renderCollection = nullptr;
            hr = enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &renderCollection);
            if (SUCCEEDED(hr) && renderCollection) {
                UINT count = 0;
                renderCollection->GetCount(&count);
                UINT maxRender = (count < 4) ? count : 4;
                for (UINT i = 0; i < maxRender; ++i) {
                    IMMDevice* device = nullptr;
                    if (SUCCEEDED(renderCollection->Item(i, &device)) && device) {
                        auto worker = std::make_unique<WASAPIDeviceWorker>(device, WASAPIDeviceWorker::Mode::Render);
                        if (worker->start()) {
                            m_renderWorkers.push_back(std::move(worker));
                        }
                        device->Release();
                    }
                }
                renderCollection->Release();
            }

            enumerator->Release();
        }
    }
    
    m_recorderManager = std::make_unique<AudioRecorderManager>();
    m_recorderManager->initialize(24, "recording_session_" + QDateTime::currentDateTime().toString("yyyy-MM-dd_hhmmss").toStdString());
    m_engine = std::make_unique<AudioEngineCore>();
    m_engine->setRecorder(m_recorderManager.get());

    m_running = true;
    m_simulatedAudioThread = std::jthread([this](std::stop_token stopToken) {
        // Set Windows timer resolution to 1ms for high-precision sleep
        timeBeginPeriod(1);

        std::vector<float> inputBuffers(24 * 256, 0.0f);
        std::vector<float> outputBuffers(8 * 256, 0.0f);
        std::vector<const float*> inputPtrs(24);
        for (size_t ch = 0; ch < 24; ++ch) {
            inputPtrs[ch] = &inputBuffers[ch * 256];
        }
        std::vector<float*> outputPtrs(8);
        for (size_t ch = 0; ch < 8; ++ch) {
            outputPtrs[ch] = &outputBuffers[ch * 256];
        }
        
        size_t sampleCounter = 0;
        auto nextFrameTime = std::chrono::steady_clock::now();
        const auto frameDuration = std::chrono::microseconds(5333); // 256 samples @ 48kHz

        while (!stopToken.stop_requested() && m_running.load()) {
            // 1. Thread pacing
            if (!m_captureWorkers.empty()) {
                // Active Capture: block until we have at least 256 samples captured
                size_t buffered = m_captureWorkers[0]->getBufferedSampleCount();
                if (buffered < 256) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(1));
                    continue;
                }
            } else {
                // Silent/Mock Pacing: Sleep/Yield precisely for 5.333ms frame intervals
                nextFrameTime += frameDuration;
                auto now = std::chrono::steady_clock::now();
                if (now < nextFrameTime) {
                    auto sleepTime = std::chrono::duration_cast<std::chrono::milliseconds>(nextFrameTime - now);
                    if (sleepTime.count() > 1) {
                        std::this_thread::sleep_for(sleepTime - std::chrono::milliseconds(1));
                    }
                    while (std::chrono::steady_clock::now() < nextFrameTime) {
                        std::this_thread::yield();
                    }
                } else if (now - nextFrameTime > std::chrono::milliseconds(100)) {
                    nextFrameTime = now;
                }
            }

            // 2. Read capture buffers
            size_t numCaptureDevices = m_captureWorkers.size();
            for (size_t d = 0; d < numCaptureDevices && d < 8; ++d) {
                float* ch0Buf = &inputBuffers[(2 * d) * 256];
                float* ch1Buf = &inputBuffers[(2 * d + 1) * 256];
                
                m_captureWorkers[d]->readCapturedSamples(ch0Buf, 256);
                std::copy(ch0Buf, ch0Buf + 256, ch1Buf);
            }

            size_t firstRemainingChannel = 2 * numCaptureDevices;
            for (size_t ch = firstRemainingChannel; ch < 24; ++ch) {
                float* chBuf = &inputBuffers[ch * 256];
                for (size_t s = 0; s < 256; ++s) {
                    float t = static_cast<float>(sampleCounter + s) / 48000.0f;
                    float lfo = 0.5f + 0.5f * std::sin(2.0f * 3.14159f * 0.2f * t);
                    float freq = 440.0f + ch * 20.0f;
                    float sig = std::sin(2.0f * 3.14159f * freq * t) * lfo;
                    float whiteNoise = (((rand() % 2000) / 1000.0f) - 1.0f) * 0.05f;
                    chBuf[s] = (sig * 0.25f) + whiteNoise;
                }
            }

            sampleCounter += 256;
            if (sampleCounter >= 48000 * 60) {
                sampleCounter = 0;
            }
            SystemWatchdog::getInstance().registerAudioCallback();
            
            if (m_engine) {
                m_engine->audioDeviceIOCallbackWithContext(
                    inputPtrs.data(), 24,
                    outputPtrs.data(), 8,
                    256, nullptr
                );
            }

            // 3. Write render buffers
            size_t numRenderDevices = m_renderWorkers.size();
            for (size_t r = 0; r < numRenderDevices && r < 4; ++r) {
                const float* ch0Buf = &outputBuffers[(2 * r) * 256];
                const float* ch1Buf = &outputBuffers[(2 * r + 1) * 256];
                std::vector<float> mixBuffer(256);
                for (size_t s = 0; s < 256; ++s) {
                    mixBuffer[s] = (ch0Buf[s] + ch1Buf[s]) * 0.5f;
                }
                m_renderWorkers[r]->writeRenderSamples(mixBuffer.data(), 256);
            }
        }
        
        timeEndPeriod(1);
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

    // Initialize m_uiInputPatches to 24 slots
    for (int i = 0; i < 24; ++i) {
        InputPatchUI patch;
        patch.channelIdx = i;
        if (i < 16) {
            patch.type = 1; // HW
            patch.index = i;
        } else {
            patch.type = 0; // None
            patch.index = 0;
        }
        m_uiInputPatches.append(patch);
        pushCommand(RoutingCommand{
            RoutingCommandType::SetInputPatch,
            static_cast<uint32_t>(i),
            static_cast<uint32_t>(patch.type),
            0.0f,
            static_cast<uint32_t>(patch.index)
        });
    }

    // Initialize m_uiOutputPatches to 8 slots
    for (int i = 0; i < 8; ++i) {
        OutputPatchUI patch;
        patch.hwOutputIdx = i;
        patch.busIdx = i;
        patch.active = true;
        m_uiOutputPatches.append(patch);
        pushCommand(RoutingCommand{
            RoutingCommandType::SetOutputPatch,
            static_cast<uint32_t>(i),
            static_cast<uint32_t>(i),
            0.0f,
            1U
        });
    }

    // Initialize peaks backing fields
    for (int i = 0; i < 24; ++i) m_channelPeaks.append(0.0);
    for (int i = 0; i < 8; ++i) m_busPeaks.append(0.0);

    // Setup default startup routes: route all 24 channels to Bus 0 (MST L) and Bus 1 (MST R) post-fader
    for (int i = 0; i < 24; ++i) {
        m_uiRoutes.append({i, 0, 1.0, 2});
        m_uiRoutes.append({i, 1, 1.0, 2});
        pushCommand(RoutingCommand{
            RoutingCommandType::SetRoute,
            static_cast<uint32_t>(i),
            0,
            1.0f,
            2
        });
        pushCommand(RoutingCommand{
            RoutingCommandType::SetRoute,
            static_cast<uint32_t>(i),
            1,
            1.0f,
            2
        });
    }

    refreshProcessesAsync();
}

AudioEngineBridge::~AudioEngineBridge() {
    m_running = false;
    m_simulatedAudioThread.request_stop();
    if (m_simulatedAudioThread.joinable()) {
        m_simulatedAudioThread.join();
    }
    if (m_processListThread.joinable()) {
        m_processListThread.request_stop();
        m_processListThread.join();
    }

    // Stop and clear workers
    m_captureWorkers.clear();
    m_renderWorkers.clear();

    // Explicitly stop all application captures to stop background threads 
    // BEFORE the engine and its queues are destroyed.
    for (int i = 0; i < 32; ++i) {
        if (m_processCaptures[i]) {
            m_processCaptures[i]->stop();
            m_processCaptures[i].reset();
        }
    }

    ExternalControlSurfaceManager::getInstance().stop();

    CoUninitialize();
}

void AudioEngineBridge::setFaderVolume(float vol) {
    if (!qFuzzyCompare(m_faderVolume, vol)) {
        m_faderVolume = vol;
        pushCommand(RoutingCommand{
            RoutingCommandType::SetChannelVolume,
            0,
            3, // Master
            vol,
            0
        });
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
            pushCommand(RoutingCommand{
                RoutingCommandType::SetDCAVolume,
                static_cast<uint32_t>(dcaIdx),
                0,
                static_cast<float>(volume),
                0
            });
            emit dcaVolumesChanged();
        }
    }
}

void AudioEngineBridge::updateMuteGroupState(int groupIdx, bool state) {
    if (groupIdx >= 0 && groupIdx < m_dcaMutes.size()) {
        if (m_dcaMutes[groupIdx] != state) {
            m_dcaMutes[groupIdx] = state;
            pushCommand(RoutingCommand{
                RoutingCommandType::SetDCAMute,
                static_cast<uint32_t>(groupIdx),
                0,
                0.0f,
                state ? 1U : 0U
            });
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
            pushCommand(RoutingCommand{
                RoutingCommandType::SetDCAMapping,
                static_cast<uint32_t>(chIdx),
                static_cast<uint32_t>(dcaIdx),
                0.0f,
                active ? 1U : 0U
            });
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
    uint32_t actualIdx = 0;
    uint32_t type = 0; // 0=Input, 1=Bus, 2=Aux, 3=Master
    if (chIdx < 24) {
        actualIdx = chIdx;
        type = 0;
    } else if (chIdx >= 64 && chIdx < 72) {
        actualIdx = chIdx - 64;
        type = 1;
    } else if (chIdx >= 80 && chIdx < 88) {
        actualIdx = chIdx - 80;
        type = 2;
    } else {
        return;
    }

    pushCommand(RoutingCommand{
        RoutingCommandType::SetChannelVolume,
        actualIdx,
        type,
        static_cast<float>(val),
        0
    });

    QString logMsg = QString("Channel %1 Volume Target Updated -> %2").arg(chIdx + 1).arg(20 * log10(val), 0, 'f', 1) + " dB";
    qDebug() << logMsg;
}

void AudioEngineBridge::processAudioFeedback() {
    if (!m_engine) return;

    constexpr float decayFactor = 0.88f; // Peak meter smooth release decay factor

    for (int i = 0; i < 24; ++i) {
        float rawPeak = m_engine->getInputPeak(i).load(std::memory_order_relaxed);
        double current = m_channelPeaks[i];
        double next = std::max(static_cast<double>(rawPeak), current * decayFactor);
        if (next < 0.001) next = 0.0;
        m_channelPeaks[i] = next;
    }

    for (int i = 0; i < 8; ++i) {
        float rawPeak = m_engine->getBusPeak(i).load(std::memory_order_relaxed);
        double current = m_busPeaks[i];
        double next = std::max(static_cast<double>(rawPeak), current * decayFactor);
        if (next < 0.001) next = 0.0;
        m_busPeaks[i] = next;
    }

    float rawMaster = m_engine->getMasterPeak().load(std::memory_order_relaxed);
    float nextMaster = std::max(rawMaster, m_masterPeak * decayFactor);
    if (nextMaster < 0.001f) nextMaster = 0.0f;
    m_masterPeak = nextMaster;

    emit peakMeterChanged();

    m_processListCounter++;
    if (m_processListCounter >= 120) {
        m_processListCounter = 0;
        refreshProcessesAsync();
    }
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
    if (src < 0 || src >= 24 || dest < 0 || dest >= 8) {
        return;
    }
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
    pushCommand(RoutingCommand{
        RoutingCommandType::SetRoute,
        static_cast<uint32_t>(src),
        static_cast<uint32_t>(dest),
        static_cast<float>(gain),
        static_cast<uint32_t>(tapType)
    });
    emit patchesChanged();
}

void AudioEngineBridge::unpatchRoute(int src, int dest) {
    if (src < 0 || src >= 24 || dest < 0 || dest >= 8) {
        return;
    }
    for (int i = 0; i < m_uiRoutes.size(); ++i) {
        if (m_uiRoutes[i].src == src && m_uiRoutes[i].dest == dest) {
            m_uiRoutes.removeAt(i);
            break;
        }
    }
    pushCommand(RoutingCommand{
        RoutingCommandType::UnpatchRoute,
        static_cast<uint32_t>(src),
        static_cast<uint32_t>(dest),
        0.0f,
        0
    });
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

void AudioEngineBridge::setInputPatch(int channelIdx, int type, int index) {
    if (channelIdx < 0 || channelIdx >= m_uiInputPatches.size()) {
        return;
    }
    m_uiInputPatches[channelIdx].type = type;
    m_uiInputPatches[channelIdx].index = index;
    pushCommand(RoutingCommand{
        RoutingCommandType::SetInputPatch,
        static_cast<uint32_t>(channelIdx),
        static_cast<uint32_t>(type),
        0.0f,
        static_cast<uint32_t>(index)
    });
    emit patchesChanged();
}

void AudioEngineBridge::setOutputPatch(int busIdx, int hwOutputIdx, bool active) {
    if (busIdx < 0 || busIdx >= m_uiOutputPatches.size()) {
        return;
    }

    if (active && hwOutputIdx >= 0 && hwOutputIdx < 8) {
        for (int i = 0; i < m_uiOutputPatches.size(); ++i) {
            if (i != busIdx && m_uiOutputPatches[i].active && m_uiOutputPatches[i].hwOutputIdx == hwOutputIdx) {
                m_uiOutputPatches[i].active = false;
                pushCommand(RoutingCommand{
                    RoutingCommandType::SetOutputPatch,
                    static_cast<uint32_t>(hwOutputIdx),
                    static_cast<uint32_t>(i),
                    0.0f,
                    0U
                });
            }
        }
    }

    int oldHwOutputIdx = m_uiOutputPatches[busIdx].hwOutputIdx;
    bool oldActive = m_uiOutputPatches[busIdx].active;

    m_uiOutputPatches[busIdx].hwOutputIdx = hwOutputIdx;
    m_uiOutputPatches[busIdx].active = active;

    if (oldActive && oldHwOutputIdx >= 0 && oldHwOutputIdx < 8) {
        if (!active || oldHwOutputIdx != hwOutputIdx) {
            pushCommand(RoutingCommand{
                RoutingCommandType::SetOutputPatch,
                static_cast<uint32_t>(oldHwOutputIdx),
                static_cast<uint32_t>(busIdx),
                0.0f,
                0U
            });
        }
    }

    if (active && hwOutputIdx >= 0 && hwOutputIdx < 8) {
        pushCommand(RoutingCommand{
            RoutingCommandType::SetOutputPatch,
            static_cast<uint32_t>(hwOutputIdx),
            static_cast<uint32_t>(busIdx),
            0.0f,
            1U
        });
    }

    emit patchesChanged();
}

QVariantList AudioEngineBridge::getInputPatches() const {
    QVariantList res;
    for (const auto& p : m_uiInputPatches) {
        QVariantMap map;
        map["channelIdx"] = p.channelIdx;
        map["type"] = p.type;
        map["index"] = p.index;
        res.append(map);
    }
    return res;
}

QVariantList AudioEngineBridge::getOutputPatches() const {
    QVariantList res;
    for (const auto& p : m_uiOutputPatches) {
        QVariantMap map;
        map["hwOutputIdx"] = p.hwOutputIdx;
        map["busIdx"] = p.busIdx;
        map["active"] = p.active;
        res.append(map);
    }
    return res;
}

bool AudioEngineBridge::pushCommand(const RoutingCommand& cmd) {
    if (m_engine) {
        if (!m_engine->getCommandQueue().push(cmd)) {
            qWarning() << "Failed to push RoutingCommand to command queue. Type:"
                       << static_cast<int>(cmd.type);
            return false;
        }
        return true;
    }
    return false;
}

QVariantMap AudioEngineBridge::availableProcesses() const {
    return m_availableProcesses;
}

void AudioEngineBridge::refreshProcessesAsync() {
    if (m_updatingProcesses.exchange(true)) {
        return;
    }

    if (m_processListThread.joinable()) {
        m_processListThread.join();
    }

    m_processListThread = std::jthread([this](std::stop_token stopToken) {
        QVariantMap newMap;
        
        if (stopToken.stop_requested()) {
            m_updatingProcesses.store(false);
            return;
        }
        
        HANDLE hProcessSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (hProcessSnap != INVALID_HANDLE_VALUE) {
            PROCESSENTRY32W pe32;
            pe32.dwSize = sizeof(PROCESSENTRY32W);
            
            if (Process32FirstW(hProcessSnap, &pe32)) {
                static const QStringList systemExes = {
                    "svchost.exe", "services.exe", "lsass.exe", "csrss.exe", "smss.exe",
                    "wininit.exe", "winlogon.exe", "spoolsv.exe", "dwm.exe", "taskhostw.exe",
                    "conhost.exe", "dllhost.exe", "sihost.exe", "fontdrvhost.exe", "ctfmon.exe",
                    "shellexperiencehost.exe", "searchhost.exe", "runtimebroker.exe"
                };
                do {
                    if (stopToken.stop_requested()) {
                        CloseHandle(hProcessSnap);
                        m_updatingProcesses.store(false);
                        return;
                    }
                    DWORD pid = pe32.th32ProcessID;
                    if (pid <= 4) {
                        continue;
                    }
                    QString procName = QString::fromWCharArray(pe32.szExeFile);
                    if (procName.isEmpty()) {
                        continue;
                    }
                    
                    QString procNameLower = procName.toLower();
                    if (systemExes.contains(procNameLower)) {
                        continue;
                    }
                    
                    QString displayName = QString("%1 (PID: %2)").arg(procName).arg(pid);
                    newMap[displayName] = static_cast<int>(pid);
                } while (Process32NextW(hProcessSnap, &pe32));
            }
            CloseHandle(hProcessSnap);
        }
        
        if (stopToken.stop_requested()) {
            m_updatingProcesses.store(false);
            return;
        }
        
        if (newMap.isEmpty()) {
            newMap["Discord.exe (PID: 1420)"] = 1420;
            newMap["chrome.exe (PID: 9812)"] = 9812;
            newMap["spotify.exe (PID: 4322)"] = 4322;
        }
        
        QMetaObject::invokeMethod(this, [this, newMap]() {
            m_availableProcesses = newMap;
            m_updatingProcesses.store(false);
            emit processesChanged();
        });
    });
}

void AudioEngineBridge::startApplicationCapture(int channelIdx, QString processName, int pid) {
    if (channelIdx < 0 || channelIdx >= 24) return;
    
    // Stop any existing capture on this channel first
    stopApplicationCapture(channelIdx);
    
    if (m_engine) {
        auto* queue = m_engine->getAppCaptureQueue(channelIdx);
        if (queue) {
            m_processCaptures[channelIdx] = std::make_unique<WindowsProcessCapture>();
            m_processCaptures[channelIdx]->start(static_cast<DWORD>(pid), *queue);
            
            RealtimeLogger::getInstance().log("Starting process capture on CH " + std::to_string(channelIdx) + 
                                              " (" + processName.toStdString() + ", PID: " + std::to_string(pid) + ")");
        }
    }
}

void AudioEngineBridge::stopApplicationCapture(int channelIdx) {
    if (channelIdx < 0 || channelIdx >= 24) return;
    
    if (m_processCaptures[channelIdx]) {
        m_processCaptures[channelIdx]->stop();
        m_processCaptures[channelIdx].reset();
        RealtimeLogger::getInstance().log("Stopping process capture on CH " + std::to_string(channelIdx));
    }
}

void AudioEngineBridge::armRecording(bool armed) {
    if (m_recordArmed != armed) {
        m_recordArmed = armed;
        emit recordArmedChanged();
        if (m_engine) {
            m_engine->setRecordingArmed(armed);
        }
    }
}

void AudioEngineBridge::triggerRecording(bool active) {
    if (m_recordingActive != active) {
        m_recordingActive = active;
        emit recordingActiveChanged();
        if (active) {
            m_recorderManager->startSession(static_cast<uint32_t>(m_activeSampleRate));
        } else {
            m_recorderManager->stopSession();
        }
    }
}

void AudioEngineBridge::configureShowChannels(int numInputs, int numBuses, int numAuxes, int numDCAs) {
    RealtimeLogger::getInstance().log("Reconfiguring Show Channels: Ins=" + std::to_string(numInputs) +
                                      ", Buses=" + std::to_string(numBuses) +
                                      ", Auxes=" + std::to_string(numAuxes) +
                                      ", DCAs=" + std::to_string(numDCAs));
    if (m_engine) {
        m_engine->configureEngine(static_cast<size_t>(numInputs),
                                  static_cast<size_t>(numBuses),
                                  static_cast<size_t>(numAuxes),
                                  static_cast<size_t>(numDCAs));
    }
}

void AudioEngineBridge::setChannelMuted(int chIdx, bool muted) {
    uint32_t actualIdx = 0;
    uint32_t type = 0; // 0=Input, 1=Bus, 2=Aux, 3=Master
    if (chIdx < 24) {
        actualIdx = chIdx;
        type = 0;
    } else if (chIdx == 24) {
        actualIdx = 0;
        type = 3;
    } else if (chIdx >= 64 && chIdx < 72) {
        actualIdx = chIdx - 64;
        type = 1;
    } else if (chIdx >= 80 && chIdx < 88) {
        actualIdx = chIdx - 80;
        type = 2;
    } else {
        return;
    }

    pushCommand(RoutingCommand{
        RoutingCommandType::SetChannelMute,
        actualIdx,
        type,
        0.0f,
        muted ? 1U : 0U
    });
}
