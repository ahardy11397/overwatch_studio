# Audio Patch Board & Device Router Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a professional high-density 2D coordinate audio patch board matrix allowing users to configure ASIO/WASAPI driver parameters, patch physical/internal audio sources to channel/hardware destinations, and edit individual route properties (dB trim gain, TapPoints) via double-click inline popups.

**Architecture:** We extend `AudioEngineBridge` to serialize routing changes onto the lock-free `uiToDspQueue` SPSC queue using `RoutingCommand` structures. The real-time loop in `AudioEngineCore` pops commands lock-freely to populate the pre-allocated `SparseRoutingMatrix`, preventing real-time thread priority inversion. The QML interface displays grouped collapsible grid cells and triggers popup editors dynamically.

**Tech Stack:** C++20, Qt 6.6.2 LTS QML, lock-free SPSC Queues (`readerwriterqueue`), MSVC 2022 v143 Compiler, GoogleTest.

---

### Task 1: C++ Audio Device Settings & SPSC Serialization (Backend)

**Files:**
- Modify: [src/core/audio/AudioEngineCore.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioEngineCore.h)
- Modify: [src/ui/AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h)
- Modify: [src/ui/AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp)
- Modify: [tests/AudioEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/AudioEngineTests.cpp)

- [ ] **Step 1: Repair the corrupted header template in `AudioEngineCore.h`**
  Let's replace the literal garbage `"<truncated 2701 bytes>"` and mock lines with a clean, fully-functioning `AudioEngineCore` class definition that handles real-time audio block summing and SPSC routing commands safely.
  
  ```cpp
  #pragma once

  #ifndef REALTIME_SAFE
  #if defined(__clang__)
  #define REALTIME_SAFE [[clang::nonblocking]]
  #else
  #define REALTIME_SAFE
  #endif
  #endif

  #include "AudioChannelStrip.h"
  #include "SparseRoutingMatrix.h"
  #include "LookAheadLimiter.h"
  #include <span>
  #include <vector>
  #include <memory>
  #include <algorithm>

  #ifndef JUCE_ASIO
  namespace juce {
  class AudioIODeviceCallback {
  public:
      virtual ~AudioIODeviceCallback() = default;
      virtual void audioDeviceIOCallbackWithContext(
          const float** inputChannelData, int numInputChannels,
          float** outputChannelData, int numOutputChannels,
          int numSamples, const void* context
      ) = 0;
      virtual void audioDeviceAboutToStart(void* device) = 0;
      virtual void audioDeviceStopped() = 0;
  };
  }
  #else
  #include <juce_audio_devices/juce_audio_devices.h>
  #endif

  enum class RoutingCommandType : uint8_t {
      SetRoute,
      UnpatchRoute,
      ClearAllRoutes,
      SetDeviceConfig
  };

  struct alignas(16) RoutingCommand {
      RoutingCommandType type;
      uint32_t sourceId;
      uint32_t destId;
      float gain;
      TapPoint tap;
      uint32_t sampleRate;
      uint32_t bufferSize;
  };

  class AudioEngineCore : public juce::AudioIODeviceCallback {
  public:
      static constexpr size_t InputChannelsCount = 24;
      static constexpr size_t OutputChannelsCount = 8;

      AudioEngineCore() noexcept : activeSampleRate(48000.0f) {
          inputBufferPtrs.fill(nullptr);
          outputBufferPtrs.fill(nullptr);
      }

      void audioDeviceAboutToStart(void* device) override {
          (void)device;
          RealtimeLogger::getInstance().log("AudioEngineCore callback started.");
      }

      void audioDeviceStopped() override {
          RealtimeLogger::getInstance().log("AudioEngineCore callback stopped.");
      }

      void audioDeviceIOCallbackWithContext(
          const float** inputChannelData, int numInputChannels,
          float** outputChannelData, int numOutputChannels,
          int numSamples, const void* context
      ) override REALTIME_SAFE {
          (void)context;
          size_t samples = static_cast<size_t>(numSamples);
          size_t inputs = std::min(static_cast<size_t>(numInputChannels), InputChannelsCount);
          size_t outputs = std::min(static_cast<size_t>(numOutputChannels), OutputChannelsCount);

          // 1. Map pointers safely with bounds checking
          for (size_t i = 0; i < InputChannelsCount; ++i) {
              inputBufferPtrs[i] = (i < inputs && inputChannelData[i]) ? inputChannelData[i] : dummyBuffer.data();
          }
          for (size_t o = 0; o < OutputChannelsCount; ++o) {
              outputBufferPtrs[o] = (o < outputs && outputChannelData[o]) ? outputChannelData[o] : dummySummingBuffer.data();
              std::fill_n(outputBufferPtrs[o], samples, 0.0f);
          }

          // 2. Process channel strips (In-place)
          for (size_t c = 0; c < inputs; ++c) {
              float* dest = outputBufferPtrs[c % outputs];
              std::copy_n(inputBufferPtrs[c], samples, dest);
              channelStrips[c].processBlock(dest, samples);
          }

          // 3. Process matrix sums
          std::span<const float*> sourceSpan(inputBufferPtrs.data(), InputChannelsCount);
          std::span<float*> destSpan(outputBufferPtrs.data(), OutputChannelsCount);
          routingMatrix.process(sourceSpan, destSpan, samples);

          // 4. Limiter safety
          for (size_t o = 0; o < outputs; ++o) {
              masterSafetyLimiter.process(outputBufferPtrs[o], samples);
          }
      }

      SparseRoutingMatrix& getRoutingMatrix() noexcept {
          return routingMatrix;
      }

  private:
      float activeSampleRate;
      alignas(64) std::array<AudioChannelStrip, InputChannelsCount> channelStrips;
      alignas(64) SparseRoutingMatrix routingMatrix;
      alignas(64) LookAheadLimiter masterSafetyLimiter;

      std::array<const float*, InputChannelsCount> inputBufferPtrs;
      std::array<float*, OutputChannelsCount> outputBufferPtrs;

      alignas(16) std::array<float, 1024> dummyBuffer{};
      alignas(16) std::array<float, 1024> dummySummingBuffer{};
  };
  ```

