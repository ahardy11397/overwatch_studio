# Individual Channel Hardware Device Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow each of the 24 console input channels to be individually patched to any active capture device and any input port on that device, with dynamic channel query support.

**Architecture:**
* Refactor `WASAPIDeviceWorker` to capture all device channels into a dynamic `std::vector<std::vector<float>>` collection of ring buffers, adding `getChannelCount()`.
* Expose `captureDevices` to QML from `AudioEngineBridge`. Store `(deviceIdx << 8) | channelIdx` as the UI hardware patch index.
* The simulated audio thread decodes this index and reads the targeted channel from the corresponding capture worker, while the DSP core is patched to `channelIdx` directly.
* Remove the global device configuration panel in `Main.qml` and replace the flat hardware patch ComboBox with two conditional dropdowns (device and channel).

---

### Task 1: Refactor WASAPIDeviceWorker for Multi-Channel Capture

**Files:**
- Modify: [WASAPIDeviceWorker.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.h)
- Modify: [WASAPIDeviceWorker.cpp](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.cpp)

- [ ] **Step 1: Declare channel count method and multi-channel members in header**
  Modify [WASAPIDeviceWorker.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.h):
  - Add `int getChannelCount() const noexcept;`
  - Replace `std::vector<float> m_ringBuffer;` with `std::vector<std::vector<float>> m_channelRingBuffers;`
  - Replace `size_t m_ringReadPos = 0;` with `std::vector<size_t> m_ringReadPos;`
  - Add `size_t m_ringBufferSize = 16384;`
  ```cpp
      int getChannelCount() const noexcept;
      bool isRunning() const noexcept { return m_running.load(std::memory_order_relaxed); }
      std::wstring getDeviceName() const noexcept { return m_deviceName; }
      size_t getBufferedSampleCount() const noexcept;

  private:
      void runLoop() noexcept;

      IMMDevice* m_device;
      Mode m_mode;
      std::wstring m_deviceName;
      std::atomic<bool> m_running{false};
      std::thread m_workerThread;

      IAudioClient* m_audioClient = nullptr;
      IAudioCaptureClient* m_captureClient = nullptr;
      IAudioRenderClient* m_renderClient = nullptr;

      WAVEFORMATEX* m_mixFormat = nullptr;
      UINT32 m_bufferFrameCount = 0;

      // Thread-safe ring buffers for decoupling I/O threads
      std::vector<std::vector<float>> m_channelRingBuffers;
      size_t m_ringWritePos = 0;
      std::vector<size_t> m_ringReadPos;
      size_t m_ringBufferSize = 16384;
      mutable std::mutex m_ringMutex;
  ```

- [ ] **Step 2: Implement getChannelCount and ring initialization in CPP**
  Modify [WASAPIDeviceWorker.cpp](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.cpp):
  - Implement `getChannelCount()`:
    ```cpp
    int WASAPIDeviceWorker::getChannelCount() const noexcept {
        return m_mixFormat ? static_cast<int>(m_mixFormat->nChannels) : 0;
    }
    ```
  - In the constructor, change `m_ringBuffer.resize(16384, 0.0f);` to:
    ```cpp
    // Do not allocate yet, we will allocate when start() determines mix format channels
    ```
  - In `start()`, right after `m_audioClient->Initialize(...)` (around line 60), allocate the dynamic ring buffers:
    ```cpp
        int channels = m_mixFormat->nChannels;
        m_channelRingBuffers.resize(channels);
        for (int c = 0; c < channels; ++c) {
            m_channelRingBuffers[c].resize(m_ringBufferSize, 0.0f);
        }
        m_ringReadPos.assign(channels, 0);
        m_ringWritePos = 0;
    ```

