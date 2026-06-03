# 2026-06-03 Visuals and Meters Design

This specification details the implementation plan to make the Software-Defined Sound Console (SDSC) audio meters bounce dynamically and replace the plain charcoal video switcher placeholders with high-fidelity, generated visual feeds.

## Problem Statement
1. **Static Audio Meters:** The peak meters currently do not bounce or animate dynamically. If the input is constant, the Qt notify signal is throttled, preventing QML from updating. Furthermore, simulated hardware inputs are static `0.1f` DC offsets, causing the level meters to remain frozen at a static position.
2. **Video Switcher Placeholders:** The video switcher displays flat charcoal boxes with text placeholders like "CAMERA 1" instead of realistic camera feeds, which makes the app look like an unfinished mockup.

## Proposed Changes

### 1. Dynamic Audio Meters
* **Unconditional Emission:** Modify `AudioEngineBridge::processAudioFeedback()` to unconditionally emit `peakMeterChanged()` on every tick (~60fps).
* **Dynamic Simulated Hardware Inputs:** Modify the simulated audio thread callback loop in `AudioEngineBridge.cpp` to fill the hardware inputs with dynamic signals instead of static `0.1f`. We will generate:
  - Dynamic sine waves of varying frequencies (e.g., 200Hz to 1200Hz) and amplitudes for channels 0 to 7.
  - Pink/white noise for channels 8 to 11.
  - A slow LFO-modulated music-like signal for channels 12 to 15.
  This ensures that when the app starts, all active fader meters will animate dynamically and naturally.

### 2. Live Video Switcher Visuals
* **Visual Asset Generation:** Use the `generate_image` tool to create four high-quality 16:9 images in `src/ui/assets/` representing a tech conference:
  - `cam1.png`: Main stage keynotes (wide shot of speaker, podium, large projector screen).
  - `cam2.png`: Panel discussions (medium shot of three experts sitting on chairs with lapel mics).
  - `cam3.png`: Audience Q&A (shot looking at the crowd with a person speaking at a stand-up microphone).
  - `cam4.png`: Speaker backstage (close-up/medium shot of a speaker preparing, wearing a headset, with confidence monitor).
* **Asset Loading & Painting:**
  - Modify `VideoCanvasMock` to load these 4 images on startup from the file system.
  - Search multiple paths (relative to workspace root, application directory, and source folder) to ensure they load in both debug/release builds.
  - Draw these images in their respective quadrants using `QPainter::drawImage()`.
  - Draw a high-tech overlay (gradient, clean borders, red/green tally colors, and genlock scanner line) over the images.
  - Fall back to a beautiful dark tech gradient if the assets fail to load.

## Verification Plan

### Automated Tests
* Run `cmake --build build --config Release`
* Run `.\build\bin\Release\AudioEngineTests.exe` to ensure no regressions in routing and DSP logic.

### Manual Verification
* Run the built app: `.\build\bin\Release\overwatch_studio.exe`
* Verify that the 24 channels and master peak meters bounce dynamically.
* Verify that lowering faders decays the corresponding meters.
* Verify that the switcher grid displays 4 detailed tech conference images instead of plain charcoal boxes.