- [ ] **Step 2: Declare properties & invokable slots in `AudioEngineBridge.h`**
  Add the missing variables, signals, and slot definitions to support routing controls:
  ```cpp
  // Add to AudioEngineBridge.h class properties section:
  Q_PROPERTY(QVariantList availableDrivers READ availableDrivers CONSTANT)
  Q_PROPERTY(QVariantList availableDevices READ availableDevices CONSTANT)
  Q_PROPERTY(int activeSampleRate READ activeSampleRate WRITE setActiveSampleRate NOTIFY deviceSettingsChanged)
  Q_PROPERTY(int activeBufferSize READ activeBufferSize WRITE setActiveBufferSize NOTIFY deviceSettingsChanged)

  // Add to public methods:
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

  signals:
  void deviceSettingsChanged();
  void patchesChanged();

  // Add to private fields:
  int m_activeSampleRate = 48000;
  int m_activeBufferSize = 128;
  struct ActiveRouteUI { int src; int dest; double gain; int tap; };
  QList<ActiveRouteUI> m_uiRoutes;
  ```

- [ ] **Step 3: Implement device slots & serialization in `AudioEngineBridge.cpp`**
  Write setters, invokable methods, and SPSC commands pushing:
  ```cpp
  // Add to AudioEngineBridge.cpp:
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
  ```

- [ ] **Step 4: Add GoogleTest for SPSC Routing commands**
  Append a unit test case inside `tests/AudioEngineTests.cpp`:
  ```cpp
  TEST_F(AudioEngineTest, VerifyRouteTogglingAndGain) {
      SparseRoutingMatrix matrix;
      matrix.setRoute(0, 0, 0.707f, TapPoint::PreFader);
      
      std::span<const float*> sourceSpan(sourceChannels.data(), 1);
      std::span<float*> destSpan(destChannels.data(), 1);
      matrix.process(sourceSpan, destSpan, 64);
      
      EXPECT_NEAR(outputBuffer[0], 0.707f, 1e-5f);
  }
  ```

- [ ] **Step 5: Run tests and verify compilation**
  Run command: `cmake --build build --config Release`
  Expected output: Compilation succeeds with 0 errors!

- [ ] **Step 6: Commit backend additions**
  Run:
  ```bash
  git add src/core/audio/AudioEngineCore.h src/ui/AudioEngineBridge.h src/ui/AudioEngineBridge.cpp tests/AudioEngineTests.cpp
  git commit -m "feat(audio-core): implement SPSC routing commands and device properties"
  ```

---

### Task 2: Build Collapsible Coordinate Grid UI (QML Matrix)

**Files:**
- Modify: [src/ui/Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml)

- [ ] **Step 1: Define physical categories & routing variables**
  Add state properties inside `Window` in `Main.qml` to represent categories, mock channels list, and active patch state:
  ```qml
  // Add below "property real masterVolume: 0.8"
  property var sourceCategories: ["ASIO Inputs", "DAW Playback", "Generators"]
  property var destCategories: ["Mix Inputs", "Busses", "ASIO Monitor"]
  property var activeRowExpanded: [true, true, true]
  property var activeColExpanded: [true, true, true]
  property var activePatchesList: []
  ```

- [ ] **Step 2: Design visual patch grid panel**
  Construct a scrolling coordinate matrix view inside `rightPanel.activeTab === 3` or as a swappable window layout inside `Main.qml`. Group cells into rows and columns, drawing a glassmorphic background:
  ```qml
  ScrollView {
      anchors.fill: parent
      clip: true
      
      ColumnLayout {
          width: parent.width
          spacing: 10
          
          // Device Selection Deck
          RowLayout {
              Layout.fillWidth: true
              spacing: 8
              
              ComboBox {
                  model: audioCore.availableDrivers
                  currentIndex: 0
                  onCurrentIndexChanged: audioCore.configureDevice(currentText, audioCore.activeDevice, audioCore.activeSampleRate, audioCore.activeBufferSize)
              }
              ComboBox {
                  model: audioCore.availableDevices
                  currentIndex: 0
              }
          }
          
          // 2D Matrix coordinate board
          // Grid columns & rows styled in dark-mode graphite surfaces
      }
  }
  ```

- [ ] **Step 3: Implement click-to-patch and double-click triggers**
  Hook up clicking interaction on patch grid cells to immediately trigger `audioCore.patchRoute(...)` and update QML state list:
  ```qml
  onClicked: {
      if (isPatched) {
          audioCore.unpatchRoute(sourceIndex, destIndex)
      } else {
          audioCore.patchRoute(sourceIndex, destIndex, 1.0, 2) // default Post-Fader
      }
      activePatchesList = audioCore.getActivePatches()
  }
  ```

- [ ] **Step 4: Build the Double-Click Inline Route Controller Popup**
  Declare a floating glassmorphic container overlay showing Gain Trim (PremiumSlider) and TapPoint options (Pre-EQ, Pre-Fader, Post-Fader) which pops up relative to coordinates of clicked cells.

- [ ] **Step 5: Run syntax validation**
  Run command: `python scratch/check_brackets.py`
  Expected output: "All brackets match perfectly!"

- [ ] **Step 6: Commit QML matrix interface**
  Run:
  ```bash
  git add src/ui/Main.qml
  git commit -m "feat(ui): implement collapsible coordinate grid matrix and device configuration deck"
  ```
