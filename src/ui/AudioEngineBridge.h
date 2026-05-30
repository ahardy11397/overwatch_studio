// Touch for Task 1: Summing Engine & C++ Device Selector
#pragma once

#include <QObject>
#include <QTimer>
#include <QString>
#include <QList>
#include <QVariantList>
#include <thread>
#include <atomic>
#include <chrono>
#include <array>
#include "../core/control/SPSCQueue.h"

class AudioEngineBridge : public QObject {
    Q_OBJECT
    Q_PROPERTY(float faderVolume READ faderVolume WRITE setFaderVolume NOTIFY faderVolumeChanged)
    Q_PROPERTY(float peakMeter READ peakMeter NOTIFY peakMeterChanged)
    Q_PROPERTY(bool fadeToBlack READ fadeToBlack WRITE setFadeToBlack NOTIFY fadeToBlackChanged)
    Q_PROPERTY(QString activeDevice READ activeDevice NOTIFY activeDeviceChanged)
    Q_PROPERTY(int sheddingLevel READ sheddingLevel NOTIFY sheddingLevelChanged)
    Q_PROPERTY(bool usingFallback READ usingFallback NOTIFY activeDeviceChanged)
    Q_PROPERTY(int historySize READ historySize NOTIFY historySizeChanged)
    Q_PROPERTY(bool undoActive READ undoActive NOTIFY undoActiveChanged)
    Q_PROPERTY(QVariantList availableDrivers READ availableDrivers CONSTANT)
    Q_PROPERTY(QVariantList availableDevices READ availableDevices CONSTANT)
    Q_PROPERTY(int activeSampleRate READ activeSampleRate WRITE setActiveSampleRate NOTIFY deviceSettingsChanged)
    Q_PROPERTY(int activeBufferSize READ activeBufferSize WRITE setActiveBufferSize NOTIFY deviceSettingsChanged)
    
    // External Control Surface Diagnostics properties
    Q_PROPERTY(int oscPort READ oscPort CONSTANT)
    Q_PROPERTY(bool midiConnected READ midiConnected NOTIFY controlSurfaceChanged)
    Q_PROPERTY(int streamDeckClients READ streamDeckClients NOTIFY controlSurfaceChanged)
    Q_PROPERTY(QString lastControlSurface READ lastControlSurface NOTIFY controlSurfaceChanged)
    Q_PROPERTY(QString lastControlSurfaceMsg READ lastControlSurfaceMsg NOTIFY controlSurfaceChanged)

    // Lists for DCA & Mutes
    Q_PROPERTY(QList<double> dcaVolumes READ dcaVolumes NOTIFY dcaVolumesChanged)
    Q_PROPERTY(QList<bool> dcaMutes READ dcaMutes NOTIFY dcaMutesChanged)
    Q_PROPERTY(QList<int> channelDcaMasks READ channelDcaMasks NOTIFY channelDcaMasksChanged)
    Q_PROPERTY(QList<int> channelMuteMasks READ channelMuteMasks NOTIFY channelMuteMasksChanged)
    Q_PROPERTY(QList<bool> channelSoloStates READ channelSoloStates NOTIFY channelSoloStatesChanged)
    Q_PROPERTY(QList<bool> channelSoloModes READ channelSoloModes NOTIFY channelSoloModesChanged)

    // Lists for DSP Parameters
    Q_PROPERTY(QList<double> channelTrims READ channelTrims NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelPhases READ channelPhases NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelHPFCutoffs READ channelHPFCutoffs NOTIFY dspChanged)
    Q_PROPERTY(QList<int> channelHPFSlopes READ channelHPFSlopes NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelHPFBypasses READ channelHPFBypasses NOTIFY dspChanged)
    
    Q_PROPERTY(QList<double> channelLPFCutoffs READ channelLPFCutoffs NOTIFY dspChanged)
    Q_PROPERTY(QList<int> channelLPFSlopes READ channelLPFSlopes NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelLPFBypasses READ channelLPFBypasses NOTIFY dspChanged)

