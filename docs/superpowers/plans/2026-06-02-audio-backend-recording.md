# Low-Latency Multitrack DAW Recording & Dynamic Engine Scaling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement fully dynamic channel scaling and low-latency, zero-allocation asynchronous multitrack WAV recording on the audio backend.

**Architecture:** Use active count masking over pre-allocated maximum capacity pools to scale fader layouts instantly. Stream raw PCM audio chunks in blocks of 256 samples through lock-free SPSC queues to a background disk-writer thread pool writing uncompressed 24-bit mono WAV files.

**Tech Stack:** C++17, moodycamel ReaderWriterQueue, standard file I/O streams, GoogleTest framework.

---

## 1. Directory & File Mapping

We will create two new header-only utility components and modify the core summing engine and bridges:
- **Create:** [WavFileWriter.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WavFileWriter.h) — Lightweight 24-bit mono WAV file writer.
- **Create:** [AudioRecorderManager.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioRecorderManager.h) — Multitrack recording background thread pool.
- **Modify:** [AudioEngineCore.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioEngineCore.h) — Dynamic reconfiguration and real-time block streaming.
- **Modify:** [AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h) / [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp) — Qt slots for arming, triggering, and sizing.
- **Modify:** [DynamicAudioEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/DynamicAudioEngineTests.cpp) — Verification tests for scaling and asynchronous file I/O.

---

## 2. Step-by-Step Execution Plan

### Task 1: Implement Lightweight WavFileWriter

**Files:**
- Create: [WavFileWriter.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WavFileWriter.h)
- Test: [DynamicAudioEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/DynamicAudioEngineTests.cpp)