- [ ] **Step 3: Update WASAPIDeviceWorker::runLoop capture branch**
  Modify `WASAPIDeviceWorker::runLoop` capture path (around lines 113–139) to read and store all channels:
  ```cpp
                      for (UINT32 f = 0; f < framesAvailable; ++f) {
                          for (int c = 0; c < channels; ++c) {
                              float val = 0.0f;
                              if (isFloat) {
                                  if (m_mixFormat->wBitsPerSample == 32) {
                                      val = reinterpret_cast<float*>(data)[f * channels + c];
                                  } else if (m_mixFormat->wBitsPerSample == 64) {
                                      val = static_cast<float>(reinterpret_cast<double*>(data)[f * channels + c]);
                                  }
                              } else { // PCM
                                  if (m_mixFormat->wBitsPerSample == 16) {
                                      val = static_cast<float>(reinterpret_cast<short*>(data)[f * channels + c]) / 32768.0f;
                                  } else if (m_mixFormat->wBitsPerSample == 24) {
                                      size_t sampleOffset = (f * channels + c) * 3;
                                      int32_t valInt = (data[sampleOffset]) |
                                                       (data[sampleOffset + 1] << 8) |
                                                       (data[sampleOffset + 2] << 16);
                                      if (valInt & 0x800000) {
                                          valInt |= 0xFF000000;
                                      }
                                      val = static_cast<float>(valInt) / 8388608.0f;
                                  } else if (m_mixFormat->wBitsPerSample == 32) {
                                      val = static_cast<float>(reinterpret_cast<int32_t*>(data)[f * channels + c]) / 2147483648.0f;
                                  }
                              }
                              m_channelRingBuffers[c][m_ringWritePos] = val;
                          }
                          m_ringWritePos = (m_ringWritePos + 1) % m_ringBufferSize;
                      }
  ```

- [ ] **Step 4: Update readCapturedSamples, writeRenderSamples, and getBufferedSampleCount**
  Modify `WASAPIDeviceWorker::readCapturedSamples`, `writeRenderSamples`, and `getBufferedSampleCount` in [WASAPIDeviceWorker.cpp](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.cpp):
  - In `readCapturedSamples`, take `deviceChannelIdx` and pull from its buffer:
    ```cpp
    void WASAPIDeviceWorker::readCapturedSamples(int deviceChannelIdx, float* destBuffer, size_t numSamples) noexcept {
        std::lock_guard<std::mutex> lock(m_ringMutex);
        
        if (deviceChannelIdx < 0 || deviceChannelIdx >= static_cast<int>(m_channelRingBuffers.size())) {
            std::fill_n(destBuffer, numSamples, 0.0f);
            return;
        }
        
        size_t readPos = m_ringReadPos[deviceChannelIdx];
        size_t buffered = (m_ringWritePos >= readPos) ? 
                          (m_ringWritePos - readPos) : 
                          (m_ringBufferSize - readPos + m_ringWritePos);
                          
        if (buffered > 512) {
            readPos = (m_ringWritePos + m_ringBufferSize - 512) % m_ringBufferSize;
        }

        const auto& chanBuf = m_channelRingBuffers[deviceChannelIdx];
        for (size_t i = 0; i < numSamples; ++i) {
            if (readPos != m_ringWritePos) {
                destBuffer[i] = chanBuf[readPos];
                readPos = (readPos + 1) % m_ringBufferSize;
            } else {
                destBuffer[i] = 0.0f; // Silence fallback
            }
        }
        m_ringReadPos[deviceChannelIdx] = readPos;
    }
    ```
  - In `getBufferedSampleCount()`, check channel 0:
    ```cpp
    size_t WASAPIDeviceWorker::getBufferedSampleCount() const noexcept {
        std::lock_guard<std::mutex> lock(m_ringMutex);
        if (m_ringReadPos.empty()) return 0;
        size_t readPos = m_ringReadPos[0];
        return (m_ringWritePos >= readPos) ? 
               (m_ringWritePos - readPos) : 
               (m_ringBufferSize - readPos + m_ringWritePos);
    }
    ```
  - Update `writeRenderSamples` to use `m_mixFormat->nChannels` for bounds/interleaving if in render mode (render mode ring buffer remains mono/stereo mixed flat):
    ```cpp
    void WASAPIDeviceWorker::writeRenderSamples(const float* srcBuffer, size_t numSamples) noexcept {
        std::lock_guard<std::mutex> lock(m_ringMutex);
        if (m_channelRingBuffers.empty() || m_channelRingBuffers[0].empty()) return;
        // Render mode writes mono/stereo mix directly
        for (size_t i = 0; i < numSamples; ++i) {
            m_channelRingBuffers[0][m_ringWritePos] = srcBuffer[i];
            m_ringWritePos = (m_ringWritePos + 1) % m_ringBufferSize;
        }
    }
    ```
    *Note:* Also update the render `runLoop` (lines 177-181) to read from `m_channelRingBuffers[0]` instead of `m_ringBuffer`:
    ```cpp
                            float val = m_channelRingBuffers[0][m_ringReadPos[0]];
                            m_channelRingBuffers[0][m_ringReadPos[0]] = 0.0f; // Clear
                            m_ringReadPos[0] = (m_ringReadPos[0] + 1) % m_ringBufferSize;
    ```
  - In `WASAPIDeviceWorker::runLoop()` (Render mode setup, around line 152), initialize render read pointer:
    ```cpp
                            m_ringReadPos.assign(channels, 0);
    ```
  - Update `WASAPIDeviceWorker` destructor:
    ```cpp
        // destructor cleanups are unchanged but ensure CoTaskMemFree(m_mixFormat) is safe
    ```

