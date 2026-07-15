# Local Media Deck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate a Local Media Deck (audio/video player and presenter) supporting play/pause, seek, looping, visual overlays (dynamic waveforms, timecodes), and stereo audio streaming into the mixer.

**Architecture:** Create a QObject-based `LocalMediaDeck` controller class in `src/ui/`. Update `AudioSourceType` in `RoutingPatchMap.h` to support `Media` = 4. Connect `AudioEngineCore` to read stereo audio from the media deck when patched. Add a dynamic fifth input channel ("MEDIA") in `VideoCanvasMock` and `Main.qml`, and build the Media Deck controls panel at the bottom of the video switcher console.

**Tech Stack:** C++, Qt 6 QML, Direct3D 11 / QPainter, GoogleTest.

---

## 1. Directory & File Mapping

- **Create:** [LocalMediaDeck.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/LocalMediaDeck.h) / [LocalMediaDeck.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/LocalMediaDeck.cpp) — Implement the media playback state, dynamic audio pad generator, and canvas paint renderer.
- **Modify:** [RoutingPatchMap.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/RoutingPatchMap.h) — Add `Media` to `AudioSourceType`.
- **Modify:** [AudioEngineCore.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioEngineCore.h) — Integrate `LocalMediaDeck` pointer and read samples in the DSP loop.
- **Modify:** [AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h) / [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp) — Instantiate and expose the media deck to QML, and route patching commands.
- **Modify:** [VideoCanvasMock.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/VideoCanvasMock.h) / [VideoCanvasMock.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/VideoCanvasMock.cpp) — Support fifth source rendering from the media deck (dynamic oscilloscope/waveform and timecode overlay).
- **Modify:** [CMakeLists.txt](file:///f:/Drive/scripts/overwatch_studio/CMakeLists.txt) — Add new source files to compilation targets.
- **Modify:** [DynamicAudioEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/DynamicAudioEngineTests.cpp) — Add unit tests for media patching, audio streaming, and playback control lifecycle.
- **Modify:** [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml) — Expand switcher PGM/PVW buses to support 5 sources, display "MEDIA" selection, and construct the media deck playback controls panel at the bottom of the video window.

---

## 2. Step-by-Step Execution Plan

### Task 1: Update Constants and CMake

**Files:**
- Modify: [RoutingPatchMap.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/RoutingPatchMap.h)
- Modify: [CMakeLists.txt](file:///f:/Drive/scripts/overwatch_studio/CMakeLists.txt)

- [ ] **Step 1: Modify RoutingPatchMap.h**
  Add `Media` to `AudioSourceType` at line 15:
  ```cpp
  enum class AudioSourceType : uint8_t {
      None = 0,
      Hardware = 1,
      Generator = 2,
      AppCapture = 3,
      Media = 4
  };
  ```

- [ ] **Step 2: Modify CMakeLists.txt**
  Add `src/ui/LocalMediaDeck.cpp` and `src/ui/LocalMediaDeck.h` to both `AudioEngineTests` and `overwatch_studio` targets:
  ```cmake
  # lines 91-100 (AudioEngineTests)
  add_executable(AudioEngineTests
      tests/AudioEngineTests.cpp
      tests/DynamicAudioEngineTests.cpp
      tests/ControlEngineTests.cpp
      tests/VideoEngineTests.cpp
      src/core/audio/WASAPIDeviceWorker.cpp
      src/core/audio/WASAPIDeviceWorker.h
      src/core/audio/WindowsProcessCapture.cpp
      src/core/audio/WindowsProcessCapture.h
      src/ui/LocalMediaDeck.cpp
      src/ui/LocalMediaDeck.h
  )
  ```
  ```cmake
  # lines 116-128 (overwatch_studio)
  add_executable(overwatch_studio 
      src/main.cpp
      src/ui/AudioEngineBridge.cpp
      src/ui/AudioEngineBridge.h
      src/ui/VideoCanvasMock.cpp
      src/ui/VideoCanvasMock.h
      src/ui/ShowBuilderBridge.cpp
      src/ui/ShowBuilderBridge.h
      src/core/audio/WindowsProcessCapture.cpp
      src/core/audio/WindowsProcessCapture.h
      src/core/audio/WASAPIDeviceWorker.cpp
      src/core/audio/WASAPIDeviceWorker.h
      src/ui/LocalMediaDeck.cpp
      src/ui/LocalMediaDeck.h
  )
  ```

- [ ] **Step 3: Run CMake configuration**
  Run: `cmake -B build -S .`
  Expected: Successful configuration without errors.

- [ ] **Step 4: Commit changes**
  ```bash
  git add src/core/audio/RoutingPatchMap.h CMakeLists.txt
  git commit -m "build(cmake): add Media source type and declare LocalMediaDeck files"
  ```

---

### Task 2: Create LocalMediaDeck Component

**Files:**
- Create: [LocalMediaDeck.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/LocalMediaDeck.h)
- Create: [LocalMediaDeck.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/LocalMediaDeck.cpp)

- [ ] **Step 1: Create LocalMediaDeck.h**
  Define properties, methods, and real-time safe audio/video generation callbacks:
  ```cpp
  #pragma once
  #include <QObject>
  #include <QString>
  #include <QImage>
  #include <atomic>
  #include <mutex>

  class LocalMediaDeck : public QObject {
      Q_OBJECT
      Q_PROPERTY(bool playing READ isPlaying WRITE setPlaying NOTIFY playingChanged)
      Q_PROPERTY(int duration READ duration NOTIFY durationChanged)
      Q_PROPERTY(int position READ position WRITE setPosition NOTIFY positionChanged)
      Q_PROPERTY(QString filePath READ filePath WRITE setFilePath NOTIFY filePathChanged)
      Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
      Q_PROPERTY(bool loop READ loop WRITE setLoop NOTIFY loopChanged)
      Q_PROPERTY(double playbackProgress READ playbackProgress NOTIFY playbackProgressChanged)

  public:
      explicit LocalMediaDeck(QObject* parent = nullptr);
      ~LocalMediaDeck();

      bool isPlaying() const { return m_playing.load(std::memory_order_relaxed); }
      void setPlaying(bool play);

      int duration() const { return m_duration.load(std::memory_order_relaxed); }
      int position() const { return m_position.load(std::memory_order_relaxed); }
      void setPosition(int pos);

      QString filePath() const;
      void setFilePath(const QString& path);

      double volume() const { return m_volume.load(std::memory_order_relaxed); }
      void setVolume(double vol);

      bool loop() const { return m_loop.load(std::memory_order_relaxed); }
      void setLoop(bool lp);

      double playbackProgress() const;

      Q_INVOKABLE void play();
      Q_INVOKABLE void pause();
      Q_INVOKABLE void stop();
      Q_INVOKABLE void load(const QString& path);

      // Real-time audio callback (lock-free)
      void readPlaybackSamples(uint32_t patchIdx, float* destBuffer, size_t numSamples) noexcept;

      // Video canvas frame painter (invoked by VideoCanvasMock)
      void generateVideoFrame(QImage& image, int frameCount, int width, int height);

  signals:
      void playingChanged();
      void durationChanged();
      void positionChanged();
      void filePathChanged();
      void volumeChanged();
      void loopChanged();
      void playbackProgressChanged();

  private:
      void updateTimerTick();

      std::atomic<bool> m_playing{false};
      std::atomic<int> m_duration{120}; // default mock duration 120s
      std::atomic<int> m_position{0};
      std::atomic<double> m_volume{1.0};
      std::atomic<bool> m_loop{true};

      mutable std::mutex m_fileMutex;
      QString m_filePath;

      double m_phaseL = 0.0;
      double m_phaseR = 0.0;

      class QTimer* m_tickTimer = nullptr;
  };
  ```

- [ ] **Step 2: Create LocalMediaDeck.cpp**
  Implement properties, 1-second interval ticking timer, and the audio/video mock generation:
  ```cpp
  #include "LocalMediaDeck.h"
  #include <QTimer>
  #include <QPainter>
  #include <QColor>
  #include <QPen>
  #include <QFont>
  #include <cmath>

  LocalMediaDeck::LocalMediaDeck(QObject* parent) : QObject(parent) {
      m_tickTimer = new QTimer(this);
      connect(m_tickTimer, &QTimer::timeout, this, &LocalMediaDeck::updateTimerTick);
      m_tickTimer->start(1000); // Trigger tick every second
  }

  LocalMediaDeck::~LocalMediaDeck() {
      m_tickTimer->stop();
  }

  void LocalMediaDeck::setPlaying(bool play) {
      if (m_playing.load() != play) {
          m_playing.store(play);
          emit playingChanged();
          emit playbackProgressChanged();
      }
  }

  void LocalMediaDeck::setPosition(int pos) {
      int dur = m_duration.load();
      int clamped = std::max(0, std::min(pos, dur));
      if (m_position.load() != clamped) {
          m_position.store(clamped);
          emit positionChanged();
          emit playbackProgressChanged();
      }
  }

  QString LocalMediaDeck::filePath() const {
      std::lock_guard<std::mutex> lock(m_fileMutex);
      return m_filePath;
  }

  void LocalMediaDeck::setFilePath(const QString& path) {
      std::lock_guard<std::mutex> lock(m_fileMutex);
      if (m_filePath != path) {
          m_filePath = path;
          emit filePathChanged();
      }
  }

  void LocalMediaDeck::setVolume(double vol) {
      double clamped = std::max(0.0, std::min(vol, 1.0));
      if (m_volume.load() != clamped) {
          m_volume.store(clamped);
          emit volumeChanged();
      }
  }

  void LocalMediaDeck::setLoop(bool lp) {
      if (m_loop.load() != lp) {
          m_loop.store(lp);
          emit loopChanged();
      }
  }

  double LocalMediaDeck::playbackProgress() const {
      int dur = m_duration.load();
      if (dur <= 0) return 0.0;
      return static_cast<double>(m_position.load()) / dur;
  }

  void LocalMediaDeck::play() {
      setPlaying(true);
  }

  void LocalMediaDeck::pause() {
      setPlaying(false);
  }

  void LocalMediaDeck::stop() {
      setPlaying(false);
      setPosition(0);
  }

  void LocalMediaDeck::load(const QString& path) {
      stop();
      setFilePath(path);
      // Mock duration parsing: set different durations based on file name length
      int dur = 60 + (path.length() * 3) % 180;
      m_duration.store(dur);
      emit durationChanged();
  }

  void LocalMediaDeck::updateTimerTick() {
      if (m_playing.load()) {
          int pos = m_position.load();
          int dur = m_duration.load();
          if (pos < dur) {
              m_position.store(pos + 1);
              emit positionChanged();
              emit playbackProgressChanged();
          } else {
              if (m_loop.load()) {
                  m_position.store(0);
                  emit positionChanged();
                  emit playbackProgressChanged();
              } else {
                  setPlaying(false);
              }
          }
      }
  }

  void LocalMediaDeck::readPlaybackSamples(uint32_t patchIdx, float* destBuffer, size_t numSamples) noexcept {
      if (!m_playing.load(std::memory_order_relaxed)) {
          std::fill_n(destBuffer, numSamples, 0.0f);
          return;
      }

      double vol = m_volume.load(std::memory_order_relaxed);
      bool isLeft = (patchIdx % 2 == 0);

      // Generate a rich polyphonic synth texture using a C major chord
      const double freqs[4] = { 130.81, 164.81, 196.00, 246.94 }; // C3, E3, G3, B3
      double& phase = isLeft ? m_phaseL : m_phaseR;

      for (size_t s = 0; s < numSamples; ++s) {
          double sum = 0.0;
          for (int i = 0; i < 4; ++i) {
              double freq = freqs[i] * (isLeft ? 1.0 : 1.002); // slight detuning for width
              sum += std::sin(phase + i * 1.5);
          }
          sum *= 0.25;

          // Apply filter sweep using LFO
          double t = static_cast<double>(m_position.load()) + static_cast<double>(s) / 48000.0;
          double lfo = 0.6 + 0.4 * std::sin(2.0 * 3.14159265 * 0.25 * t); // 0.25Hz LFO
          
          destBuffer[s] = static_cast<float>(sum * vol * lfo);

          phase += 2.0 * 3.14159265 * 130.81 / 48000.0;
          if (phase >= 2.0 * 3.14159265) phase -= 2.0 * 3.14159265;
      }
  }

  void LocalMediaDeck::generateVideoFrame(QImage& image, int frameCount, int width, int height) {
      if (image.width() != width || image.height() != height || image.format() != QImage::Format_ARGB32) {
          image = QImage(width, height, QImage::Format_ARGB32);
      }
      
      image.fill(QColor("#0a0c10"));
      
      QPainter painter(&image);
      painter.setRenderHint(QPainter::Antialiasing);

      // Draw grid
      painter.setPen(QPen(QColor("#151b24"), 1));
      int gridSize = 40;
      for (int x = 0; x < width; x += gridSize) {
          painter.drawLine(x, 0, x, height);
      }
      for (int y = 0; y < height; y += gridSize) {
          painter.drawLine(0, y, width, y);
      }

      int posVal = m_position.load();
      int durVal = m_duration.load();
      double progress = durVal > 0 ? static_cast<double>(posVal) / durVal : 0.0;

      // Draw dynamic visual waves
      painter.setPen(QPen(QColor("#00bdd6"), 2));
      int centerY = height / 2;
      int waveHeight = 60;
      QPainterPath path;
      path.moveTo(0, centerY);
      for (int x = 0; x < width; ++x) {
          double wavePhase = static_cast<double>(x) * 0.05 + (m_playing.load() ? static_cast<double>(frameCount) * 0.2 : 0.0);
          double amp = std::sin(wavePhase) * std::cos(wavePhase * 0.3);
          double val = centerY + amp * waveHeight * (m_playing.load() ? 1.0 : 0.1);
          path.lineTo(x, val);
      }
      painter.drawPath(path);

      // Text overlays
      painter.setPen(QColor("#ffffff"));
      QFont font = painter.font();
      font.setFamily("Segoe UI");
      font.setBold(true);
      font.setPixelSize(20);
      painter.setFont(font);
      
      QString stateText = m_playing.load() ? "PLAYING" : "PAUSED";
      if (posVal == 0 && !m_playing.load()) stateText = "STOPPED";
      painter.drawText(20, 40, "MEDIA DECK: " + stateText);

      font.setBold(false);
      font.setPixelSize(14);
      painter.setFont(font);
      QString file;
      {
          std::lock_guard<std::mutex> lock(m_fileMutex);
          file = m_filePath.isEmpty() ? "No File Loaded" : m_filePath;
      }
      painter.drawText(20, 70, "FILE: " + file);

      // Progress bar
      int barY = height - 50;
      int barW = width - 40;
      painter.fillRect(20, barY, barW, 8, QColor("#1a1c1e"));
      painter.fillRect(20, barY, static_cast<int>(barW * progress), 8, QColor("#00bdd6"));

      // Timecode string
      int min = posVal / 60;
      int sec = posVal % 60;
      int durMin = durVal / 60;
      int durSec = durVal % 60;
      QString timeStr = QString("%1:%2 / %3:%4")
          .arg(min, 2, 10, QChar('0'))
          .arg(sec, 2, 10, QChar('0'))
          .arg(durMin, 2, 10, QChar('0'))
          .arg(durSec, 2, 10, QChar('0'));
      painter.drawText(20, barY - 10, timeStr);
  }
  ```

- [ ] **Step 3: Verify build**
  Compile the project to confirm that the new component compiles cleanly:
  `cmake --build build --config Release`

- [ ] **Step 4: Commit component**
  ```bash
  git add src/ui/LocalMediaDeck.h src/ui/LocalMediaDeck.cpp
  git commit -m "feat(ui): implement LocalMediaDeck component for audio/video playback simulation"
  ```

---

### Task 3: Integrate with Audio Mixer DSP Engine

**Files:**
- Modify: [AudioEngineCore.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioEngineCore.h)
- Modify: [AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h)
- Modify: [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp)

- [ ] **Step 1: Integrate LocalMediaDeck in AudioEngineCore.h**
  Add pointer to `LocalMediaDeck` and update sample pulling in the DSP loop:
  1. Include `#include "../../ui/LocalMediaDeck.h"` at the top of `AudioEngineCore.h`.
  2. Declare `LocalMediaDeck* m_mediaDeck = nullptr;` inside the private section (around line 346).
  3. Implement `void setMediaDeck(LocalMediaDeck* deck) noexcept { m_mediaDeck = deck; }` public setter.
  4. In `audioDeviceIOCallbackWithContext`, add the `Media` source handler (around line 321):
     ```cpp
                 } else if (patch.type == AudioSourceType::Media) {
                     if (m_mediaDeck != nullptr) {
                         m_mediaDeck->readPlaybackSamples(patch.index, dest, samples);
                     } else {
                         std::fill_n(dest, samples, 0.0f);
                     }
                 }
     ```
  5. In `setInputPatch` command handler (around line 197), check up to `AudioSourceType::Media`:
     ```cpp
                     if (cmd.targetIdx <= static_cast<uint32_t>(AudioSourceType::Media)) {
                         setInputPatch(cmd.channelIdx, static_cast<AudioSourceType>(cmd.targetIdx), cmd.flag);
                     }
     ```

- [ ] **Step 2: Declare and register Media Deck in AudioEngineBridge**
  Modify `AudioEngineBridge.h`:
  1. Forward declare `class LocalMediaDeck;`
  2. Add Q_PROPERTY:
     ```cpp
     Q_PROPERTY(LocalMediaDeck* mediaDeck READ mediaDeck CONSTANT)
     ```
  3. Declare getter:
     ```cpp
     LocalMediaDeck* mediaDeck() const { return m_mediaDeck.get(); }
     ```
  4. Add private member:
     ```cpp
     std::unique_ptr<LocalMediaDeck> m_mediaDeck;
     ```
  Modify `AudioEngineBridge.cpp`:
  1. Include `#include "LocalMediaDeck.h"` at the top of the file.
  2. In constructor, initialize `m_mediaDeck` and link it to the DSP core:
     ```cpp
     m_mediaDeck = std::make_unique<LocalMediaDeck>(this);
     m_engine->setMediaDeck(m_mediaDeck.get());
     ```
  3. In the constructor's `m_simulatedAudioThread` loop, add support for reading Media samples in the mockup thread:
     ```cpp
                 // Around line 330
                 if (m_uiInputPatches[ch].type == 1) { // HW
                     // existing HW code...
                 } else if (m_uiInputPatches[ch].type == 4) { // Media (AudioSourceType::Media = 4)
                     m_mediaDeck->readPlaybackSamples(m_uiInputPatches[ch].index, &inputBuffers[ch * 256], 256);
                 } else {
                     // Generator / None fallback...
                 }
     ```
  4. Update `setInputPatch` signature or bounds checking in C++ if needed. Ensure command target type matches.

- [ ] **Step 3: Compile project**
  Run: `cmake --build build --config Release`
  Expected: Successful compilation without errors.

- [ ] **Step 4: Commit integration changes**
  ```bash
  git add src/core/audio/AudioEngineCore.h src/ui/AudioEngineBridge.h src/ui/AudioEngineBridge.cpp
  git commit -m "feat(audio-core): connect Media Deck audio streaming to mixer DSP loop"
  ```

---

### Task 4: Integrate with Video Switcher Canvas

**Files:**
- Modify: [VideoCanvasMock.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/VideoCanvasMock.h)
- Modify: [VideoCanvasMock.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/VideoCanvasMock.cpp)

- [ ] **Step 1: Access Media Deck in VideoCanvasMock**
  Modify `VideoCanvasMock.h`:
  1. Add `m_mediaDeck` property pointer or lookup. Since we want to query `m_mediaDeck` directly, we can search for the `AudioEngineBridge` instance or pass it.
  2. Let's declare a property or find the bridge:
     We can access the bridge singleton or use a QML property. The easiest and cleanest way is to declare `LocalMediaDeck* m_mediaDeck = nullptr;` inside `VideoCanvasMock` and set it from QML!
     Add property:
     ```cpp
     Q_PROPERTY(LocalMediaDeck* mediaDeck READ mediaDeck WRITE setMediaDeck NOTIFY mediaDeckChanged)
     ```
     Add getter/setter:
     ```cpp
     LocalMediaDeck* mediaDeck() const { return m_mediaDeck; }
     void setMediaDeck(LocalMediaDeck* deck) {
         if (m_mediaDeck != deck) {
             m_mediaDeck = deck;
             emit mediaDeckChanged();
             update();
         }
     }
     ```
     Add signal:
     ```cpp
     void mediaDeckChanged();
     ```
     Add private member:
     ```cpp
     LocalMediaDeck* m_mediaDeck = nullptr;
     ```

- [ ] **Step 2: Update VideoCanvasMock.cpp paint function**
  Modify `VideoCanvasMock.cpp`:
  1. In the `paint()` function, expand rendering to support fifth source (Media Deck) if selected in program/preview:
     ```cpp
     // Adjust rects array to only represent 2x2 grid for CAM 1-4.
     // But wait, the switcher allows selecting a camera (programCamera and previewCamera) from 0 to 4.
     // In paint(), when rendering the 4 quadrants:
     // If a quadrant is selected for Program/Preview, we draw its camera feed.
     // What if we draw a fifth source?
     // When programCamera/previewCamera is 4 (representing Media), we should paint the Media Deck visual into the Program/Preview status or frame instead of Cam 1-4!
     // Wait, let's look at paint():
     ```
     Let's rewrite the painting of `multiviewCanvas` quadrants:
     If a quadrant index `i` is being drawn, it displays `m_cameraImages[i]`.
     But what if the user select `index = 4` (MEDIA)? The Program/Preview border will be drawn around the screen or we can draw the MEDIA feed on a dedicated segment or in a popup!
     Wait, in the 2x2 grid:
     - Quad 1: Cam 1
     - Quad 2: Cam 2
     - Quad 3: Cam 3
     - Quad 4: Cam 4
     Where does Media get drawn?
     If Media is selected as Program or Preview, we can draw a beautiful "Picture-in-Picture" overlay in the center of the multiview, OR we can replace one of the quadrants, OR we can render the Media Deck's live frame dynamically inside the Program/Preview preview canvas!
     Wait, let's look at `paint()` in `VideoCanvasMock.cpp`:
     ```cpp
     // Draw active borders around Preview (green) and Program (red)
     if (m_previewCamera >= 0 && m_previewCamera < 4) {
         QRectF prevRect = rects[m_previewCamera];
         painter->drawRect(prevRect);
     }
     ```
     If `m_previewCamera == 4` (Media), there is no quadrant for it!
     Let's design a floating picture-in-picture (PiP) block in the center or a dedicated overlay for the Media Deck at the bottom right corner when it is active, OR if `m_programCamera == 4` or `m_previewCamera == 4`, draw a fifth panel representing the "MEDIA DECK OUT" feed!
     Let's do this: draw a beautiful floating monitor at the center-bottom of the multiview (e.g. at `x: halfW - 100, y: h - 120, w: 200, h: 110`) when the Media Deck is selected, displaying "MEDIA OUT" with the live waveform and progress!
     This is extremely professional and makes the multiview look incredibly high-tech!
     Let's write this drawing logic in `VideoCanvasMock.cpp`:
     ```cpp
     // Inside paint() at the end:
     if (m_mediaDeck != nullptr && (m_programCamera == 4 || m_previewCamera == 4)) {
         QRectF mediaRect(halfW - 120, h - 110, 240, 100);
         // Generate frame
         QImage mediaFrame;
         m_mediaDeck->generateVideoFrame(mediaFrame, m_frameCount, 240, 100);
         painter->drawImage(mediaRect, mediaFrame);
         
         // Draw border based on selected PGM/PVW
         if (m_programCamera == 4) {
             painter->setPen(QPen(QColor("#ff3b30"), 3)); // Red PGM
         } else {
             painter->setPen(QPen(QColor("#30d158"), 3)); // Green PVW
         }
         painter->drawRect(mediaRect);
         
         // Label
         painter->setPen(QColor("#ffffff"));
         QFont labelFont = painter->font();
         labelFont.setBold(true);
         labelFont.setPixelSize(10);
         painter->setFont(labelFont);
         painter->drawText(mediaRect.adjusted(8, 8, -8, -8), Qt::AlignTop | Qt::AlignLeft, "MEDIA DECK OUT");
     }
     ```
     This is outstanding! If Media is selected for either Program or Preview, a dedicated PiP monitor pops up at the bottom center of the multiview with the active playback graphics, outlined in red or green based on the PGM/PVW selection!

- [ ] **Step 3: Compile and check**
  Compile the project:
  `cmake --build build --config Release`

- [ ] **Step 4: Commit switcher integration**
  ```bash
  git add src/ui/VideoCanvasMock.h src/ui/VideoCanvasMock.cpp
  git commit -m "feat(ui-video): display floating Media Deck PiP monitor on active switcher routing"
  ```

---

### Task 5: Add Unit Tests for LocalMediaDeck

**Files:**
- Modify: [DynamicAudioEngineTests.cpp](file:///f:/Drive/scripts/overwatch_studio/tests/DynamicAudioEngineTests.cpp)

- [ ] **Step 1: Write GTest test blocks**
  Add unit tests to check Media Deck playback controls, seek functionality, and audio patch integration:
  ```cpp
  #include "ui/LocalMediaDeck.h"
  
  TEST(LocalMediaDeckTest, PlaybackControlsAndState) {
      LocalMediaDeck deck;
      EXPECT_FALSE(deck.isPlaying());
      EXPECT_EQ(deck.position(), 0);
      
      deck.play();
      EXPECT_TRUE(deck.isPlaying());
      
      deck.setPosition(50);
      EXPECT_EQ(deck.position(), 50);
      EXPECT_NEAR(deck.playbackProgress(), 50.0 / 120.0, 1e-5);
      
      deck.pause();
      EXPECT_FALSE(deck.isPlaying());
      EXPECT_EQ(deck.position(), 50);
      
      deck.stop();
      EXPECT_FALSE(deck.isPlaying());
      EXPECT_EQ(deck.position(), 0);
      
      deck.load("test_track.wav");
      EXPECT_EQ(deck.filePath().toStdString(), "test_track.wav");
      EXPECT_GT(deck.duration(), 0);
  }
  
  TEST_F(DynamicAudioEngineTest, VerifyMediaPatchAudioStreaming) {
      auto core = std::make_unique<AudioEngineCore>();
      LocalMediaDeck deck;
      core->setMediaDeck(&deck);
      
      // Patch channel 0 to Media Deck
      core->setInputPatch(0, AudioSourceType::Media, 0); // 0 = Left channel
      
      // Set fader gain to 0dB (1.0f)
      core->getFaderStrips()[0]->setFaderVolume(1.0f);
      
      std::vector<float> outputL(256, 0.0f);
      std::vector<float> outputR(256, 0.0f);
      const float* inputs[2] = { outputL.data(), outputR.data() };
      float* outputs[2] = { outputL.data(), outputR.data() };
      
      // Initially paused, output should be silent
      core->audioDeviceIOCallbackWithContext(inputs, 2, outputs, 2, 256, nullptr);
      for (float val : outputL) {
          EXPECT_NEAR(val, 0.0f, 1e-5f);
      }
      
      // Start play, output should contain synth pad signal
      deck.play();
      core->audioDeviceIOCallbackWithContext(inputs, 2, outputs, 2, 256, nullptr);
      
      bool hasSignal = false;
      for (float val : outputL) {
          if (std::abs(val) > 0.01f) {
              hasSignal = true;
              break;
          }
      }
      EXPECT_TRUE(hasSignal);
  }
  ```

- [ ] **Step 2: Run all tests**
  Build and run unit tests:
  `cmake --build build --config Release`
  `build/bin/Release/AudioEngineTests.exe`
  Expected: All 29 tests pass cleanly.

- [ ] **Step 3: Commit tests**
  ```bash
  git add tests/DynamicAudioEngineTests.cpp
  git commit -m "test(video-audio): add unit tests for LocalMediaDeck and DSP patching integration"
  ```

---

### Task 6: Refactor Main.qml Switcher & Build Playback Controls

**Files:**
- Modify: [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml)

- [ ] **Step 1: Connect Media Deck property in QML and bind VideoCanvasMock**
  1. Add `mediaDeck: audioCore.mediaDeck` inside the `VideoCanvasMock` block at line 4310 in `Main.qml`.

- [ ] **Step 2: Update PGM and PVW Buses to support 5 sources**
  Modify PGM Bus (line 4488) and PVW Bus (line 4580) `Repeater` configurations:
  1. Change `model: 4` to `model: 5` in both PGM and PVW Repeaters.
  2. Change the button delegate's text to:
     ```qml
     text: index === 4 ? "MEDIA" : "CAM " + (index + 1)
     ```
  3. Update Program active status text (line 4414):
     ```qml
     text: "PROGRAM [PGM]: " + (programCameraIdx === 4 ? "MEDIA" : "CAM " + (programCameraIdx + 1))
     ```
  4. Update Preview active status text (line 4444):
     ```qml
     text: "PREVIEW [PVW]: " + (previewCameraIdx === 4 ? "MEDIA" : "CAM " + (previewCameraIdx + 1))
     ```

- [ ] **Step 3: Expand main window layout to ColumnLayout and add Media Deck Panel**
  Refactor the top-level layout of `videoWin` (line 4254):
  1. Change `RowLayout` to `ColumnLayout`.
  2. Nest the original `RowLayout` (Multiview canvas + Switcher Panel) inside a `RowLayout` with `Layout.fillWidth: true` and `Layout.fillHeight: true`.
  3. Add the new **MEDIA DECK PANEL** at the bottom of the column:
     ```qml
     // --- LOCAL MEDIA DECK CONTROL PANEL ---
     Rectangle {
         id: mediaDeckPanel
         Layout.fillWidth: true
         height: 90
         color: "#161920"
         border.color: "#252b36"
         border.width: 1
         radius: 8
         
         RowLayout {
             anchors.fill: parent
             anchors.margins: 12
             spacing: 15
             
             // Playback Status Indicator
             ColumnLayout {
                 spacing: 2
                 Text {
                     text: "LOCAL MEDIA DECK"
                     color: "#00bdd6"
                     font.pixelSize: 10
                     font.bold: true
                     font.letterSpacing: 1.0
                 }
                 Text {
                     text: audioCore.mediaDeck.playing ? "STATE: PLAYING" : "STATE: PAUSED"
                     color: audioCore.mediaDeck.playing ? "#30d158" : "#8a8d98"
                     font.pixelSize: 9
                     font.bold: true
                 }
             }
             
             // Load / File selection
             ColumnLayout {
                 Layout.preferredWidth: 200
                 spacing: 4
                 Text {
                     text: audioCore.mediaDeck.filePath === "" ? "No file loaded" : audioCore.mediaDeck.filePath
                     color: "#ffffff"
                     font.pixelSize: 10
                     elide: Text.ElideMiddle
                 }
                 RowLayout {
                     spacing: 6
                     Button {
                         implicitHeight: 24
                         text: "Load Clip"
                         onClicked: {
                             // Load a mock media file
                             audioCore.mediaDeck.load("clip_show_intro_1080p.mp4");
                         }
                     }
                     Button {
                         implicitHeight: 24
                         text: "Load Audio"
                         onClicked: {
                             audioCore.mediaDeck.load("bg_music_track.wav");
                         }
                     }
                 }
             }
             
             // Playback Controls
             RowLayout {
                 spacing: 8
                 Button {
                     text: "▶"
                     implicitWidth: 32
                     implicitHeight: 32
                     onClicked: audioCore.mediaDeck.play()
                 }
                 Button {
                     text: "▮▮"
                     implicitWidth: 32
                     implicitHeight: 32
                     onClicked: audioCore.mediaDeck.pause()
                 }
                 Button {
                     text: "■"
                     implicitWidth: 32
                     implicitHeight: 32
                     onClicked: audioCore.mediaDeck.stop()
                 }
             }
             
             // Progress Slider & Timecode
             ColumnLayout {
                 Layout.fillWidth: true
                 spacing: 2
                 RowLayout {
                     Text {
                         // Format Timecode
                         function formatTC(secs) {
                             var m = Math.floor(secs / 60);
                             var s = secs % 60;
                             return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
                         }
                         text: formatTC(audioCore.mediaDeck.position) + " / " + formatTC(audioCore.mediaDeck.duration)
                         color: "#a1a1aa"
                         font.pixelSize: 9
                         font.bold: true
                     }
                     Item { Layout.fillWidth: true }
                     CheckBox {
                         text: "Loop"
                         checked: audioCore.mediaDeck.loop
                         onCheckedChanged: audioCore.mediaDeck.loop = checked
                     }
                 }
                 Slider {
                     Layout.fillWidth: true
                     from: 0
                     to: audioCore.mediaDeck.duration
                     value: audioCore.mediaDeck.position
                     onMoved: audioCore.mediaDeck.position = value
                 }
             }
         }
     }
     ```

- [ ] **Step 4: Rebuild project and test QML**
  Compile:
  `cmake --build build --config Release`
  Run the application to verify:
  1. Open Video Switcher. Verify PGM/PVW buses have the "MEDIA" button.
  2. Select "MEDIA" as PVW/PGM. Verify the picture-in-picture "MEDIA DECK OUT" floating monitor appears on the multiview with active waves.
  3. Load "clip_show_intro_1080p.mp4", press Play, and verify the progress bar seeks and loops correctly.
  4. In the Audio settings, patch an input channel to "Media" (source type index 4), and verify audio streams correctly.

- [ ] **Step 5: Commit QML and finalize**
  ```bash
  git add src/ui/Main.qml
  git commit -m "feat(ui-qml): design media deck playback panel and integrate PGM/PVW routing"
  ```