    Q_PROPERTY(QList<double> channelSatDrives READ channelSatDrives NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelSatMixes READ channelSatMixes NOTIFY dspChanged)
    Q_PROPERTY(QList<int> channelSatModes READ channelSatModes NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelSatBypasses READ channelSatBypasses NOTIFY dspChanged)

    Q_PROPERTY(QList<double> channelDeEsserFreqs READ channelDeEsserFreqs NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelDeEsserThresholds READ channelDeEsserThresholds NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelDeEsserBypasses READ channelDeEsserBypasses NOTIFY dspChanged)

    Q_PROPERTY(QList<double> channelTransientAttacks READ channelTransientAttacks NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelTransientSustains READ channelTransientSustains NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelTransientBypasses READ channelTransientBypasses NOTIFY dspChanged)

    Q_PROPERTY(QList<double> channelEQBand0Gains READ channelEQBand0Gains NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelEQBand1Gains READ channelEQBand1Gains NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelEQBand2Gains READ channelEQBand2Gains NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelEQBand3Gains READ channelEQBand3Gains NOTIFY dspChanged)

    Q_PROPERTY(QList<bool> channelEQBand0Dynamics READ channelEQBand0Dynamics NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelEQBand1Dynamics READ channelEQBand1Dynamics NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelEQBand2Dynamics READ channelEQBand2Dynamics NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelEQBand3Dynamics READ channelEQBand3Dynamics NOTIFY dspChanged)

    Q_PROPERTY(QList<double> channelCompThresholds READ channelCompThresholds NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelCompRatios READ channelCompRatios NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelCompMakeups READ channelCompMakeups NOTIFY dspChanged)
    Q_PROPERTY(QList<int> channelCompModes READ channelCompModes NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelCompBypasses READ channelCompBypasses NOTIFY dspChanged)

    Q_PROPERTY(QList<double> channelGateThresholds READ channelGateThresholds NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelGateRanges READ channelGateRanges NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelGateHysteresis READ channelGateHysteresis NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelGateSidechains READ channelGateSidechains NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelGateBypasses READ channelGateBypasses NOTIFY dspChanged)

    Q_PROPERTY(QList<double> channelLimiterThresholds READ channelLimiterThresholds NOTIFY dspChanged)
    Q_PROPERTY(QList<bool> channelLimiterBypasses READ channelLimiterBypasses NOTIFY dspChanged)

    Q_PROPERTY(QList<double> channelEQBand0Freqs READ channelEQBand0Freqs NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelEQBand1Freqs READ channelEQBand1Freqs NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelEQBand2Freqs READ channelEQBand2Freqs NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelEQBand3Freqs READ channelEQBand3Freqs NOTIFY dspChanged)

    Q_PROPERTY(QList<double> channelEQBand0Qs READ channelEQBand0Qs NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelEQBand1Qs READ channelEQBand1Qs NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelEQBand2Qs READ channelEQBand2Qs NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelEQBand3Qs READ channelEQBand3Qs NOTIFY dspChanged)

    Q_PROPERTY(QList<int> channelEQBand0Types READ channelEQBand0Types NOTIFY dspChanged)
    Q_PROPERTY(QList<int> channelEQBand3Types READ channelEQBand3Types NOTIFY dspChanged)

    Q_PROPERTY(QList<double> channelCompAttacks READ channelCompAttacks NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelCompReleases READ channelCompReleases NOTIFY dspChanged)

    Q_PROPERTY(QList<double> channelGateAttacks READ channelGateAttacks NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelGateReleases READ channelGateReleases NOTIFY dspChanged)
    Q_PROPERTY(QList<double> channelGateHolds READ channelGateHolds NOTIFY dspChanged)

public:
    explicit AudioEngineBridge(QObject* parent = nullptr);
    ~AudioEngineBridge() override;

