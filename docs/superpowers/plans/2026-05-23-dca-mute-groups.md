# DCA & Mute Groups Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the DCA & Mute Groups lock-free DSP routing pipeline in C++ and design an interactive $24 \times 8$ configuration matrix in the QML diagnostics sandbox.

**Architecture:** We utilize atomic scaling variables inside the low-latency audio core and channel strips to execute zero-allocation multiplication during fader sweeps. Assignments are stored as fast 8-bit bitmasks synchronized via C++ UI Bridge slot triggers.

**Tech Stack:** Qt 6.6.2 (QML), C++20, GoogleTest (via CTest)

---

### Task 1: Declare Group Structures & Atomic Buffers

**Files:**
- Modify: [AudioChannelStrip.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioChannelStrip.h)
- Modify: [AudioEngineCore.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioEngineCore.h)
- Test: [ControlEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/ControlEngineTests.cpp)

- [ ] **Step 1.1: Update `AudioChannelStrip::processBlock` signature**
  Modify [AudioChannelStrip.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioChannelStrip.h) to accept active group scale factors and masks dynamically in real-time.
  
  ```cpp
  // In AudioChannelStrip.h:
  void processBlock(float* samples, size_t numSamples, 
                    const std::array<float, 8>& dcaVols, 
                    const std::array<bool, 8>& muteStates, 
                    uint8_t dcaMask, 
                    uint8_t muteMask) noexcept REALTIME_SAFE {
      // 1. AV Lip-Sync Delay Line alignment
      delayLine.processBlock(samples, numSamples);

      // 2. High-Pass Filter
      applyHPF(samples, numSamples);

      // 3. Noise Gate
      applyGate(samples, numSamples);

      // 4. Parametric EQ
      applyEQ(samples, numSamples);

      // 5. Compressor
      applyCompressor(samples, numSamples);

      // 6. Volume Fader Parameter Smoothing with DCA and Mute Group modifiers
      float dcaScale = 1.0f;
      for (int d = 0; d < 8; ++d) {
          if (dcaMask & (1 << d)) {
              dcaScale *= dcaVols[d];
          }
      }

      bool isMutedByGroup = false;
      for (int m = 0; m < 8; ++m) {
          if ((muteMask & (1 << m)) && muteStates[m]) {
              isMutedByGroup = true;
              break;
          }
      }

      float finalTarget = isMutedByGroup ? 0.0f : (volumeTarget * dcaScale);
      faderSmoother.setTarget(finalTarget);
      faderSmoother.processBlock(samples, numSamples);
  }
  ```

- [ ] **Step 1.2: Add atomic structures to `AudioEngineCore`**
  Modify [AudioEngineCore.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioEngineCore.h) to store groups states and bitmasks using lock-free std::atomic types:
  
  ```cpp
  // Add in AudioEngineCore.h public scope:
  void setDCAVolume(size_t index, float volume) noexcept {
      if (index < 8) dcaVolumes[index].store(volume, std::memory_order_relaxed);
  }
  void setMuteGroupState(size_t index, bool state) noexcept {
      if (index < 8) activeMuteGroups[index].store(state, std::memory_order_relaxed);
  }
  void setChannelDCAMask(size_t chIdx, uint8_t mask) noexcept {
      if (chIdx < InputChannelsCount) channelDcaMasks[chIdx].store(mask, std::memory_order_relaxed);
  }
  void setChannelMuteMask(size_t chIdx, uint8_t mask) noexcept {
      if (chIdx < InputChannelsCount) channelMuteGroupMasks[chIdx].store(mask, std::memory_order_relaxed);
  }
  ```
  
  And declare private member arrays in `AudioEngineCore.h`:
  ```cpp
  // Add in AudioEngineCore.h private scope:
  std::array<std::atomic<float>, 8> dcaVolumes;
  std::array<std::atomic<bool>, 8> activeMuteGroups;
  std::array<std::atomic<uint8_t>, InputChannelsCount> channelDcaMasks;
  std::array<std::atomic<uint8_t>, InputChannelsCount> channelMuteGroupMasks;
  ```