- [ ] **Step 1: Write the failing test**
  Add a unit test to `tests/DynamicAudioEngineTests.cpp` that attempts to open, write to, and close a `WavFileWriter` to verify compilation failure first:
  ```cpp
  #include "WavFileWriter.h"
  TEST(WavFileWriterTest, VerifyFileCreationAndHeader) {
      WavFileWriter writer;
      bool ok = writer.open("test_out.wav", 48000);
      EXPECT_TRUE(ok);
      std::vector<float> buffer(512, 0.5f);
      writer.writeSamples(buffer.data(), buffer.size());
      writer.close();
      
      // Read file back to verify header is 44 bytes and data was written
      std::ifstream in("test_out.wav", std::ios::binary);
      ASSERT_TRUE(in.is_open());
      char header[44];
      in.read(header, 44);
      EXPECT_EQ(std::string(header, 4), "RIFF");
      EXPECT_EQ(std::string(header + 8, 4), "WAVE");
  }
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `cmake --build build --config Release`
  Expected: Compilation error (missing `WavFileWriter.h`).

- [ ] **Step 3: Write minimal implementation**
  Create `src/core/audio/WavFileWriter.h` containing the standard C++ class:
  ```cpp
  #pragma once
  #include <fstream>
  #include <vector>
  #include <string>
  #include <algorithm>
  #include <cstdint>

  class WavFileWriter {
  public:
      WavFileWriter() = default;
      ~WavFileWriter() { close(); }

      bool open(const std::string& filePath, uint32_t sampleRate) {
          m_file.open(filePath, std::ios::binary);
          if (!m_file.is_open()) return false;
          m_sampleRate = sampleRate;
          m_totalDataBytes = 0;

          std::vector<char> placeholder(44, 0);
          m_file.write(placeholder.data(), placeholder.size());
          return true;
      }

      void writeSamples(const float* floatSamples, size_t count) {
          if (!m_file.is_open()) return;

          std::vector<uint8_t> bytes;
          bytes.reserve(count * 3);

          for (size_t i = 0; i < count; ++i) {
              float clamped = std::max(-1.0f, std::min(1.0f, floatSamples[i]));
              int32_t val = static_cast<int32_t>(clamped * 8388607.0f);
              bytes.push_back(static_cast<uint8_t>(val & 0xFF));
              bytes.push_back(static_cast<uint8_t>((val >> 8) & 0xFF));
              bytes.push_back(static_cast<uint8_t>((val >> 16) & 0xFF));
          }

          m_file.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
          m_totalDataBytes += bytes.size();
      }

      void close() {
          if (!m_file.is_open()) return;

          m_file.seekp(0);
          uint32_t fileSizeMinus8 = 36 + m_totalDataBytes;
          uint32_t subChunk1Size = 16;
          uint16_t audioFormat = 1;
          uint16_t numChannels = 1;
          uint16_t bitsPerSample = 24;
          uint16_t blockAlign = 3;
          uint32_t byteRate = m_sampleRate * blockAlign;

          m_file.write("RIFF", 4);
          m_file.write(reinterpret_cast<const char*>(&fileSizeMinus8), 4);
          m_file.write("WAVEfmt ", 8);
          m_file.write(reinterpret_cast<const char*>(&subChunk1Size), 4);
          m_file.write(reinterpret_cast<const char*>(&audioFormat), 2);
          m_file.write(reinterpret_cast<const char*>(&numChannels), 2);
          m_file.write(reinterpret_cast<const char*>(&m_sampleRate), 4);
          m_file.write(reinterpret_cast<const char*>(&byteRate), 4);
          m_file.write(reinterpret_cast<const char*>(&blockAlign), 2);
          m_file.write(reinterpret_cast<const char*>(&bitsPerSample), 2);
          m_file.write("data", 4);
          m_file.write(reinterpret_cast<const char*>(&m_totalDataBytes), 4);

          m_file.close();
      }

  private:
      std::ofstream m_file;
      uint32_t m_sampleRate = 48000;
      uint32_t m_totalDataBytes = 0;
  };
  ```

- [ ] **Step 4: Run test to verify it passes**
  Compile and run GTest:
  `cmake --build build --config Release`
  `build/bin/Release/AudioEngineTests.exe`
  Expected: Test passes cleanly.

- [ ] **Step 5: Commit**
  ```bash
  git add src/core/audio/WavFileWriter.h tests/DynamicAudioEngineTests.cpp
  git commit -m "feat(audio): implement lightweight WavFileWriter and unit tests"
  ```

---

### Task 2: Implement Background Threaded AudioRecorderManager

**Files:**
- Create: [AudioRecorderManager.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioRecorderManager.h)
- Test: [DynamicAudioEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/DynamicAudioEngineTests.cpp)

- [ ] **Step 1: Write the failing test**
  Add a unit test checking that `AudioRecorderManager` creates channels and runs a thread pool:
  ```cpp
  #include "AudioRecorderManager.h"
  TEST(AudioRecorderManagerTest, VerifyAsynchronousWriting) {
      AudioRecorderManager manager;
      manager.initialize(4, "test_session");
      manager.startSession(48000);
      
      // Push some test blocks
      AudioRecordBlock block;
      block.samples.fill(0.2f);
      block.count = 256;
      
      bool ok = manager.pushBlock(0, block);
      EXPECT_TRUE(ok);
      
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
      manager.stopSession();
  }
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run: `cmake --build build --config Release`
  Expected: Compilation error (missing `AudioRecorderManager.h`).

