# Technical Specification: Individual Channel Hardware Device Routing

## 1. Overview & Goals
Currently, Overwatch Studio captures hardware inputs using a fixed sequential layout: the first 8 active capture devices on the system are mapped to input channels 0–15 (2 channels per device). The global "ASIO Device Configuration" settings block is non-functional and does not allow selecting or reconfiguring devices.

This specification refactors the audio input routing to:
1. Remove the global device configuration panel.
2. Allow each of the 24 console input channels to be individually patched to any active capture device and any input port on that device.
3. Dynamically query each audio device's native channel count to populate the port selection list.
4. Keep the real-time DSP core lock-free, allocation-free, and decoupled from hardware details.

---

## 2. Component Design & Changes

### 2.1 WASAPIDeviceWorker
The worker will be updated to capture all channels of the hardware device:
* **Headers**: Define dynamic ring buffers and reader pointers in `WASAPIDeviceWorker.h`:
  ```cpp
  int getChannelCount() const noexcept;
  // ...
  std::vector<std::vector<float>> m_channelRingBuffers;
  std::vector<size_t> m_ringReadPos;
  size_t m_ringBufferSize = 16384;
  ```
* **Initialization**: In `WASAPIDeviceWorker::start()`:
  - Initialize the channel count: `int channels = m_mixFormat->nChannels;`.
  - Resize `m_channelRingBuffers` to `channels`, and resize each buffer to `16384`.
  - Resize `m_ringReadPos` to `channels`, initializing all elements to `0`.
* **Capture Loop**: In `WASAPIDeviceWorker::runLoop()` (capture path):
  - Read all `channels` from the WASAPI capture buffer for each frame.
  - Store each channel's sample into its corresponding ring buffer:
    ```cpp
    for (int c = 0; c < channels; ++c) {
        float sample = ...; // Convert from Float/PCM
        m_channelRingBuffers[c][m_ringWritePos] = sample;
    }
    m_ringWritePos = (m_ringWritePos + 1) % m_ringBufferSize;
    ```
* **Asynchronous Reading**: Update `readCapturedSamples` to accept a channel offset:
  ```cpp
  void readCapturedSamples(int deviceChannelIdx, float* destBuffer, size_t numSamples) noexcept;
  ```
  This method will read from `m_channelRingBuffers[deviceChannelIdx]` and advance its private read pointer `m_ringReadPos[deviceChannelIdx]`.

### 2.2 AudioEngineBridge
The bridge maps UI patches to capture workers:
* **Expose Capture Devices**: Expose a QVariantList property `captureDevices` containing maps of device name and channel counts:
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
* **Set Input Patch**: In `setInputPatch(int channelIdx, int type, int index)`:
  - For Hardware (`type == 1`), `index` is encoded as `(deviceIdx << 8) | channelIdx`.
  - We store this in the bridge's local patch map.
  - We push a `SetInputPatch` command to the DSP core (`AudioEngineCore`), passing the channel index itself (`channelIdx`) as the DSP index.
* **Simulated Audio Thread**:
  - The simulated audio thread runs the main DSP callback.
  - For each channel `ch` (0 to 23), if it is patched to Hardware (`type == 1`):
    - Decode the index: `int devIdx = encoded >> 8` and `int chanIdx = encoded & 0xFF`.
    - If `devIdx` is valid, read from the worker:
      ```cpp
      m_captureWorkers[devIdx]->readCapturedSamples(chanIdx, &inputBuffers[ch * 256], 256);
      ```
    - Otherwise, fill with silence.

### 2.3 Main.qml
* **Remove Panel**: Remove the `Rectangle` containing "ASIO DEVICE CONFIGURATION".
* **Refactor Input Patch Row**:
  - Replace the flat `srcDetailCombo` with three conditional ComboBoxes:
    1. **`hwDeviceCombo`** (visible only for ASIO Hardware type):
       - Model: `audioCore.captureDevices.map(d => d.deviceName)`
       - Selected index: `Math.floor(patch.index / 8)` or `patch.index >> 8`
       - On activated: sets patch to `(index << 8) | hwChannelCombo.currentIndex`.
    2. **`hwChannelCombo`** (visible only for ASIO Hardware type):
       - Model: generated dynamically matching the channel count of the selected device:
         ```qml
         model: {
             var dev = audioCore.captureDevices[hwDeviceCombo.currentIndex];
             var count = dev ? dev.channels : 2;
             var list = [];
             for (var i = 0; i < count; ++i) {
                 list.push("Input " + (i + 1));
             }
             return list;
         }
         ```
       - Selected index: `patch.index & 0xFF`
       - On activated: sets patch to `(hwDeviceCombo.currentIndex << 8) | index`.
    3. **`generatorCombo`** (visible for Test Generator type).
    4. **`appCaptureCombo`** (visible for App Capture type).

---

## 3. Data Flow and Thread Safety
The proposed architecture maintains strict thread-safety:
- **Lock-Free Read/Write**: Capture workers write to ring buffers, and the simulated audio thread reads from them using `std::lock_guard` protecting the ring read/write pointers.
- **Zero Real-Time Allocations**: Resizing and memory allocation of the ring buffers happen entirely during startup/device configuration on the UI thread inside `start()`. The DSP thread and simulated audio thread only perform bounded index checks and memory copies.

---

## 4. Verification Plan

### 4.1 Automated Verification
- Verify that the codebase compiles cleanly in Release configuration:
  `cmake --build build --config Release`
- Run the unit test suite:
  `build/bin/Release/AudioEngineTests.exe`

### 4.2 Manual Verification
- Open the application and go to settings.
- Verify that the "ASIO DEVICE CONFIGURATION" block is gone.
- Verify that under Input Patching, selecting "ASIO Hardware" shows a device dropdown and a channel dropdown.
- Check that the channel dropdown displays the exact channel count of the selected device.
- Select different hardware input channels on different devices and verify that audio routes correctly.