- [ ] **Step 1.3: Initialize arrays in constructor**
  In the `AudioEngineCore` constructor, initialize all arrays to default states:
  
  ```cpp
  for (auto& vol : dcaVolumes) vol.store(1.0f);
  for (auto& mute : activeMuteGroups) mute.store(false);
  for (auto& mask : channelDcaMasks) mask.store(0);
  for (auto& mask : channelMuteGroupMasks) mask.store(0);
  ```

- [ ] **Step 1.4: Update loop summation inside `audioDeviceIOCallbackWithContext`**
  Modify the channel processing loop in `AudioEngineCore::audioDeviceIOCallbackWithContext` to load these atomic states and feed them to `processBlock`:
  
  ```cpp
  // Within audioDeviceIOCallbackWithContext (AudioEngineCore.h):
  std::array<float, 8> localDcaVols;
  std::array<bool, 8> localMuteStates;
  for (size_t i = 0; i < 8; ++i) {
      localDcaVols[i] = dcaVolumes[i].load(std::memory_order_relaxed);
      localMuteStates[i] = activeMuteGroups[i].load(std::memory_order_relaxed);
  }

  for (size_t c = 0; c < inputs; ++c) {
      float* dest = outputBufferPtrs[c % outputs];
      std::copy_n(inputBufferPtrs[c], samples, dest);
      
      uint8_t dcaMask = channelDcaMasks[c].load(std::memory_order_relaxed);
      uint8_t muteMask = channelMuteGroupMasks[c].load(std::memory_order_relaxed);
      
      channelStrips[c].processBlock(dest, samples, localDcaVols, localMuteStates, dcaMask, muteMask);
  }
  ```

---

### Task 2: Expose Group Mappings on C++ UI Bridge

**Files:**
- Modify: [AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h)
- Modify: [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp)

- [ ] **Step 2.1: Expose properties & slots in `AudioEngineBridge`**
  Add Q_PROPERTIES and slots to [AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h):
  
  ```cpp
  // Add in AudioEngineBridge.h public Q_PROPERTY scope:
  Q_PROPERTY(QList<double> dcaVolumes READ dcaVolumes NOTIFY dcaVolumesChanged)
  Q_PROPERTY(QList<bool> dcaMutes READ dcaMutes NOTIFY dcaMutesChanged)
  Q_PROPERTY(QList<int> channelDcaMasks READ channelDcaMasks NOTIFY channelDcaMasksChanged)
  Q_PROPERTY(QList<int> channelMuteMasks READ channelMuteMasks NOTIFY channelMuteMasksChanged)
  ```
  
  Add signals:
  ```cpp
  void dcaVolumesChanged();
  void dcaMutesChanged();
  void channelDcaMasksChanged();
  void channelMuteMasksChanged();
  ```
  
  Add slots in public invokable scope:
  ```cpp
  Q_INVOKABLE QList<double> dcaVolumes() const;
  Q_INVOKABLE QList<bool> dcaMutes() const;
  Q_INVOKABLE QList<int> channelDcaMasks() const;
  Q_INVOKABLE QList<int> channelMuteMasks() const;

  Q_INVOKABLE void updateDCAVolume(int dcaIdx, double volume);
  Q_INVOKABLE void updateMuteGroupState(int groupIdx, bool state);
  Q_INVOKABLE void updateChannelDCAMapping(int chIdx, int dcaIdx, bool active);
  Q_INVOKABLE void updateChannelMuteMapping(int chIdx, int groupIdx, bool active);
  ```

  Add private member states in `AudioEngineBridge.h`:
  ```cpp
  QList<double> m_dcaVolumes;
  QList<bool> m_dcaMutes;
  QList<int> m_channelDcaMasks;
  QList<int> m_channelMuteMasks;
  ```

- [ ] **Step 2.2: Implement initialization & getters in `AudioEngineBridge.cpp`**
  Initialize arrays to size 8 (DCAs) and 24 (channels) in constructor, and write standard getters.
  
  ```cpp
  // In constructor:
  for (int i = 0; i < 8; ++i) {
      m_dcaVolumes.append(1.0);
      m_dcaMutes.append(false);
  }
  for (int i = 0; i < 24; ++i) {
      m_channelDcaMasks.append(0);
      m_channelMuteMasks.append(0);
  }
  ```