    // Getters for core variables
    float faderVolume() const { return m_faderVolume; }
    void setFaderVolume(float vol);
    float peakMeter() const { return m_peakMeter; }
    bool fadeToBlack() const { return m_fadeToBlack; }
    void setFadeToBlack(bool active);
    QString activeDevice() const { return m_activeDevice; }
    int sheddingLevel() const { return m_sheddingLevel; }
    bool usingFallback() const { return m_usingFallback; }
    int historySize() const { return m_historySize; }
    bool undoActive() const { return m_undoActive; }

    QVariantList availableDrivers() const { return { "ASIO (Low-Latency)", "WASAPI Shared", "DirectSound" }; }
    QVariantList availableDevices() const { return { "Dante Virtual Soundcard", "ASIO Focusrite USB", "Built-in Sound Device" }; }
    int activeSampleRate() const { return m_activeSampleRate; }
    void setActiveSampleRate(int rate);
    int activeBufferSize() const { return m_activeBufferSize; }
    void setActiveBufferSize(int size);

    Q_INVOKABLE void patchRoute(int src, int dest, double gain, int tapType);
    Q_INVOKABLE void unpatchRoute(int src, int dest);
    Q_INVOKABLE void configureDevice(QString driver, QString deviceName, int sampleRate, int bufferSize);
    Q_INVOKABLE QVariantList getActivePatches() const;

    int oscPort() const { return 8000; }
    bool midiConnected() const { return m_midiConnected; }
    int streamDeckClients() const { return m_streamDeckClients; }
    QString lastControlSurface() const { return m_lastControlSurface; }
    QString lastControlSurfaceMsg() const { return m_lastControlSurfaceMsg; }

    // List Getters
    QList<double> dcaVolumes() const { return m_dcaVolumes; }
    QList<bool> dcaMutes() const { return m_dcaMutes; }
    QList<int> channelDcaMasks() const { return m_channelDcaMasks; }
    QList<int> channelMuteMasks() const { return m_channelMuteMasks; }
    QList<bool> channelSoloStates() const { return m_channelSoloStates; }
    QList<bool> channelSoloModes() const { return m_channelSoloModes; }

    QList<double> channelTrims() const { return m_channelTrims; }
    QList<bool> channelPhases() const { return m_channelPhases; }
    QList<double> channelHPFCutoffs() const { return m_channelHPFCutoffs; }
    QList<int> channelHPFSlopes() const { return m_channelHPFSlopes; }
    QList<bool> channelHPFBypasses() const { return m_channelHPFBypasses; }

    QList<double> channelLPFCutoffs() const { return m_channelLPFCutoffs; }
    QList<int> channelLPFSlopes() const { return m_channelLPFSlopes; }
    QList<bool> channelLPFBypasses() const { return m_channelLPFBypasses; }

    QList<double> channelSatDrives() const { return m_channelSatDrives; }
    QList<double> channelSatMixes() const { return m_channelSatMixes; }
    QList<int> channelSatModes() const { return m_channelSatModes; }
    QList<bool> channelSatBypasses() const { return m_channelSatBypasses; }

    QList<double> channelDeEsserFreqs() const { return m_channelDeEsserFreqs; }
    QList<double> channelDeEsserThresholds() const { return m_channelDeEsserThresholds; }
    QList<bool> channelDeEsserBypasses() const { return m_channelDeEsserBypasses; }

    QList<double> channelTransientAttacks() const { return m_channelTransientAttacks; }
    QList<double> channelTransientSustains() const { return m_channelTransientSustains; }
    QList<bool> channelTransientBypasses() const { return m_channelTransientBypasses; }

    QList<double> channelEQBand0Gains() const { return m_channelEQBand0Gains; }
    QList<double> channelEQBand1Gains() const { return m_channelEQBand1Gains; }
    QList<double> channelEQBand2Gains() const { return m_channelEQBand2Gains; }
    QList<double> channelEQBand3Gains() const { return m_channelEQBand3Gains; }

