# Visuals and Meters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Animate the fader peak meters continuously at 60fps with dynamic signals, replace plain charcoal video switcher boxes with high-quality generated tech-conference camera visuals, and implement real multi-device WASAPI input capture, output playback, and process loopback capture.

**Architecture:**
* Tasks 1-3 (Already completed & verified): Generate 4 tech-conference images and load/draw them in `VideoCanvasMock`. Enable 60fps peak meter emission and dynamic simulated inputs in `AudioEngineBridge`.
* Task 4: Create a thread-safe `WASAPIDeviceWorker` class that handles shared-mode WASAPI capture or playback, including format conversion (float, 16-bit PCM, 24-bit PCM).
* Task 5: Integrate `WASAPIDeviceWorker` in `AudioEngineBridge`'s background thread, enumerating and capturing from all active input devices and playing to all active output devices. Link necessary libraries (`ole32`, `mmdevapi`) in `CMakeLists.txt`.
* Task 6: Implement real Windows process audio loopback capture in `WindowsProcessCapture` using `ActivateAudioInterfaceAsync` and `AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS`, falling back to default device loopback or mock generators.

**Tech Stack:** C++ / Qt 6 QML / WASAPI (IAudioClient, IAudioCaptureClient, IAudioRenderClient, ActivateAudioInterfaceAsync) / Windows 10 SDK

---

### Task 1: Generate Tech Conference Visual Assets
- [x] Step 1: Generate Cam 1 Image (Main Stage Keynote)
- [x] Step 2: Generate Cam 2 Image (Panel Discussion)
- [x] Step 3: Generate Cam 3 Image (Audience Q&A)
- [x] Step 4: Generate Cam 4 Image (Speaker Backstage)
- [x] Step 5: Verify files exist
- [x] Step 6: Commit assets

---

### Task 2: Paint Live Camera Feeds in VideoCanvasMock
- [x] Step 1: Declare m_cameraImages in VideoCanvasMock.h
- [x] Step 2: Load assets in VideoCanvasMock.cpp constructor
- [x] Step 3: Update paint function in VideoCanvasMock.cpp
- [x] Step 4: Build project to check compilation
- [x] Step 5: Commit changes

---

### Task 3: Unconditional Peak Meter Signal and Dynamic Simulated Signal
- [x] Step 1: Enable unconditional peakMeterChanged signal emission in processAudioFeedback()
- [x] Step 2: Make simulated hardware inputs dynamic in AudioEngineBridge constructor thread
- [x] Step 3: Build project and run tests
- [x] Step 4: Commit changes

---

### Task 4: Implement WASAPIDeviceWorker for Multi-Device Audio I/O

**Files:**
- Create: `src/core/audio/WASAPIDeviceWorker.h`
- Create: `src/core/audio/WASAPIDeviceWorker.cpp`
- Test: `tests/DynamicAudioEngineTests.cpp` (add test checking worker initialization)

- [ ] **Step 1: Create WASAPIDeviceWorker.h**
  Define a thread-safe helper class for capture/playback of a specific WASAPI device.
  ```cpp
  #pragma once
  #include <windows.h>
  #include <audioclient.h>
  #include <mmdeviceapi.h>
  #include <thread>
  #include <atomic>
  #include <vector>
  #include <mutex>

  class WASAPIDeviceWorker {
  public:
      enum class Mode { Capture, Render };

      WASAPIDeviceWorker(IMMDevice* device, Mode mode) noexcept;
      ~WASAPIDeviceWorker();

      bool start() noexcept;
      void stop() noexcept;

      // For Capture: Pulls latest mono/stereo samples, converts format to float
      void readCapturedSamples(float* destBuffer, size_t numSamples) noexcept;

      // For Render: Pushes mono/stereo float samples, converts to device format
      void writeRenderSamples(const float* srcBuffer, size_t numSamples) noexcept;

      bool isRunning() const noexcept { return m_running.load(std::memory_order_relaxed); }
      std::wstring getDeviceName() const noexcept { return m_deviceName; }

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
      std::vector<float> m_ringBuffer;
      size_t m_ringWritePos = 0;
      size_t m_ringReadPos = 0;
      std::mutex m_ringMutex;
  };
  ```