- [ ] **Step 2.3: Implement slot update callbacks**
  Implement the slots inside [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp):
  
  ```cpp
  QList<double> AudioEngineBridge::dcaVolumes() const { return m_dcaVolumes; }
  QList<bool> AudioEngineBridge::dcaMutes() const { return m_dcaMutes; }
  QList<int> AudioEngineBridge::channelDcaMasks() const { return m_channelDcaMasks; }
  QList<int> AudioEngineBridge::channelMuteMasks() const { return m_channelMuteMasks; }

  void AudioEngineBridge::updateDCAVolume(int dcaIdx, double volume) {
      if (dcaIdx >= 0 && dcaIdx < 8) {
          m_dcaVolumes[dcaIdx] = volume;
          emit dcaVolumesChanged();
      }
  }

  void AudioEngineBridge::updateMuteGroupState(int groupIdx, bool state) {
      if (groupIdx >= 0 && groupIdx < 8) {
          m_dcaMutes[groupIdx] = state;
          emit dcaMutesChanged();
      }
  }

  void AudioEngineBridge::updateChannelDCAMapping(int chIdx, int dcaIdx, bool active) {
      if (chIdx >= 0 && chIdx < 24 && dcaIdx >= 0 && dcaIdx < 8) {
          if (active) {
              m_channelDcaMasks[chIdx] |= (1 << dcaIdx);
          } else {
              m_channelDcaMasks[chIdx] &= ~(1 << dcaIdx);
          }
          emit channelDcaMasksChanged();
      }
  }

  void AudioEngineBridge::updateChannelMuteMapping(int chIdx, int groupIdx, bool active) {
      if (chIdx >= 0 && chIdx < 24 && groupIdx >= 0 && groupIdx < 8) {
          if (active) {
              m_channelMuteMasks[chIdx] |= (1 << groupIdx);
          } else {
              m_channelMuteMasks[chIdx] &= ~(1 << groupIdx);
          }
          emit channelMuteMasksChanged();
      }
  }
  ```

---

### Task 3: Build Interactive Double-Tabbed Sandbox Matrix & Visual Pills

**Files:**
- Modify: [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml)