    QList<bool> channelEQBand0Dynamics() const { return m_channelEQBand0Dynamics; }
    QList<bool> channelEQBand1Dynamics() const { return m_channelEQBand1Dynamics; }
    QList<bool> channelEQBand2Dynamics() const { return m_channelEQBand2Dynamics; }
    QList<bool> channelEQBand3Dynamics() const { return m_channelEQBand3Dynamics; }

    QList<double> channelCompThresholds() const { return m_channelCompThresholds; }
    QList<double> channelCompRatios() const { return m_channelCompRatios; }
    QList<double> channelCompMakeups() const { return m_channelCompMakeups; }
    QList<int> channelCompModes() const { return m_channelCompModes; }
    QList<bool> channelCompBypasses() const { return m_channelCompBypasses; }

    QList<double> channelGateThresholds() const { return m_channelGateThresholds; }
    QList<double> channelGateRanges() const { return m_channelGateRanges; }
    QList<double> channelGateHysteresis() const { return m_channelGateHysteresis; }
    QList<bool> channelGateSidechains() const { return m_channelGateSidechains; }
    QList<bool> channelGateBypasses() const { return m_channelGateBypasses; }

    QList<double> channelLimiterThresholds() const { return m_channelLimiterThresholds; }
    QList<bool> channelLimiterBypasses() const { return m_channelLimiterBypasses; }

    QList<double> channelEQBand0Freqs() const { return m_channelEQBand0Freqs; }
    QList<double> channelEQBand1Freqs() const { return m_channelEQBand1Freqs; }
    QList<double> channelEQBand2Freqs() const { return m_channelEQBand2Freqs; }
    QList<double> channelEQBand3Freqs() const { return m_channelEQBand3Freqs; }

    QList<double> channelEQBand0Qs() const { return m_channelEQBand0Qs; }
    QList<double> channelEQBand1Qs() const { return m_channelEQBand1Qs; }
    QList<double> channelEQBand2Qs() const { return m_channelEQBand2Qs; }
    QList<double> channelEQBand3Qs() const { return m_channelEQBand3Qs; }

    QList<int> channelEQBand0Types() const { return m_channelEQBand0Types; }
    QList<int> channelEQBand3Types() const { return m_channelEQBand3Types; }

    QList<double> channelCompAttacks() const { return m_channelCompAttacks; }
    QList<double> channelCompReleases() const { return m_channelCompReleases; }

    QList<double> channelGateAttacks() const { return m_channelGateAttacks; }
    QList<double> channelGateReleases() const { return m_channelGateReleases; }
    QList<double> channelGateHolds() const { return m_channelGateHolds; }

    // Public Invokable Slots matching Main.qml
    Q_INVOKABLE void updateChannelTrim(int ch, double val);
    Q_INVOKABLE void updateChannelHPF(int ch, double cutoff, int slope, bool bypass);
    Q_INVOKABLE void updateChannelHPF(int ch, double cutoff, bool bypass);
    Q_INVOKABLE void updateChannelLPF(int ch, double cutoff, int slope, bool bypass);
    Q_INVOKABLE void updateChannelPhase(int ch, bool invert);
    Q_INVOKABLE void updateChannelSaturation(int ch, double drive, double mix, int mode, bool bypass);
    Q_INVOKABLE void updateChannelDeEsser(int ch, double freq, double thresh, bool bypass);
    Q_INVOKABLE void updateChannelTransient(int ch, double attack, double sustain, bool bypass);
    Q_INVOKABLE void updateChannelEQ(int ch, int band, double gain);
    Q_INVOKABLE void updateChannelEQFreq(int ch, int band, double freq);
    Q_INVOKABLE void updateChannelEQQ(int ch, int band, double q);
    Q_INVOKABLE void updateChannelEQDynamic(int ch, int band, bool active);
    Q_INVOKABLE void updateChannelEQType(int ch, int band, int type);
    Q_INVOKABLE void updateChannelCompressor(int ch, double thresh, double ratio, double makeup, int mode, bool bypass);
    Q_INVOKABLE void updateChannelCompressor(int ch, double thresh, double ratio, double makeup, bool bypass);
    Q_INVOKABLE void updateChannelCompressor(int ch, double thresh, double ratio, double makeup, double attack, double release, int mode, bool bypass);
    Q_INVOKABLE void updateChannelCompressor(int ch, double thresh, double ratio, double makeup, double attack, double release, bool bypass);
    Q_INVOKABLE void updateChannelGate(int ch, double thresh, double range, bool bypass);
    Q_INVOKABLE void updateChannelGate(int ch, double thresh, double range, double hysteresis, bool filterSidechain, bool bypass);
    Q_INVOKABLE void updateChannelGate(int ch, double thresh, double range, double attack, double release, double hold, double hysteresis, bool filterSidechain, bool bypass);
    Q_INVOKABLE void updateChannelGate(int ch, double thresh, double range, double attack, double release, double hold, bool bypass);
    Q_INVOKABLE void updateChannelLimiter(int ch, double thresh, bool bypass);