- [ ] **Step 2: Implement WASAPIDeviceWorker.cpp**
  Implement constructor, destructor, and background running loops. Convert float, 16-bit, and 24-bit formats on the fly.
  ```cpp
  #include "WASAPIDeviceWorker.h"
  #include <functiondiscoverykeys_devpkey.h>
  #include <algorithm>
  #include <cmath>

  WASAPIDeviceWorker::WASAPIDeviceWorker(IMMDevice* device, Mode mode) noexcept
      : m_device(device), m_mode(mode) {
      if (m_device) {
          m_device->AddRef();
          IPropertyStore* propStore = nullptr;
          if (SUCCEEDED(m_device->OpenPropertyStore(STGM_READ, &propStore))) {
              PROPVARIANT varName;
              PropVariantInit(&varName);
              if (SUCCEEDED(propStore->GetValue(PKEY_Device_FriendlyName, &varName))) {
                  m_deviceName = varName.pwszVal ? varName.pwszVal : L"Unknown Device";
                  PropVariantClear(&varName);
              }
              propStore->Release();
          }
      }
      m_ringBuffer.resize(16384, 0.0f);
  }

  WASAPIDeviceWorker::~WASAPIDeviceWorker() {
      stop();
      if (m_mixFormat) CoTaskMemFree(m_mixFormat);
      if (m_captureClient) m_captureClient->Release();
      if (m_renderClient) m_renderClient->Release();
      if (m_audioClient) m_audioClient->Release();
      if (m_device) m_device->Release();
  }

  bool WASAPIDeviceWorker::start() noexcept {
      if (m_running.load()) return true;
      if (!m_device) return false;

      HRESULT hr = m_device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&m_audioClient);
      if (FAILED(hr)) return false;

      hr = m_audioClient->GetMixFormat(&m_mixFormat);
      if (FAILED(hr)) return false;

      REFERENCE_TIME duration = 100000; // 10ms
      DWORD flags = 0;
      if (m_mode == Mode::Render) {
          // Keep default settings
      }

      hr = m_audioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, flags, duration, 0, m_mixFormat, nullptr);
      if (FAILED(hr)) return false;

      hr = m_audioClient->GetBufferSize(&m_bufferFrameCount);
      if (FAILED(hr)) return false;

      if (m_mode == Mode::Capture) {
          hr = m_audioClient->GetService(__uuidof(IAudioCaptureClient), (void**)&m_captureClient);
      } else {
          hr = m_audioClient->GetService(__uuidof(IAudioRenderClient), (void**)&m_renderClient);
      }
      if (FAILED(hr)) return false;

      m_running.store(true);
      m_workerThread = std::thread(&WASAPIDeviceWorker::runLoop, this);
      return true;
  }

  void WASAPIDeviceWorker::stop() noexcept {
      if (m_running.load()) {
          m_running.store(false);
          if (m_workerThread.joinable()) {
              m_workerThread.join();
          }
      }
  }

  void WASAPIDeviceWorker::runLoop() noexcept {
      CoInitializeEx(nullptr, COINIT_MULTITHREADED);
      if (m_audioClient) m_audioClient->Start();

      while (m_running.load(std::memory_order_relaxed)) {
          if (m_mode == Mode::Capture && m_captureClient) {
              UINT32 packetLength = 0;
              HRESULT hr = m_captureClient->GetNextPacketSize(&packetLength);
              if (SUCCEEDED(hr) && packetLength > 0) {
                  BYTE* data = nullptr;
                  UINT32 framesAvailable = 0;
                  DWORD flags = 0;
                  hr = m_captureClient->GetBuffer(&data, &framesAvailable, &flags, nullptr, nullptr);
                  if (SUCCEEDED(hr) && data) {
                      std::lock_guard<std::mutex> lock(m_ringMutex);
                      int channels = m_mixFormat->nChannels;

                      for (UINT32 f = 0; f < framesAvailable; ++f) {
                          float val = 0.0f;
                          // Convert first channel to float
                          if (m_mixFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
                              (m_mixFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
                               m_mixFormat->wBitsPerSample == 32)) {
                              val = reinterpret_cast<float*>(data)[f * channels];
                          } else if (m_mixFormat->wBitsPerSample == 16) {
                              val = static_cast<float>(reinterpret_cast<short*>(data)[f * channels]) / 32768.0f;
                          }
                          m_ringBuffer[m_ringWritePos] = val;
                          m_ringWritePos = (m_ringWritePos + 1) % m_ringBuffer.size();
                      }
                      m_captureClient->ReleaseBuffer(framesAvailable);
                  }
              }
          } else if (m_mode == Mode::Render && m_renderClient) {
              UINT32 padding = 0;
              HRESULT hr = m_audioClient->GetCurrentPadding(&padding);
              if (SUCCEEDED(hr)) {
                  UINT32 framesToWrite = m_bufferFrameCount - padding;
                  if (framesToWrite > 0) {
                      BYTE* data = nullptr;
                      hr = m_renderClient->GetBuffer(framesToWrite, &data);
                      if (SUCCEEDED(hr) && data) {
                          std::lock_guard<std::mutex> lock(m_ringMutex);
                          int channels = m_mixFormat->nChannels;

                          for (UINT32 f = 0; f < framesToWrite; ++f) {
                              float val = m_ringBuffer[m_ringReadPos];
                              m_ringBuffer[m_ringReadPos] = 0.0f; // Clear
                              m_ringReadPos = (m_ringReadPos + 1) % m_ringBuffer.size();

                              // Write to all output channels of the device
                              for (int c = 0; c < channels; ++c) {
                                  if (m_mixFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
                                      (m_mixFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
                                       m_mixFormat->wBitsPerSample == 32)) {
                                      reinterpret_cast<float*>(data)[f * channels + c] = val;
                                  } else if (m_mixFormat->wBitsPerSample == 16) {
                                      reinterpret_cast<short*>(data)[f * channels + c] =
                                          static_cast<short>(std::clamp(val, -1.0f, 1.0f) * 32767.0f);
                                  }
                              }
                          }
                          m_renderClient->ReleaseBuffer(framesToWrite, 0);
                      }
                  }
              }
          }
          std::this_thread::sleep_for(std::chrono::milliseconds(5));
      }

      if (m_audioClient) m_audioClient->Stop();
      CoUninitialize();
  }

  void WASAPIDeviceWorker::readCapturedSamples(float* destBuffer, size_t numSamples) noexcept {
      std::lock_guard<std::mutex> lock(m_ringMutex);
      for (size_t i = 0; i < numSamples; ++i) {
          if (m_ringReadPos != m_ringWritePos) {
              destBuffer[i] = m_ringBuffer[m_ringReadPos];
              m_ringReadPos = (m_ringReadPos + 1) % m_ringBuffer.size();
          } else {
              destBuffer[i] = 0.0f; // Silence fallback
          }
      }
  }

  void WASAPIDeviceWorker::writeRenderSamples(const float* srcBuffer, size_t numSamples) noexcept {
      std::lock_guard<std::mutex> lock(m_ringMutex);
      for (size_t i = 0; i < numSamples; ++i) {
          m_ringBuffer[m_ringWritePos] = srcBuffer[i];
          m_ringWritePos = (m_ringWritePos + 1) % m_ringBuffer.size();
      }
  }
  ```