- [ ] **Step 5: Verify compilation**
  Run: `cmake --build build --config Release`
  Expected: Successful compilation of the core worker library.

- [ ] **Step 6: Commit**
  ```bash
  git add src/core/audio/WASAPIDeviceWorker.h src/core/audio/WASAPIDeviceWorker.cpp
  git commit -m "refactor(audio): support dynamic multi-channel capture in WASAPIDeviceWorker"
  ```

---

### Task 2: Expose Devices and Implement Dynamic Routing in AudioEngineBridge

**Files:**
- Modify: [AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h)
- Modify: [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp)

- [ ] **Step 1: Expose captureDevices property and update signatures in header**
  Modify [AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h):
  - Add Q_PROPERTY:
    ```cpp
    Q_PROPERTY(QVariantList captureDevices READ getCaptureDevices CONSTANT)
    ```
  - Declare getter:
    ```cpp
    QVariantList getCaptureDevices() const;
    ```

- [ ] **Step 2: Implement getCaptureDevices in CPP**
  Modify [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp):
  - Add implementation for `getCaptureDevices()`:
    ```cpp
    QVariantList AudioEngineBridge::getCaptureDevices() const {
        QVariantList list;
        for (const auto& w : m_captureWorkers) {
            QVariantMap map;
            map["deviceName"] = QString::fromStdWString(w->getDeviceName());
            map["channels"] = w->getChannelCount();
            list.append(map);
        }
        return list;
    }
    ```

- [ ] **Step 3: Refactor setInputPatch to store encoded hardware indices**
  Modify `AudioEngineBridge::setInputPatch` in [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp):
  - If `type == 1` (Hardware), store the encoded `(deviceIdx << 8) | channelIdx` index locally, but tell the DSP core to read from the channel's index (`channelIdx`) directly:
    ```cpp
    void AudioEngineBridge::setInputPatch(int channelIdx, int type, int index) {
        if (channelIdx < 0 || channelIdx >= m_uiInputPatches.size()) {
            return;
        }
        m_uiInputPatches[channelIdx].type = type;
        m_uiInputPatches[channelIdx].index = index;
        
        uint32_t dspIndex = (type == 1) ? static_cast<uint32_t>(channelIdx) : static_cast<uint32_t>(index);
        pushCommand(RoutingCommand{
            RoutingCommandType::SetInputPatch,
            static_cast<uint32_t>(channelIdx),
            static_cast<uint32_t>(type),
            0.0f,
            dspIndex
        });
        emit patchesChanged();
    }
    ```

- [ ] **Step 4: Update simulated audio thread loop**
  Modify `m_simulatedAudioThread` setup in `AudioEngineBridge::AudioEngineBridge` (lines 175-195):
  - Decode device and channel index from the stored index, and read from the target capture worker:
    ```cpp
                // 2. Read capture buffers for patched hardware channels
                for (size_t ch = 0; ch < 24; ++ch) {
                    if (m_uiInputPatches[ch].type == 1) {
                        int encoded = m_uiInputPatches[ch].index;
                        int devIdx = encoded >> 8;
                        int chanIdx = encoded & 0xFF;
                        if (devIdx >= 0 && devIdx < static_cast<int>(m_captureWorkers.size())) {
                            m_captureWorkers[devIdx]->readCapturedSamples(chanIdx, &inputBuffers[ch * 256], 256);
                        } else {
                            std::fill_n(&inputBuffers[ch * 256], 256, 0.0f);
                        }
                    } else {
                        // Fallback to test generator signal for unpatched/generator/other channels
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
                }
    ```