    Q_INVOKABLE void updateDCAVolume(int dcaIdx, double volume);
    Q_INVOKABLE void updateMuteGroupState(int groupIdx, bool state);
    Q_INVOKABLE void updateChannelDCAMapping(int chIdx, int dcaIdx, bool active);
    Q_INVOKABLE void updateChannelMuteMapping(int chIdx, int groupIdx, bool active);

    Q_INVOKABLE void updateChannelSoloState(int chIdx, bool active);
    Q_INVOKABLE void updateChannelSoloMode(int chIdx, bool isAFL);
    Q_INVOKABLE void clearAllSolos();

    Q_INVOKABLE void captureUndoSnapshot(QVariantList channelVolumes, double masterVolume, int activeBank, int programCamera, int previewCamera);
    Q_INVOKABLE void triggerUndo(int step, QVariantList channelVolumes, double masterVolume);

    Q_INVOKABLE void simulateOSCFader(int ch, double val);
    Q_INVOKABLE void simulateMIDIFader(int ch, double val);
    Q_INVOKABLE void simulateStreamDeckCue(int val);
    Q_INVOKABLE void adjustStreamDeckClients(int val);
    Q_INVOKABLE void simulateDeviceFailure();
    Q_INVOKABLE void recoverDevice();
    Q_INVOKABLE void setSheddingLevel(int level);
    Q_INVOKABLE void notifyFaderChanged(int chIdx, double val);

signals:
    void faderVolumeChanged();
    void peakMeterChanged();
    void fadeToBlackChanged();
    void activeDeviceChanged();
    void sheddingLevelChanged();
    void historySizeChanged();
    void undoActiveChanged();
    void controlSurfaceChanged();
    void deviceSettingsChanged();
    void patchesChanged();
    
    void dcaVolumesChanged();
    void dcaMutesChanged();
    void channelDcaMasksChanged();
    void channelMuteMasksChanged();
    void channelSoloStatesChanged();
    void channelSoloModesChanged();
    void dspChanged();

private slots:
    void processAudioFeedback();

private:
    float m_faderVolume = 0.8f;
    float m_peakMeter = 0.25f;
    bool m_fadeToBlack = false;
    QString m_activeDevice = "Primary ASIO Driver";
    int m_sheddingLevel = 0;
    bool m_usingFallback = false;
    int m_historySize = 0;
    bool m_undoActive = false;

    int m_activeSampleRate = 48000;
    int m_activeBufferSize = 128;
    struct ActiveRouteUI { int src; int dest; double gain; int tap; };
    QList<ActiveRouteUI> m_uiRoutes;

    bool m_midiConnected = true;
    int m_streamDeckClients = 2;
    QString m_lastControlSurface = "MIDI Controller 1";
    QString m_lastControlSurfaceMsg = "MIDI CC 7 (Volume) Channel 1: 85";