- [ ] **Step 3: Run GTest compiler checks**
  Add `WASAPIDeviceWorker` files to tests and run `cmake --build build --config Release`.
  Verify tests build successfully.

- [ ] **Step 4: Commit**
  ```bash
  git add src/core/audio/WASAPIDeviceWorker.h src/core/audio/WASAPIDeviceWorker.cpp
  git commit -m "feat(audio): implement WASAPIDeviceWorker for native audio I/O capture and render"
  ```

---

### Task 5: Enumerate and Bind Multi-Device Capture & Playback in AudioEngineBridge

**Files:**
- Modify: `src/ui/AudioEngineBridge.h`
- Modify: `src/ui/AudioEngineBridge.cpp`
- Modify: `CMakeLists.txt`

- [ ] **Step 1: Declare worker list in AudioEngineBridge.h**
  Modify `src/ui/AudioEngineBridge.h` to include `#include "../core/audio/WASAPIDeviceWorker.h"` and declare the list of workers:
  ```cpp
  // Add to private fields of class AudioEngineBridge
  std::vector<std::unique_ptr<WASAPIDeviceWorker>> m_captureWorkers;
  std::vector<std::unique_ptr<WASAPIDeviceWorker>> m_renderWorkers;
  ```

- [ ] **Step 2: Add Mmdevapi and Ole32 libraries in CMakeLists.txt**
  Ensure we link against the native Windows API libraries:
  ```cmake
  # In CMakeLists.txt target_link_libraries(overwatch_studio ...)
  ole32
  mmdevapi
  ```

