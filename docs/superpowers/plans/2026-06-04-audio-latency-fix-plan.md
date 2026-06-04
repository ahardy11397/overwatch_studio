# Audio Latency Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the WASAPI audio latency (~1s) in Overwatch Studio by implementing a low-latency ring-buffer catch-up mechanism and a high-precision, hardware-aligned thread pacing loop.

**Architecture:** 
1. Add a ring buffer catch-up threshold to `WASAPIDeviceWorker` in both Capture and Render modes. When buffered samples exceed the threshold, advance the read pointer to discard stale backlog and keep latency low (target ~10-15ms).
2. Implement adaptive audio thread pacing in `AudioEngineBridge`: pace by capture hardware buffer fill level when capture devices are active; pace using a high-precision clock loop (with 1ms Windows timer resolution) when they are inactive.

**Tech Stack:** C++, Windows WASAPI, WinMM (for high-resolution timers), GoogleTest.

---

## 1. Directory & File Mapping

- **Modify:** [WASAPIDeviceWorker.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.h) — Add `getBufferedSampleCount()` and make `m_ringMutex` mutable.
- **Modify:** [WASAPIDeviceWorker.cpp](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.cpp) — Implement catch-up discard logic in `readCapturedSamples()` and `runLoop()` (Render mode).
- **Modify:** [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp) — Set Windows scheduler resolution to 1ms, and implement the adaptive hardware/timer pacing loop.
- **Test:** [DynamicAudioEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/DynamicAudioEngineTests.cpp) — Add verification unit tests for ring buffer levels and catch-up behavior.

---

## 2. Step-by-Step Tasks

### Task 1: Update WASAPIDeviceWorker Catch-Up Logic

**Files:**
- Modify: [WASAPIDeviceWorker.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.h)
- Modify: [WASAPIDeviceWorker.cpp](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.cpp)
- Test: [DynamicAudioEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/DynamicAudioEngineTests.cpp)

