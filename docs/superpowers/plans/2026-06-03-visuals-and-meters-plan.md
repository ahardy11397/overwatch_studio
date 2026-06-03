# Visuals and Meters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Animate the fader peak meters continuously at 60fps with dynamic simulated signals and replace the plain charcoal video switcher rectangles with high-quality generated tech-conference camera visuals.

**Architecture:** We will generate 4 tech-conference images, save them in the UI assets folder, and modify `VideoCanvasMock` to load and render them. We will modify `AudioEngineBridge` to emit the peak notify signal unconditionally and replace the static simulated inputs with dynamic waves.

**Tech Stack:** C++ / Qt 6 QML / QQuickPaintedItem / QPainter

---

### Task 1: Generate Tech Conference Visual Assets

**Files:**
- Create: `src/ui/assets/cam1.png`
- Create: `src/ui/assets/cam2.png`
- Create: `src/ui/assets/cam3.png`
- Create: `src/ui/assets/cam4.png`

- [ ] **Step 1: Generate Cam 1 Image (Main Stage Keynote)**
  Generate a 16:9 image representing a modern tech conference wide shot of a speaker at a sleek podium, a large bright projector screen showing charts, and clean lighting.
  Save to: `f:/Drive/scripts/overwatch_studio/src/ui/assets/cam1.png`
  Tool call: `generate_image` with prompt: "Wide shot of a modern tech conference main stage, a keynote speaker at a sleek podium, a large presentation screen displaying clean data charts, high-end professional stage lighting, cinematic, 16:9 aspect ratio, high resolution"

- [ ] **Step 2: Generate Cam 2 Image (Panel Discussion)**
  Generate a 16:9 image representing a medium shot of a panel discussion with three experts sitting on modern chairs on a stage talking to the audience, with professional lighting.
  Save to: `f:/Drive/scripts/overwatch_studio/src/ui/assets/cam2.png`
  Tool call: `generate_image` with prompt: "Medium shot of a tech conference panel discussion, three diverse industry experts sitting on modern chairs on a low-lit stage, talking with lapel microphones, professional clean aesthetic, 16:9 aspect ratio, high resolution"

- [ ] **Step 3: Generate Cam 3 Image (Audience Q&A)**
  Generate a 16:9 image looking from behind the audience towards a standing microphone in the center aisle where an attendee is asking a question, facing the brightly lit stage.
  Save to: `f:/Drive/scripts/overwatch_studio/src/ui/assets/cam3.png`
  Tool call: `generate_image` with prompt: "High resolution 16:9 photo from behind the audience in a large auditorium, looking at a standing Q&A microphone in the aisle with a person speaking, facing a brightly lit stage in the background, professional conference photography style"

- [ ] **Step 4: Generate Cam 4 Image (Speaker Backstage)**
  Generate a 16:9 image of a speaker backstage prepping, adjusting a headset microphone, with flight cases, TV screens, and technical equipment in the soft-focus background.
  Save to: `f:/Drive/scripts/overwatch_studio/src/ui/assets/cam4.png`
  Tool call: `generate_image` with prompt: "Medium shot of a speaker backstage at a large venue preparing to go on stage, adjusting a headset microphone, technical production crew and flight cases in a dimly-lit background, high-end broadcast production setup, 16:9 aspect ratio, high resolution"

- [ ] **Step 5: Verify images are saved**
  Verify the files exist in `f:/Drive/scripts/overwatch_studio/src/ui/assets/` using a filesystem command.

- [ ] **Step 6: Commit**
  ```bash
  git add src/ui/assets/*.png
  git commit -m "asset(switcher): add generated tech conference video feed images"
  ```

---

### Task 2: Paint Live Camera Feeds in VideoCanvasMock

**Files:**
- Modify: `src/ui/VideoCanvasMock.h`
- Modify: `src/ui/VideoCanvasMock.cpp`

- [ ] **Step 1: Declare QImage assets in VideoCanvasMock.h**
  Modify `src/ui/VideoCanvasMock.h` to declare an array of 4 `QImage` objects:
  ```cpp
  // Inside private: of class VideoCanvasMock
  std::array<QImage, 4> m_cameraImages;
  ```