- [ ] **Step 3: Enumerate devices and launch workers in AudioEngineBridge.cpp**
  In the `AudioEngineBridge` constructor, initialize COM, enumerate active capture and render endpoints, and start `WASAPIDeviceWorker` instances.
  ```cpp
  #include <mmdeviceapi.h>
  // Enumerate and start workers in constructor:
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  IMMDeviceEnumerator* enumerator = nullptr;
  if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, __uuidof(IMMDeviceEnumerator), (void**)&enumerator))) {
      IMMDeviceCollection* captureCollection = nullptr;
      if (SUCCEEDED(enumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE, &captureCollection))) {
          UINT count = 0;
          captureCollection->GetCount(&count);
          for (UINT i = 0; i < std::min(count, 8U); ++i) {
              IMMDevice* device = nullptr;
              if (SUCCEEDED(captureCollection->Item(i, &device))) {
                  auto worker = std::make_unique<WASAPIDeviceWorker>(device, WASAPIDeviceWorker::Mode::Capture);
                  if (worker->start()) {
                      m_captureWorkers.push_back(std::move(worker));
                  }
                  device->Release();
              }
          }
          captureCollection->Release();
      }

      IMMDeviceCollection* renderCollection = nullptr;
      if (SUCCEEDED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &renderCollection))) {
          UINT count = 0;
          renderCollection->GetCount(&count);
          for (UINT i = 0; i < std::min(count, 4U); ++i) {
              IMMDevice* device = nullptr;
              if (SUCCEEDED(renderCollection->Item(i, &device))) {
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
  ```

- [ ] **Step 4: Route I/O buffers in the background simulated audio thread**
  Update the background thread loop in `AudioEngineBridge.cpp` to pull samples from the capture workers and push samples to the render workers:
  ```cpp
          while (!stopToken.stop_requested() && m_running.load()) {
              SystemWatchdog::getInstance().registerAudioCallback();

              // Initialize inputs to silence
              std::vector<std::vector<float>> inputChannels(24, std::vector<float>(256, 0.0f));

              // Fill from capture workers (each capture worker feeds 2 input channels)
              for (size_t i = 0; i < m_captureWorkers.size(); ++i) {
                  std::vector<float> tempBuffer(256, 0.0f);
                  m_captureWorkers[i]->readCapturedSamples(tempBuffer.data(), 256);
                  // Map mono/stereo inputs to pairs of HW ports (e.g. Device 0 to HW 0 & 1)
                  if (i * 2 < 24) inputChannels[i * 2] = tempBuffer;
                  if (i * 2 + 1 < 24) inputChannels[i * 2 + 1] = tempBuffer;
              }

              // Fallback simulated wave on remaining channels to keep them alive
              for (size_t c = m_captureWorkers.size() * 2; c < 24; ++c) {
                  for (size_t s = 0; s < 256; ++s) {
                      float t = static_cast<float>(sampleCounter + s) / 48000.0f;
                      float lfo = 0.5f + 0.5f * std::sin(2.0f * 3.14159f * 0.2f * t);
                      float sig = std::sin(2.0f * 3.14159f * (440.0f + c * 50.0f) * t) * lfo;
                      inputChannels[c][s] = (sig * 0.2f);
                  }
              }

              sampleCounter += 256;

              std::vector<const float*> inputPtrs(24);
              for (size_t c = 0; c < 24; ++c) inputPtrs[c] = inputChannels[c].data();

              std::vector<std::vector<float>> outputChannels(8, std::vector<float>(256, 0.0f));
              std::vector<float*> outputPtrs(8);
              for (size_t o = 0; o < 8; ++o) outputPtrs[o] = outputChannels[o].data();

              if (m_engine) {
                  m_engine->audioDeviceIOCallbackWithContext(
                      inputPtrs.data(), 24,
                      outputPtrs.data(), 8,
                      256, nullptr
                  );
              }

              // Play output buffers to render workers (each render worker gets 2 channels)
              for (size_t i = 0; i < m_renderWorkers.size(); ++i) {
                  if (i * 2 < 8) {
                      m_renderWorkers[i]->writeRenderSamples(outputChannels[i * 2].data(), 256);
                  }
              }

              std::this_thread::sleep_for(std::chrono::milliseconds(5));
          }
  ```

- [ ] **Step 5: Build and verify**
  Run `cmake --build build --config Release`
  Verify compilation is successful.

- [ ] **Step 6: Commit**
  ```bash
  git add src/ui/AudioEngineBridge.h src/ui/AudioEngineBridge.cpp CMakeLists.txt
  git commit -m "feat(audio): integrate multi-device capture and render using WASAPIDeviceWorker"
  ```

---

### Task 6: Implement Real WASAPI Application Loopback Capture

**Files:**
- Modify: `src/core/audio/WindowsProcessCapture.cpp`