- [ ] **Step 3: Write minimal implementation**
  Create `src/core/audio/AudioRecorderManager.h`:
  ```cpp
  #pragma once
  #include "WavFileWriter.h"
  #include "../control/SPSCQueue.h"
  #include <thread>
  #include <atomic>
  #include <vector>
  #include <memory>
  #include <filesystem>

  struct AudioRecordBlock {
      static constexpr size_t BlockSize = 256;
      std::array<float, BlockSize> samples;
      size_t count = 0;
  };

  class AudioRecorderManager {
  public:
      AudioRecorderManager() : m_active(false) {}
      ~AudioRecorderManager() { stopSession(); }

      void initialize(size_t channelCount, const std::string& sessionName) {
          m_channelCount = channelCount;
          m_sessionName = sessionName;
          
          m_queues.clear();
          for (size_t i = 0; i < m_channelCount; ++i) {
              m_queues.push_back(std::make_unique<SPSCQueue<AudioRecordBlock>>(2048));
          }
      }

      void startSession(uint32_t sampleRate) {
          if (m_active.load()) return;
          m_sampleRate = sampleRate;
          m_active.store(true);

          std::filesystem::create_directories(m_sessionName);

          m_writerThread = std::thread([this]() {
              std::vector<std::unique_ptr<WavFileWriter>> writers;
              for (size_t i = 0; i < m_channelCount; ++i) {
                  auto writer = std::make_unique<WavFileWriter>();
                  std::string path = m_sessionName + "/track_" + std::to_string(i + 1) + ".wav";
                  writer->open(path, m_sampleRate);
                  writers.push_back(std::move(writer));
              }

              while (m_active.load()) {
                  bool processedAny = false;
                  for (size_t i = 0; i < m_channelCount; ++i) {
                      if (auto blockOpt = m_queues[i]->pop()) {
                          writers[i]->writeSamples(blockOpt->samples.data(), blockOpt->count);
                          processedAny = true;
                      }
                  }
                  if (!processedAny) {
                      std::this_thread::sleep_for(std::chrono::milliseconds(2));
                  }
              }

              // Drain remaining queues
              for (size_t i = 0; i < m_channelCount; ++i) {
                  while (auto blockOpt = m_queues[i]->pop()) {
                      writers[i]->writeSamples(blockOpt->samples.data(), blockOpt->count);
                  }
                  writers[i]->close();
              }
          });
      }

      void stopSession() {
          if (!m_active.load()) return;
          m_active.store(false);
          if (m_writerThread.joinable()) {
              m_writerThread.join();
          }
      }

      bool pushBlock(size_t channelIdx, const AudioRecordBlock& block) noexcept {
          if (!m_active.load() || channelIdx >= m_queues.size()) return false;
          return m_queues[channelIdx]->push(block);
      }

  private:
      size_t m_channelCount = 0;
      uint32_t m_sampleRate = 48000;
      std::string m_sessionName;
      std::atomic<bool> m_active;
      std::thread m_writerThread;
      std::vector<std::unique_ptr<SPSCQueue<AudioRecordBlock>>> m_queues;
  };
  ```

- [ ] **Step 4: Run test to verify it passes**
  Compile and run tests:
  `cmake --build build --config Release`
  `build/bin/Release/AudioEngineTests.exe`
  Expected: Tests pass cleanly.

- [ ] **Step 5: Commit**
  ```bash
  git add src/core/audio/AudioRecorderManager.h tests/DynamicAudioEngineTests.cpp
  git commit -m "feat(audio): implement background AudioRecorderManager multitrack loop"
  ```

---

### Task 3: Integrate Reconfiguration & Recording in AudioEngineCore

**Files:**
- Modify: [AudioEngineCore.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioEngineCore.h)
- Test: [DynamicAudioEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/DynamicAudioEngineTests.cpp)

- [ ] **Step 1: Declare properties and configure method**
  Add atomic active channel counts, a recording accumulator buffer, and recording flags to `AudioEngineCore.h` (around lines 55-90):
  ```cpp
      size_t getActiveSampleRate() const noexcept { return static_cast<size_t>(activeSampleRate); }
      
      void configureEngine(size_t numInputs, size_t numBuses, size_t numAuxes, size_t numDCAs) noexcept {
          activeInputsCount.store(std::min(numInputs, MaxInputs));
          activeBusesCount.store(std::min(numBuses, MaxBuses));
          activeAuxesCount.store(std::min(numAuxes, MaxAuxes));
          activeDCAsCount.store(std::min(numDCAs, MaxDCAs));

          size_t faderIdx = 0;
          for (size_t i = 0; i < activeInputsCount.load() && faderIdx < faderStrips.size(); ++i) {
              faderStrips[faderIdx++] = &channelPool[i];
          }
          
          size_t dcaStartIdx = MaxInputs + MaxBuses + MaxAuxes + MaxFX;
          for (size_t i = 0; i < activeDCAsCount.load() && faderIdx < faderStrips.size(); ++i) {
              faderStrips[faderIdx++] = &channelPool[dcaStartIdx + i];
          }

          while (faderIdx < faderStrips.size()) {
              faderStrips[faderIdx++] = nullptr;
          }

          routingMatrix.clearAllRoutes();
      }
  ```