- [ ] **Step 1: Write a failing unit test for WASAPIDeviceWorker catch-up**
  Add a test to `tests/DynamicAudioEngineTests.cpp` verifying that:
  - `getBufferedSampleCount()` returns correct levels.
  - Adding too many samples triggers catch-up, discarding oldest samples and keeping latency minimal.
  ```cpp
  TEST(WASAPIDeviceWorkerTest, VerifyCatchUpAndBufferLevels) {
      // Create worker in Capture mode (using nullptr device for mock structure)
      WASAPIDeviceWorker worker(nullptr, WASAPIDeviceWorker::Mode::Capture);
      
      // Initially empty
      EXPECT_EQ(worker.getBufferedSampleCount(), 0);

      // Simulate writing a massive backlog (e.g., 2000 samples)
      std::vector<float> data(2000, 1.0f);
      worker.writeRenderSamples(data.data(), data.size()); // Write to ring buffer
      
      // Since it's capture/render shared buffer, verify backlog level
      EXPECT_EQ(worker.getBufferedSampleCount(), 2000);

      // Reading a block of 256 samples should trigger catch-up
      // The backlog (2000) exceeds the threshold (512), so it should discard down to 512
      // and then read 256, leaving exactly 256 unread samples.
      std::vector<float> dest(256, 0.0f);
      worker.readCapturedSamples(dest.data(), dest.size());

      EXPECT_EQ(worker.getBufferedSampleCount(), 256);
  }
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `cmake --build build --config Release; build\bin\Release\AudioEngineTests.exe --gtest_filter=WASAPIDeviceWorkerTest.*`
  Expected: Compilation error (missing `getBufferedSampleCount()`, etc.).

- [ ] **Step 3: Update WASAPIDeviceWorker.h**
  Modify [WASAPIDeviceWorker.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.h) to:
  - Add `size_t getBufferedSampleCount() const noexcept`
  - Mark `m_ringMutex` as `mutable` so it can be locked in a `const` function:
  ```cpp
  // ... line 27 ...
      bool isRunning() const noexcept { return m_running.load(std::memory_order_relaxed); }
      std::wstring getDeviceName() const noexcept { return m_deviceName; }
      size_t getBufferedSampleCount() const noexcept;
  ```
  ```cpp
  // ... line 50 ...
      mutable std::mutex m_ringMutex;
  ```

- [ ] **Step 4: Update WASAPIDeviceWorker.cpp**
  Modify [WASAPIDeviceWorker.cpp](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.cpp):
  - Implement `getBufferedSampleCount()`:
    ```cpp
    size_t WASAPIDeviceWorker::getBufferedSampleCount() const noexcept {
        std::lock_guard<std::mutex> lock(m_ringMutex);
        return (m_ringWritePos >= m_ringReadPos) ? 
               (m_ringWritePos - m_ringReadPos) : 
               (m_ringBuffer.size() - m_ringReadPos + m_ringWritePos);
    }
    ```
  - Modify `readCapturedSamples` to check backlog and skip oldest samples if `backlog > 512`:
    ```cpp
    void WASAPIDeviceWorker::readCapturedSamples(float* destBuffer, size_t numSamples) noexcept {
        std::lock_guard<std::mutex> lock(m_ringMutex);
        
        size_t buffered = (m_ringWritePos >= m_ringReadPos) ? 
                          (m_ringWritePos - m_ringReadPos) : 
                          (m_ringBuffer.size() - m_ringReadPos + m_ringWritePos);
                          
        if (buffered > 512) {
            m_ringReadPos = (m_ringWritePos - 512 + m_ringBuffer.size()) % m_ringBuffer.size();
        }

        for (size_t i = 0; i < numSamples; ++i) {
            if (m_ringReadPos != m_ringWritePos) {
                destBuffer[i] = m_ringBuffer[m_ringReadPos];
                m_ringReadPos = (m_ringReadPos + 1) % m_ringBuffer.size();
            } else {
                destBuffer[i] = 0.0f; // Silence fallback
            }
        }
    }
    ```
  - Modify Render loop `runLoop()` (around line 152) to check backlog and skip if `backlog > framesToWrite + 512`:
    ```cpp
                        std::lock_guard<std::mutex> lock(m_ringMutex);
                        
                        size_t buffered = (m_ringWritePos >= m_ringReadPos) ? 
                                          (m_ringWritePos - m_ringReadPos) : 
                                          (m_ringBuffer.size() - m_ringReadPos + m_ringWritePos);
                                          
                        size_t maxAllowed = framesToWrite + 512;
                        if (buffered > maxAllowed) {
                            m_ringReadPos = (m_ringWritePos - (framesToWrite + 256) + m_ringBuffer.size()) % m_ringBuffer.size();
                        }

                        int channels = m_mixFormat->nChannels;
    ```

- [ ] **Step 5: Run tests to verify they pass**
  Run: `cmake --build build --config Release; build\bin\Release\AudioEngineTests.exe --gtest_filter=WASAPIDeviceWorkerTest.*`
  Expected: PASS.

- [ ] **Step 6: Commit**
  ```bash
  git add src/core/audio/WASAPIDeviceWorker.h src/core/audio/WASAPIDeviceWorker.cpp tests/DynamicAudioEngineTests.cpp
  git commit -m "feat(audio): implement low-latency catch-up discard logic in WASAPIDeviceWorker"
  ```

---

### Task 2: Implement High-Precision Thread Pacing in AudioEngineBridge

**Files:**
- Modify: [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp)

- [ ] **Step 1: Wire precision timing and timer resolution**
  At the top of `src/ui/AudioEngineBridge.cpp`, include:
  ```cpp
  #include <windows.h>
  #include <timeapi.h>
  #pragma comment(lib, "winmm.lib")
  ```

- [ ] **Step 2: Update m_simulatedAudioThread pacing logic**
  Replace the simulated audio thread loop inside `AudioEngineBridge::AudioEngineBridge(QObject*)` constructor (around line 84-145):
  - Request `timeBeginPeriod(1)` on thread startup and `timeEndPeriod(1)` on thread exit.
  - Implement pacing check:
    - If `!m_captureWorkers.empty()`: Wait (sleep 1ms) if `m_captureWorkers[0]->getBufferedSampleCount() < 256`.
    - If `m_captureWorkers.empty()`: Use high-precision steady-clock pacing.
  ```cpp
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
  ```

- [ ] **Step 3: Verify compilation**
  Run: `cmake --build build --config Release`
  Expected: Success.

- [ ] **Step 4: Run unit tests**
  Run: `build\bin\Release\AudioEngineTests.exe`
  Expected: PASS.

- [ ] **Step 5: Commit**
  ```bash
  git add src/ui/AudioEngineBridge.cpp
  git commit -m "feat(audio): enable 1ms system timer and implement hardware-aligned pacing loop"
  ```

---

## 3. Verification Plan

### Automated Tests
Run: `.\build\bin\Release\AudioEngineTests.exe`

### Manual Verification
1. Launch Overwatch Studio: `.\build\bin\Release\overwatch_studio.exe`
2. Talk into the microphone.
3. Observe peak level meters response.
4. Verify response is instantaneous (sub-20ms latency) and audio is continuous without stutter.