- [ ] **Step 3.1: Redesign Show Control Sandbox Right Panel**
  Modify [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml) to convert the Right Panel (`Fail-Safe Diagnostics`) into a beautiful double-tabbed layout:
  
  ```qml
  // In Main.qml (Right Panel of Show Control Sandbox):
  Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: "#161920"
      border.color: "#252b36"
      border.width: 1
      radius: 8

      property int activeTab: 0 // 0=Diagnostics, 1=DCA & Mute Grid

      ColumnLayout {
          anchors.fill: parent
          anchors.margins: 12
          spacing: 10

          // Glassmorphic Tab Selector Header
          RowLayout {
              Layout.fillWidth: true
              spacing: 6
              
              Button {
                  text: "DIAGNOSTICS"
                  Layout.fillWidth: true
                  implicitHeight: 30
                  checkable: true
                  checked: activeTab === 0
                  onClicked: activeTab = 0
                  background: Rectangle {
                      color: activeTab === 0 ? "#252b36" : "transparent"
                      border.color: activeTab === 0 ? "#f0b000" : "#252b36"
                      radius: 4
                  }
              }
              Button {
                  text: "DCA & MUTE SETUP"
                  Layout.fillWidth: true
                  implicitHeight: 30
                  checkable: true
                  checked: activeTab === 1
                  onClicked: activeTab = 1
                  background: Rectangle {
                      color: activeTab === 1 ? "#252b36" : "transparent"
                      border.color: activeTab === 1 ? "#00d084" : "#252b36"
                      radius: 4
                  }
              }
          }

          // Content switcher
          StackLayout {
              Layout.fillWidth: true
              Layout.fillHeight: true
              currentIndex: activeTab

              // Tab 0: Diagnostics (Watchdog & Failover controls)
              ColumnLayout {
                  // [Original Diagnostics Controls placed here, untouched]
              }

              // Tab 1: DCA & Mute Routing Grid
              RowLayout {
                  spacing: 12
                  Layout.fillWidth: true
                  Layout.fillHeight: true

                  // Scrollable Setup Matrix
                  ScrollView {
                      Layout.fillWidth: true
                      Layout.fillHeight: true
                      clip: true

                      ColumnLayout {
                          spacing: 4
                          width: parent.width

                          // Header row
                          RowLayout {
                              spacing: 2
                              Text { text: "CHANNEL"; color: "#8a8d98"; font.pixelSize: 8; font.bold: true; width: 60 }
                              Repeater {
                                  model: 8
                                  Text { text: "D" + (index+1); color: "#00d084"; font.pixelSize: 8; font.bold: true; width: 18; horizontalAlignment: Text.AlignHCenter }
                              }
                              Repeater {
                                  model: 8
                                  Text { text: "M" + (index+1); color: "#ff3b30"; font.pixelSize: 8; font.bold: true; width: 18; horizontalAlignment: Text.AlignHCenter }
                              }
                          }

                          // 24 channel rows
                          Repeater {
                              model: 24
                              delegate: RowLayout {
                                  spacing: 2
                                  property int chIdx: index
                                  Text { text: "CH " + (chIdx+1); color: "#ffffff"; font.pixelSize: 9; font.bold: true; width: 60 }

                                  // DCA Checkboxes
                                  Repeater {
                                      model: 8
                                      delegate: Rectangle {
                                          width: 18; height: 18; radius: 4
                                          color: (audioCore.channelDcaMasks[chIdx] & (1 << index)) ? "#11261d" : "#0d0f12"
                                          border.color: (audioCore.channelDcaMasks[chIdx] & (1 << index)) ? "#00d084" : "#252b36"
                                          
                                          Text {
                                              text: "✔"
                                              anchors.centerIn: parent
                                              color: "#00d084"
                                              font.pixelSize: 9
                                              visible: (audioCore.channelDcaMasks[chIdx] & (1 << index))
                                          }

                                          MouseArea {
                                              anchors.fill: parent
                                              onClicked: {
                                                  var active = !(audioCore.channelDcaMasks[chIdx] & (1 << index));
                                                  audioCore.updateChannelDCAMapping(chIdx, index, active);
                                              }
                                          }
                                      }
                                  }

                                  // Mute Group Checkboxes
                                  Repeater {
                                      model: 8
                                      delegate: Rectangle {
                                          width: 18; height: 18; radius: 4
                                          color: (audioCore.channelMuteMasks[chIdx] & (1 << index)) ? "#261113" : "#0d0f12"
                                          border.color: (audioCore.channelMuteMasks[chIdx] & (1 << index)) ? "#ff3b30" : "#252b36"
                                          
                                          Text {
                                              text: "✔"
                                              anchors.centerIn: parent
                                              color: "#ff3b30"
                                              font.pixelSize: 9
                                              visible: (audioCore.channelMuteMasks[chIdx] & (1 << index))
                                          }

                                          MouseArea {
                                              anchors.fill: parent
                                              onClicked: {
                                                  var active = !(audioCore.channelMuteMasks[chIdx] & (1 << index));
                                                  audioCore.updateChannelMuteMapping(chIdx, index, active);
                                              }
                                          }
                                      }
                                  }
                              }
                          }
                      }
                  }

                  // Sidebar Master Faders
                  ColumnLayout {
                      width: 80
                      Layout.fillHeight: true
                      spacing: 4

                      Text { text: "DCA MASTER"; color: "#00d084"; font.pixelSize: 8; font.bold: true; Layout.alignment: Qt.AlignHCenter }

                      ScrollView {
                          Layout.fillWidth: true
                          Layout.fillHeight: true
                          clip: true
                          ColumnLayout {
                              spacing: 8
                              Repeater {
                                  model: 8
                                  RowLayout {
                                      spacing: 4
                                      Text { text: "D" + (index+1); color: "#8a8d98"; font.pixelSize: 8 }
                                      Slider {
                                          value: audioCore.dcaVolumes[index]
                                          Layout.fillWidth: true
                                          onMoved: audioCore.updateDCAVolume(index, value)
                                      }
                                      Button {
                                          text: "M"
                                          implicitWidth: 16; implicitHeight: 16
                                          checkable: true
                                          checked: audioCore.dcaMutes[index]
                                          onClicked: audioCore.updateMuteGroupState(index, !audioCore.dcaMutes[index])
                                      }
                                  }
                              }
                          }
                      }
                  }
              }
          }
      }
  }
  ```