    QList<double> m_dcaVolumes;
    QList<bool> m_dcaMutes;
    QList<int> m_channelDcaMasks;
    QList<int> m_channelMuteMasks;
    QList<bool> m_channelSoloStates;
    QList<bool> m_channelSoloModes;

    // DSP lists
    QList<double> m_channelTrims;
    QList<bool> m_channelPhases;
    QList<double> m_channelHPFCutoffs;
    QList<int> m_channelHPFSlopes;
    QList<bool> m_channelHPFBypasses;
    
    QList<double> m_channelLPFCutoffs;
    QList<int> m_channelLPFSlopes;
    QList<bool> m_channelLPFBypasses;

    QList<double> m_channelSatDrives;
    QList<double> m_channelSatMixes;
    QList<int> m_channelSatModes;
    QList<bool> m_channelSatBypasses;

    QList<double> m_channelDeEsserFreqs;
    QList<double> m_channelDeEsserThresholds;
    QList<bool> m_channelDeEsserBypasses;

    QList<double> m_channelTransientAttacks;
    QList<double> m_channelTransientSustains;
    QList<bool> m_channelTransientBypasses;

    QList<double> m_channelEQBand0Gains;
    QList<double> m_channelEQBand1Gains;
    QList<double> m_channelEQBand2Gains;
    QList<double> m_channelEQBand3Gains;

    QList<bool> m_channelEQBand0Dynamics;
    QList<bool> m_channelEQBand1Dynamics;
    QList<bool> m_channelEQBand2Dynamics;
    QList<bool> m_channelEQBand3Dynamics;

    QList<double> m_channelCompThresholds;
    QList<double> m_channelCompRatios;
    QList<double> m_channelCompMakeups;
    QList<int> m_channelCompModes;
    QList<bool> m_channelCompBypasses;

    QList<double> m_channelGateThresholds;
    QList<double> m_channelGateRanges;
    QList<double> m_channelGateHysteresis;
    QList<bool> m_channelGateSidechains;
    QList<bool> m_channelGateBypasses;

    QList<double> m_channelLimiterThresholds;
    QList<bool> m_channelLimiterBypasses;

    QList<double> m_channelEQBand0Freqs;
    QList<double> m_channelEQBand1Freqs;
    QList<double> m_channelEQBand2Freqs;
    QList<double> m_channelEQBand3Freqs;

    QList<double> m_channelEQBand0Qs;
    QList<double> m_channelEQBand1Qs;
    QList<double> m_channelEQBand2Qs;
    QList<double> m_channelEQBand3Qs;

    QList<int> m_channelEQBand0Types;
    QList<int> m_channelEQBand3Types;

    QList<double> m_channelCompAttacks;
    QList<double> m_channelCompReleases;

    QList<double> m_channelGateAttacks;
    QList<double> m_channelGateReleases;
    QList<double> m_channelGateHolds;

    // Dynamic Undo reverse-fade tracking state
    bool m_inUndoTransition = false;
    float m_undoElapsedMs = 0.0f;
    float m_undoDurationMs = 0.0f;
    
    std::array<float, 24> m_undoStartVols{};
    float m_undoStartMasterVol = 0.0f;
    
    std::array<float, 24> m_undoTargetVols{};
    std::array<bool, 24> m_undoTargetMutes{};
    float m_undoTargetMasterVol = 0.0f;
    bool m_undoTargetMasterMute = false;
    int m_undoTargetProgramCam = 0;
    int m_undoTargetPreviewCam = 1;
    bool m_undoTargetFTB = false;

    // Lock-free queues going to/from the real-time DSP
    SPSCQueue<float> uiToDspQueue;
    SPSCQueue<float> dspToUiQueue;
    
    QTimer* m_feedbackTimer;

    // Simulated real-time background audio thread
    std::atomic<bool> m_running{true};
    std::jthread m_simulatedAudioThread;
};
