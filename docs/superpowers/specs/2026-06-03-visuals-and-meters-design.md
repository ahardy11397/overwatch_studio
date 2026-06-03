# 2026-06-03 Visuals and Meters Design

This specification details the implementation plan to make the Software-Defined Sound Console (SDSC) audio meters bounce dynamically, replace the plain charcoal video switcher placeholders with high-fidelity generated visual feeds, and implement real multi-device WASAPI audio capture/playback and application loopback.

## Problem Statement
1. **Static Audio Meters:** The peak meters currently do not bounce or animate dynamically. Simulated hardware inputs are static `0.1f` DC offsets, causing the level meters to remain frozen.
2. **Video Switcher Placeholders:** The video switcher displays flat charcoal boxes with text placeholders like "CAMERA 1" instead of realistic camera feeds.
3. **No Real Audio Device I/O:** The application lacks capture from physical audio input devices (microphones/line-ins), playback to physical audio output devices (speakers/headphones), and real application loopback audio capture.

## Proposed Changes

### 1. Dynamic Audio Meters
* **Unconditional Emission:** Modify `AudioEngineBridge::processAudioFeedback()` to unconditionally emit `peakMeterChanged()` on every tick (~60fps) to keep QML bindings active.
* **Dynamic Simulation Fallback:** If no physical audio devices are present, fill the simulated hardware inputs with dynamic sine waves modulated by a slow LFO and mixed with noise, so the meters bounce naturally.

### 2. Live Video Switcher Visuals
* **Visual Asset Generation:** Use the `generate_image` tool to create four high-quality 16:9 images in `src/ui/assets/` representing a tech conference (`cam1.png` to `cam4.png`).
* **Asset Loading & Painting:** Modify `VideoCanvasMock` to load these 4 images on startup and paint them in their respective quadrants, falling back to a beautiful dark tech gradient if they fail to load.

### 3. Real Multi-Device WASAPI Capture and Playback
We will implement real multi-device I/O using native Windows WASAPI:
* **WASAPIDeviceWorker Class:**
  - Create a lightweight thread-safe worker class to handle a single WASAPI audio device.
  - Can be initialized in **Capture** mode (using `IAudioCaptureClient`) or **Render** mode (using `IAudioRenderClient`).
  - Automatically handles format conversion (converting float to/from 16-bit PCM or 24-bit PCM depending on the device's native format).
* **Multi-Device Input Capture:**
  - Enumerate all active capture endpoints (`eCapture`) using `IMMDeviceEnumerator`.
  - Open a `WASAPIDeviceWorker` in Capture mode for each active capture device (up to 8 devices).
  - Map each capture device to a pair of Hardware Input Ports (Device 0 to Ports 0-1, Device 1 to Ports 2-3, etc.).
  - Copy captured samples into the corresponding channels of `inputChannelData` during the callback loop.
* **Multi-Device Output Playback:**
  - Enumerate all active render endpoints (`eRender`) using `IMMDeviceEnumerator`.
  - Open a `WASAPIDeviceWorker` in Render mode for each active render device (up to 4 devices).
  - Map pairs of Hardware Output Ports (Ports 0-1 to Device 0, Ports 2-3 to Device 1, etc.).
  - Play out the summing buses' mixed buffers to the corresponding physical output devices.

### 4. Real Application Loopback Capture
* **Process Loopback Client:**
  - Implement real application loopback capture in `WindowsProcessCapture` using `ActivateAudioInterfaceAsync` and `AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS` targeting the process PID.
  - Fall back to system-wide loopback capture (`AUDCLNT_STREAMFLAGS_LOOPBACK` on the default render device) if process-specific activation fails or is unsupported.
  - Push captured samples to the designated SPSC queue of the channel strip.

## Verification Plan

### Automated Tests
* Run `cmake --build build --config Release`
* Run `.\build\bin\Release\AudioEngineTests.exe` to ensure no regressions in routing and DSP logic.

### Manual Verification
* Run `.\build\bin\Release\overwatch_studio.exe`
* Speak into your microphone and verify the mapped hardware input meters respond to your voice.
* Play audio in a target process (e.g. Chrome or Spotify) and patch it to an input channel; verify the meter responds to the music.
* Route audio to headphones and speakers and verify both play their respective mixes simultaneously.