- [ ] **Step 2: Load assets in constructor of VideoCanvasMock.cpp**
  Modify `src/ui/VideoCanvasMock.cpp` constructor to load the 4 images. Include path fallbacks so it works in both dev directory and built binary folders.
  ```cpp
  #include <QCoreApplication>
  #include <QDir>
  #include <QDebug>

  VideoCanvasMock::VideoCanvasMock(QQuickItem* parent) : QQuickPaintedItem(parent) {
      m_timer = new QTimer(this);
      connect(m_timer, &QTimer::timeout, this, &VideoCanvasMock::updateFrame);
      m_timer->start(16); // 60fps mock genlock rendering

      // Define potential base directories for assets
      QString appDir = QCoreApplication::applicationDirPath();
      QStringList searchPaths = {
          appDir + "/assets/",
          appDir + "/../src/ui/assets/",
          appDir + "/../../src/ui/assets/",
          "./src/ui/assets/",
          "../src/ui/assets/"
      };

      for (int i = 0; i < 4; ++i) {
          QString filename = QString("cam%1.png").arg(i + 1);
          bool loaded = false;
          for (const QString& path : searchPaths) {
              QString fullPath = QDir::cleanPath(path + filename);
              if (m_cameraImages[i].load(fullPath)) {
                  qDebug() << "Successfully loaded switcher video feed:" << fullPath;
                  loaded = true;
                  break;
              }
          }
          if (!loaded) {
              qWarning() << "Failed to load switcher video feed:" << filename << "in search paths. Fallback gradient will be used.";
          }
      }
  }
  ```

- [ ] **Step 3: Update paint function in VideoCanvasMock.cpp**
  Modify the `paint` function to draw each camera's image or draw a fallback high-tech gradient if loading failed:
  ```cpp
  #include <QLinearGradient>

  void VideoCanvasMock::paint(QPainter* painter) {
      if (PanicSwitch::getInstance().isFadeToBlackActive()) {
          painter->fillRect(boundingRect(), QBrush(QColor("#000000")));
          
          painter->setPen(QColor("#ff3b30"));
          QFont font = painter->font();
          font.setBold(true);
          font.setPixelSize(16);
          painter->setFont(font);
          painter->drawText(boundingRect(), Qt::AlignCenter, "FADE TO BLACK ACTIVE\n[PANIC BLACKOUT ENGAGED]");
          return;
      }

      qreal w = boundingRect().width();
      qreal h = boundingRect().height();
      qreal halfW = w / 2.0;
      qreal halfH = h / 2.0;

      std::array<QRectF, 4> rects = {
          QRectF(0, 0, halfW, halfH),
          QRectF(halfW, 0, halfW, halfH),
          QRectF(0, halfH, halfW, halfH),
          QRectF(halfW, halfH, halfW, halfH)
      };

      // Draw background and camera content for all quadrants
      for (int i = 0; i < 4; ++i) {
          QRectF r = rects[i];
          if (!m_cameraImages[i].isNull()) {
              // Draw the beautiful camera visual
              painter->drawImage(r, m_cameraImages[i]);
          } else {
              // High-tech fallback gradient
              QLinearGradient grad(r.topLeft(), r.bottomRight());
              grad.setColorAt(0.0, QColor("#141923"));
              grad.setColorAt(1.0, QColor("#090b0f"));
              painter->fillRect(r, QBrush(grad));
          }

          // Subtle transparent overlay for technical feel
          painter->fillRect(r, QColor(0, 0, 0, 40));

          // Camera Label
          painter->setPen(QColor("#ffffff"));
          QFont labelFont = painter->font();
          labelFont.setBold(true);
          labelFont.setPixelSize(12);
          painter->setFont(labelFont);
          QString label = QString("CAMERA %1").arg(i + 1);
          painter->drawText(r.adjusted(12, 12, -12, -12), Qt::AlignTop | Qt::AlignLeft, label);

          // Technical specs overlay
          QFont infoFont = painter->font();
          infoFont.setBold(false);
          infoFont.setPixelSize(8);
          painter->setFont(infoFont);
          painter->setPen(QColor("#a0aab8"));
          painter->drawText(r.adjusted(12, 12, -12, -12), Qt::AlignBottom | Qt::AlignRight, "1080p60 | GPU-SYNC");
      }

      // 1. Draw Program scanning line inside Program camera's quadrant
      if (m_programCamera >= 0 && m_programCamera < 4) {
          QRectF progRect = rects[m_programCamera];
          int scanYOffset = (m_frameCount * 3) % static_cast<int>(progRect.height());
          qreal lineY = progRect.top() + scanYOffset;
          painter->setPen(QPen(QColor("#ff3b30"), 2)); // Red scanner line
          painter->drawLine(progRect.left(), lineY, progRect.right(), lineY);
      }

      // 2. Draw active borders around Preview (green) and Program (red)
      if (m_previewCamera >= 0 && m_previewCamera < 4) {
          QRectF prevRect = rects[m_previewCamera];
          painter->setPen(QPen(QColor("#30d158"), 4)); // Bright green PVW border
          painter->drawRect(prevRect.adjusted(2, 2, -2, -2));
      }
      if (m_programCamera >= 0 && m_programCamera < 4) {
          QRectF progRect = rects[m_programCamera];
          painter->setPen(QPen(QColor("#ff3b30"), 4)); // Bright red PGM border
          painter->drawRect(progRect.adjusted(2, 2, -2, -2));
      }

      // 3. Draw grid divider lines to separate quadrants beautifully
      painter->setPen(QPen(QColor("#252b36"), 2));
      painter->drawLine(halfW, 0, halfW, h);
      painter->drawLine(0, halfH, w, halfH);
  }
  ```