- [ ] **Step 3.2: Render Dynamic Indicator pills on Channel Strips**
  Inside [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml), add a horizontal flowing row of active group pills above the volume level meter (CH 1–24 strips):
  
  ```qml
  // In Audio Window Channel Strip delegate, above the Mute/Fader layout:
  RowLayout {
      Layout.alignment: Qt.AlignHCenter
      spacing: 3
      height: 12

      // DCA active indicators
      Repeater {
          model: 8
          delegate: Rectangle {
              width: 10; height: 10; radius: 5
              color: "#00d084"
              visible: (audioCore.channelDcaMasks[chIdx] & (1 << index))
              Text {
                  text: (index + 1)
                  color: "#0a0c10"
                  font.pixelSize: 7
                  font.bold: true
                  anchors.centerIn: parent
              }
          }
      }

      // Mute Group active indicators
      Repeater {
          model: 8
          delegate: Rectangle {
              width: 12; height: 10; radius: 4
              color: "#ff3b30"
              visible: (audioCore.channelMuteMasks[chIdx] & (1 << index))
              Text {
                  text: "M" + (index + 1)
                  color: "#ffffff"
                  font.pixelSize: 6
                  font.bold: true
                  anchors.centerIn: parent
              }
          }
      }
  }
  ```

---

### Task 4: Complete GoogleTest Coverage & Verify Build

**Files:**
- Modify: [ControlEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/ControlEngineTests.cpp)

- [ ] **Step 4.1: Append GoogleTest code block**
  Add unit tests validating DCA gain calculations and mute group active states to [ControlEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/ControlEngineTests.cpp):
  
  ```cpp
  // Add at the end of tests/ControlEngineTests.cpp:
  TEST(ControlEngineTests, DCAGroupGainScaling) {
      AudioChannelStrip strip;
      strip.prepareToPlay(48000.0f);
      
      // Set normal preamp fader to 0dB (1.0f gain)
      strip.setFaderDb(0.0f);

      std::array<float, 8> dcaVols = { 0.5f, 1.0f, 0.75f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f };
      std::array<bool, 8> muteStates = { false, false, false, false, false, false, false, false };

      // Set assignment mask (DCA 1 and DCA 3 active) -> bit 0 and bit 2
      uint8_t dcaMask = (1 << 0) | (1 << 2);
      
      // Generate dummy frame with 1.0f values
      std::array<float, 100> samples;
      samples.fill(1.0f);

      // Process block
      strip.processBlock(samples.data(), samples.size(), dcaVols, muteStates, dcaMask, 0);

      // Calculated gain must scale to: 1.0f * (0.5 * 0.75) = 0.375f
      for (float val : samples) {
          EXPECT_NEAR(val, 0.375f, 0.001f);
      }
  }

  TEST(ControlEngineTests, MuteGroupAssignments) {
      AudioChannelStrip strip;
      strip.prepareToPlay(48000.0f);
      strip.setFaderDb(0.0f);

      std::array<float, 8> dcaVols;
      dcaVols.fill(1.0f);
      std::array<bool, 8> muteStates = { false, false, true, false, false, false, false, false }; // Mute group 3 active

      uint8_t muteMask = (1 << 2); // Assigned to Mute Group 3

      std::array<float, 100> samples;
      samples.fill(1.0f);

      // Process block
      strip.processBlock(samples.data(), samples.size(), dcaVols, muteStates, 0, muteMask);

      // Output must be hard digitally muted (0.0f)
      for (float val : samples) {
          EXPECT_NEAR(val, 0.0f, 0.001f);
      }
  }
  ```

- [ ] **Step 4.2: Run build compilation & verify**
  Run target build in MSVC release to confirm compile safety:
  `cmake --build build --config Release`
  
- [ ] **Step 4.3: Execute CTest automation suite**
  Execute: `ctest --test-dir build -C Release --output-on-failure`
  Expected: 3/3 Test suites pass, including the new DCA math blocks.