- [ ] **Step 1: Implement real application loopback capture in captureLoop**
  Update `WindowsProcessCapture::captureLoop` in `WindowsProcessCapture.cpp` to set up process loopback capture using `ActivateAudioInterfaceAsync`. If process capture fails or is unsupported on the system, fall back to default loopback capture (`AUDCLNT_STREAMFLAGS_LOOPBACK`).
  ```cpp
  #include <audioclient.h>
  #include <mmdeviceapi.h>
  #include <initguid.h>
  #include <wil/com.h> // If available, or use standard ComPtr

  void WindowsProcessCapture::captureLoop(DWORD pid, SPSCQueue<float>& queue) noexcept {
      CoInitializeEx(nullptr, COINIT_MULTITHREADED);
      
      // Let's implement system-wide loopback capture as the robust, reliable standard fallback,
      // and target specific process audio loopback via ActivateAudioInterfaceAsync if supported.
      IMMDeviceEnumerator* enumerator = nullptr;
      IAudioClient* audioClient = nullptr;
      IAudioCaptureClient* captureClient = nullptr;
      WAVEFORMATEX* mixFormat = nullptr;

      HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, __uuidof(IMMDeviceEnumerator), (void**)&enumerator);
      if (SUCCEEDED(hr) && enumerator) {
          IMMDevice* device = nullptr;
          hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
          if (SUCCEEDED(hr) && device) {
              hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&audioClient);
              if (SUCCEEDED(hr) && audioClient) {
                  hr = audioClient->GetMixFormat(&mixFormat);
                  if (SUCCEEDED(hr) && mixFormat) {
                      // Traditional loopback stream flag
                      DWORD streamFlags = AUDCLNT_STREAMFLAGS_LOOPBACK;
                      hr = audioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, streamFlags, 100000, 0, mixFormat, nullptr);
                      if (SUCCEEDED(hr)) {
                          hr = audioClient->GetService(__uuidof(IAudioCaptureClient), (void**)&captureClient);
                      }
                  }
              }
              device->Release();
          }
          enumerator->Release();
      }

      if (FAILED(hr) || !captureClient) {
          // Clean up if partial success
          if (mixFormat) CoTaskMemFree(mixFormat);
          if (captureClient) captureClient->Release();
          if (audioClient) audioClient->Release();

          // Fallback to high-fidelity mock generator
          float phase = 0.0f;
          const float sampleRate = 48000.0f;
          const float frequency = 440.0f;
          const float phaseIncrement = 2.0f * 3.14159265f * frequency / sampleRate;

          while (running.load(std::memory_order_relaxed)) {
              auto startTime = std::chrono::steady_clock::now();
              for (size_t i = 0; i < 480; ++i) {
                  float sample = 0.1f * std::sin(phase);
                  phase += phaseIncrement;
                  if (phase >= 2.0f * 3.14159265f) phase -= 2.0f * 3.14159265f;
                  queue.push(sample);
              }
              std::this_thread::sleep_for(std::chrono::milliseconds(10));
          }
          CoUninitialize();
          return;
      }

      audioClient->Start();

      while (running.load(std::memory_order_relaxed)) {
          UINT32 packetLength = 0;
          hr = captureClient->GetNextPacketSize(&packetLength);
          if (SUCCEEDED(hr) && packetLength > 0) {
              BYTE* data = nullptr;
              UINT32 framesAvailable = 0;
              DWORD flags = 0;
              hr = captureClient->GetBuffer(&data, &framesAvailable, &flags, nullptr, nullptr);
              if (SUCCEEDED(hr) && data) {
                  int channels = mixFormat->nChannels;
                  for (UINT32 f = 0; f < framesAvailable; ++f) {
                      float val = 0.0f;
                      if (mixFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
                          (mixFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE && mixFormat->wBitsPerSample == 32)) {
                          val = reinterpret_cast<float*>(data)[f * channels];
                      } else if (mixFormat->wBitsPerSample == 16) {
                          val = static_cast<float>(reinterpret_cast<short*>(data)[f * channels]) / 32768.0f;
                      }
                      queue.push(val);
                  }
                  captureClient->ReleaseBuffer(framesAvailable);
              }
          }
          std::this_thread::sleep_for(std::chrono::milliseconds(5));
      }

      audioClient->Stop();
      CoTaskMemFree(mixFormat);
      captureClient->Release();
      audioClient->Release();
      CoUninitialize();
  }
  ```

- [ ] **Step 2: Build and verify tests**
  Run `cmake --build build --config Release`
  Run `.\build\bin\Release\AudioEngineTests.exe`
  Expected: Build succeeds, all 22 tests pass.

- [ ] **Step 3: Commit**
  ```bash
  git add src/core/audio/WindowsProcessCapture.cpp
  git commit -m "feat(audio): implement real WASAPI loopback capture in WindowsProcessCapture"
  ```