- [ ] **Step 5: Verify compilation and tests**
  Run: `cmake --build build --config Release`
  Then: `build/bin/Release/AudioEngineTests.exe`
  Expected: Successful compilation and all 26 unit tests PASS.

- [ ] **Step 6: Commit**
  ```bash
  git add src/ui/AudioEngineBridge.h src/ui/AudioEngineBridge.cpp
  git commit -m "feat(ui-bridge): support individual hardware device patching and routing by channel"
  ```

---

### Task 3: Refactor Main.qml Settings UI

**Files:**
- Modify: [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml)

- [ ] **Step 1: Remove ASIO DEVICE CONFIGURATION panel**
  Remove the `Rectangle` containing "ASIO DEVICE CONFIGURATION" block (lines 7867-7956) in [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml).

- [ ] **Step 2: Redesign Input Patch row dropdowns**
  Modify [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml) around lines 8080-8160.
  - In `srcTypeCombo`'s `onActivated`, add handling for `newType === 1` default configuration:
    ```qml
                                                    if (newType === 3) {
                                                        var processes = Object.keys(audioCore.availableProcesses);
                                                        if (processes.length > 0) {
                                                            var procName = processes[0];
                                                            var pid = audioCore.availableProcesses[procName];
                                                            audioCore.setInputPatch(channelIdx, 3, pid);
                                                            audioCore.startApplicationCapture(channelIdx, procName, pid);
                                                        } else {
                                                            audioCore.setInputPatch(channelIdx, 3, 0);
                                                        }
                                                    } else if (newType === 1) {
                                                        audioCore.setInputPatch(channelIdx, 1, 0); // Default to device 0, channel 0
                                                    } else {
                                                        audioCore.setInputPatch(channelIdx, newType, 0);
                                                    }
    ```
  - Replace the flat `srcDetailCombo` ComboBox with the four dedicated ComboBoxes:
    ```qml
                                             // --- HARDWARE DEVICE SELECTION (Visible only for type 1) ---
                                             ComboBox {
                                                 id: hwDeviceCombo
                                                 implicitHeight: 24
                                                 Layout.preferredWidth: 150
                                                 visible: srcTypeCombo.currentIndex === 1
                                                 
                                                 model: audioCore.captureDevices.map(function(d) { return d.deviceName; })
                                                 
                                                 currentIndex: {
                                                     if (audioCore.inputPatches && audioCore.inputPatches[channelIdx] !== undefined) {
                                                         var patch = audioCore.inputPatches[channelIdx];
                                                         if (patch.type === 1) {
                                                             var devIdx = patch.index >> 8;
                                                             if (devIdx >= 0 && devIdx < audioCore.captureDevices.length) {
                                                                 return devIdx;
                                                             }
                                                         }
                                                     }
                                                     return 0;
                                                 }
                                                 
                                                 onActivated: {
                                                     if (audioCore.captureDevices.length > 0) {
                                                         var devIdx = index;
                                                         var chIdx = hwChannelCombo.currentIndex;
                                                         var patchIdx = (devIdx << 8) | chIdx;
                                                         audioCore.setInputPatch(channelIdx, 1, patchIdx);
                                                     }
                                                 }
                                             }
                                             
                                             // --- HARDWARE CHANNEL SELECTION (Visible only for type 1) ---
                                             ComboBox {
                                                 id: hwChannelCombo
                                                 implicitHeight: 24
                                                 Layout.preferredWidth: 80
                                                 visible: srcTypeCombo.currentIndex === 1
                                                 
                                                 model: {
                                                     var devIdx = hwDeviceCombo.currentIndex;
                                                     if (audioCore.captureDevices && devIdx >= 0 && devIdx < audioCore.captureDevices.length) {
                                                         var dev = audioCore.captureDevices[devIdx];
                                                         var count = dev ? dev.channels : 2;
                                                         var list = [];
                                                         for (var i = 0; i < count; ++i) {
                                                             list.push("Input " + (i + 1));
                                                         }
                                                         return list;
                                                     }
                                                     return ["Input 1", "Input 2"];
                                                 }
                                                 
                                                 currentIndex: {
                                                     if (audioCore.inputPatches && audioCore.inputPatches[channelIdx] !== undefined) {
                                                         var patch = audioCore.inputPatches[channelIdx];
                                                         if (patch.type === 1) {
                                                             return patch.index & 0xFF;
                                                         }
                                                     }
                                                     return 0;
                                                 }
                                                 
                                                 onActivated: {
                                                     if (audioCore.captureDevices.length > 0) {
                                                         var devIdx = hwDeviceCombo.currentIndex;
                                                         var chIdx = index;
                                                         var patchIdx = (devIdx << 8) | chIdx;
                                                         audioCore.setInputPatch(channelIdx, 1, patchIdx);
                                                     }
                                                 }
                                             }
                                             
                                             // --- TEST GENERATOR SELECTION (Visible only for type 2) ---
                                             ComboBox {
                                                 id: generatorCombo
                                                 implicitHeight: 24
                                                 Layout.preferredWidth: 150
                                                 visible: srcTypeCombo.currentIndex === 2
                                                 model: ["1kHz Sine Wave", "Pink Noise"]
                                                 
                                                 currentIndex: {
                                                     if (audioCore.inputPatches && audioCore.inputPatches[channelIdx] !== undefined) {
                                                         var patch = audioCore.inputPatches[channelIdx];
                                                         if (patch.type === 2) {
                                                             return patch.index;
                                                         }
                                                     }
                                                     return 0;
                                                 }
                                                 
                                                 onActivated: {
                                                     audioCore.setInputPatch(channelIdx, 2, index);
                                                 }
                                             }
                                             
                                             // --- APP CAPTURE SELECTION (Visible only for type 3) ---
                                             ComboBox {
                                                 id: appCaptureCombo
                                                 implicitHeight: 24
                                                 Layout.preferredWidth: 230
                                                 visible: srcTypeCombo.currentIndex === 3
                                                 
                                                 model: Object.keys(audioCore.availableProcesses)
                                                 
                                                 currentIndex: {
                                                     if (audioCore.inputPatches && audioCore.inputPatches[channelIdx] !== undefined) {
                                                         var patch = audioCore.inputPatches[channelIdx];
                                                         if (patch.type === 3) {
                                                             var processes = Object.keys(audioCore.availableProcesses);
                                                             for (var i = 0; i < processes.length; i++) {
                                                                 if (audioCore.availableProcesses[processes[i]] === patch.index) {
                                                                     return i;
                                                                 }
                                                             }
                                                         }
                                                     }
                                                     return -1;
                                                 }
                                                 
                                                 onActivated: {
                                                     var processes = Object.keys(audioCore.availableProcesses);
                                                     if (index >= 0 && index < processes.length) {
                                                         var procName = processes[index];
                                                         var pid = audioCore.availableProcesses[procName];
                                                         audioCore.setInputPatch(channelIdx, 3, pid);
                                                         audioCore.startApplicationCapture(channelIdx, procName, pid);
                                                     }
                                                 }
                                             }
    ```
  - Update the `PID Info` text block to bind to `appCaptureCombo.currentIndex`:
    ```qml
                                             // PID Info for App Capture
                                             Text {
                                                 Layout.fillWidth: true
                                                 text: {
                                                     if (srcTypeCombo.currentIndex === 3) {
                                                         var processes = Object.keys(audioCore.availableProcesses);
                                                         var selIdx = appCaptureCombo.currentIndex;
                                                         if (selIdx >= 0 && selIdx < processes.length) {
                                                             var procName = processes[selIdx];
                                                             var pid = audioCore.availableProcesses[procName];
                                                             return "PID: " + pid;
                                                         }
                                                     }
                                                     return "";
                                                 }
                                                 color: "#8a8d98"
                                                 font.pixelSize: 9
                                                 font.family: "Courier New"
                                             }
    ```

- [ ] **Step 3: Verify QML resources build without errors**
  Run: `cmake --build build --config Release`
  Expected: Successful compilation and linking.

- [ ] **Step 4: Commit**
  ```bash
  git add src/ui/Main.qml
  git commit -m "feat(ui-qml): remove global config panel and implement individual hardware input selection"
  ```