- [ ] **Step 4: Build project to check compilation**
  Run: `cmake --build build --config Release`
  Expected: Success.

- [ ] **Step 5: Commit**
  ```bash
  git add src/ui/VideoCanvasMock.h src/ui/VideoCanvasMock.cpp
  git commit -m "feat(switcher): load and render high-fidelity camera feeds in VideoCanvasMock"
  ```

---

### Task 3: Unconditional Peak Meter Signal and Dynamic Simulated Signal

**Files:**
- Modify: `src/ui/AudioEngineBridge.cpp`

- [ ] **Step 1: Enable unconditional peakMeterChanged signal emission**
  Modify `AudioEngineBridge::processAudioFeedback()` to unconditionally update backing arrays and emit `peakMeterChanged()`.
  ```cpp
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

      // Always emit to ensure QML binds refresh continuously for natural decay physics
      emit peakMeterChanged();
  }
  ```

- [ ] **Step 2: Make simulated hardware inputs dynamic**
  Modify the simulated audio thread inside `AudioEngineBridge::AudioEngineBridge` constructor to generate dynamic waves for the 24 channels instead of constant static `0.1f` buffers.
  We will fill `inputBuffer` dynamically each frame inside the thread loop using a running sample counter:
  ```cpp
      m_running = true;
      m_simulatedAudioThread = std::jthread([this](std::stop_token stopToken) {
          std::vector<float> inputBuffer(256, 0.0f);
          std::vector<const float*> inputPtrs(24, inputBuffer.data());
          std::vector<float> outputBuffer(256, 0.0f);
          std::vector<float*> outputPtrs(8, outputBuffer.data());
          
          uint32_t sampleCounter = 0;
          
          while (!stopToken.stop_requested() && m_running.load()) {
              SystemWatchdog::getInstance().registerAudioCallback();
              
              // Fill inputBuffer with simulated multi-channel audio activity:
              // Generate a dynamic mix of sine waves and noise that oscillates over time.
              for (size_t s = 0; s < 256; ++s) {
                  float t = static_cast<float>(sampleCounter + s) / 48000.0f;
                  
                  // Primary wave: slow LFO modulation to simulate a musical flow
                  float lfo = 0.5f + 0.5f * std::sin(2.0f * 3.14159f * 0.2f * t); // 0.2 Hz slow sweep
                  
                  // Generate dynamic signal
                  float sig = std::sin(2.0f * 3.14159f * 440.0f * t) * lfo;
                  
                  // Add subtle white-noise simulation
                  float whiteNoise = (((rand() % 2000) / 1000.0f) - 1.0f) * 0.05f;
                  
                  inputBuffer[s] = (sig * 0.25f) + whiteNoise;
              }
              
              sampleCounter += 256;
              if (sampleCounter >= 48000 * 60) {
                  sampleCounter = 0; // Wrap around every 60 seconds
              }

              if (m_engine) {
                  m_engine->audioDeviceIOCallbackWithContext(
                      inputPtrs.data(), 24,
                      outputPtrs.data(), 8,
                      256, nullptr
                  );
              }
              std::this_thread::sleep_for(std::chrono::milliseconds(5));
          }
      });
  ```

- [ ] **Step 3: Build project and run tests**
  Run: `cmake --build build --config Release`
  Run: `.\build\bin\Release\AudioEngineTests.exe`
  Expected: Build succeeds, all 22 tests pass.

- [ ] **Step 4: Commit**
  ```bash
  git add src/ui/AudioEngineBridge.cpp
  git commit -m "fix(audio): enable unconditional peak meter updates and dynamic hardware input simulation"
  ```