- [ ] **Step 2: Stream audio samples inside callback**
  Add a real-time safe record streaming chunk inside `audioDeviceIOCallbackWithContext`. We will write an inner check that aggregates blocks of 256 samples per active input, then pushes them to `m_recorder`:
  ```cpp
      // Add these private variables at the end of AudioEngineCore class:
      std::atomic<size_t> activeInputsCount{24};
      std::atomic<size_t> activeBusesCount{8};
      std::atomic<size_t> activeAuxesCount{8};
      std::atomic<size_t> activeDCAsCount{8};

  public:
      // Recorder setter
      void setRecorder(AudioRecorderManager* recorder) noexcept {
          m_recorder = recorder;
      }
      
      bool isRecordingArmed() const noexcept { return m_recordingArmed.load(); }
      void setRecordingArmed(bool armed) noexcept { m_recordingArmed.store(armed); }

  private:
      AudioRecorderManager* m_recorder = nullptr;
      std::atomic<bool> m_recordingArmed{false};
      std::array<AudioRecordBlock, InputChannelsCount> m_recordBlocks{};
  ```
  Now, inside `audioDeviceIOCallbackWithContext`, append samples for armed tracks:
  ```cpp
          // 5. Append to recording buffers if armed
          if (m_recordingArmed.load() && m_recorder != nullptr) {
              for (size_t c = 0; c < inputs; ++c) {
                  auto& rb = m_recordBlocks[c];
                  for (size_t s = 0; s < samples; ++s) {
                      rb.samples[rb.count++] = inputBufferPtrs[c][s];
                      if (rb.count >= AudioRecordBlock::BlockSize) {
                          m_recorder->pushBlock(c, rb);
                          rb.count = 0;
                      }
                  }
              }
          }
  ```

- [ ] **Step 3: Verify dynamic reconfiguration in GTest**
  Add a GTest test block in `tests/DynamicAudioEngineTests.cpp` confirming that after calling `configureEngine(12, 0, 0, 4)`, active inputs limit correctly gates strips allocation.

- [ ] **Step 4: Compile and check**
  Run: `cmake --build build --config Release`
  Verify all tests compile and pass.

- [ ] **Step 5: Commit**
  ```bash
  git add src/core/audio/AudioEngineCore.h tests/DynamicAudioEngineTests.cpp
  git commit -m "feat(audio-core): implement active count masking and real-time record blocks streaming"
  ```

---

### Task 4: Connect to Qt AudioEngineBridge Controls

**Files:**
- Modify: [AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h)
- Modify: [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp)

- [ ] **Step 1: Declare slots and properties**
  In `AudioEngineBridge.h`:
  - Include `#include "../core/audio/AudioRecorderManager.h"`
  - Declare slots `armRecording(bool armed)`, `triggerRecording(bool active)`, and `configureShowChannels(int numInputs, int numBuses, int numAuxes, int numDCAs)`.
  - Expose Q_PROPERTIES `recordArmed` and `recordingActive`.

- [ ] **Step 2: Implement slots**
  In `AudioEngineBridge.cpp`, initialize `AudioRecorderManager` during construction:
  ```cpp
      m_recorderManager = std::make_unique<AudioRecorderManager>();
      m_recorderManager->initialize(24, "recording_session_" + QDateTime::currentDateTime().toString("yyyy-MM-dd_hhmmss").toStdString());
      m_engine->setRecorder(m_recorderManager.get());
  ```
  Implement the slots `armRecording(bool armed)` and `triggerRecording(bool active)` which call `m_engine->setRecordingArmed(armed)` and `m_recorderManager->startSession(...)` / `m_recorderManager->stopSession()`.

- [ ] **Step 3: Rebuild and Verify**
  Compile the final package:
  `cmake --build build --config Release`
  `build/bin/Release/AudioEngineTests.exe`

- [ ] **Step 4: Commit**
  ```bash
  git add src/ui/AudioEngineBridge.h src/ui/AudioEngineBridge.cpp
  git commit -m "feat(bridge): wire multitrack recording and active scaling controls to Qt GUI shell"
  ```
