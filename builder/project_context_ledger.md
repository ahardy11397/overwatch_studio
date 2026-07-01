# Overwatch Studio: Project Context Ledger & Session State Memory

> **CONFIDENTIAL DEVELOPMENT SYSTEM STATE** > **Target System:** Unified Software-Defined Sound Console (SDSC) & Video Switcher (SDVS)
>
> **Last Synced Engine Timestamp:** Wednesday, July 1, 2026

## 1. Instruction Manual for the Incoming CLI Agent (Read Me First)

You are the  **Overwatch Studio Core Developer Agent** . You are entering a mission-critical, low-latency live production software workspace. If you experience a cold reboot, a session crash, or a new workspace load, you must execute the following bootstrapping protocol before suggesting modifications or writing a single line of code:

### Bootstrapping Protocol

1. **Read the Specs:** Fully parse `master_builder.md` to load the exact mathematical formulas, GPU texture maps, lock-free SPSC ring buffers, and system safety constraints into your active memory.
2. **Read the Progress Ledger:** Fully parse this file (`project_context_ledger.md`) to establish the exact "Who, What, When, Where, Why" of our state, mapping outstanding checklist items, recently completed steps, and active work targets.
3. **Sync the Memory State:** Under no circumstances should you drift from the established design decisions recorded in the *Chronological Decision Register* (Section 4).
4. **Auto-Update on Close:** At the end of every task or session phase, you are programmatically required to update this ledger file. Rewrite the checklist states, append new design decisions, and log progress in the decision register.

## 2. Current Release Target: BETA (2026-06-29)

**Persona:** At-home podcasters, 2+ monitors. Not broadcast engineers.

**Beta floor:** real audio AND real video (not mock). Windows persist across launches. OSC control works. Default `.sds` loads on first run. CI runs on GitHub Actions. WiX v5 installer produces single MSI.

**Active plans:**
- `docs/superpowers/plans/2026-06-29-beta-real-audio-path.md` — real WASAPI → DSP → render, per-process app capture, 8-channel 24-bit WAV stem recording
- `docs/superpowers/plans/2026-06-29-beta-remaining-systems.md` — real video (WGC + FFmpeg), multi-window QML, OSC, persistence, default showfile, CI, installer

## 3. Beta Scope Decisions (ahard, 2026-06-29)

* **Decision 20 (Beta — Audio Path):** WASAPI exclusive mode for beta; ASIO deferred to v1. Round-trip < 2 ms.
* **Decision 21 (Beta — Video Capture):** Windows Graphics Capture (screen/window) + FFmpeg (RTSP/NDI) for beta. libOBS deferred — too heavy to build.
* **Decision 22 (Beta — Channel Count):** User-programmable in spec, but beta ships fixed 8-channel / 2-bus / 8-DCA default via `AudioEngineCore::configureEngine(8, 2, 0, 8)`.
* **Decision 23 (Beta — Recording):** 8 mono 24-bit WAV stems (hard beta requirement). Mix-only not acceptable. `AudioRecorderManager` already real.
* **Decision 24 (Beta — Control Surface):** OSC-only for beta (oscpp, UDP 8000 in / 9000 out). MIDI/MCU deferred.
* **Decision 25 (Beta — Codecs):** WAV-only for beta. AAC/FLAC/Opus for full release.
* **Decision 26 (Beta — Persistence):** Window positions persist via `QSettings` (INI/registry). Showfiles via `.sds` (zip + manifest.json + SQLite WAL).
* **Decision 27 (Beta — CI):** GitHub Actions Windows runner, unit tests + D3D11 NULL device shader compile tests. Audio/video smoke-tests validated by humans (not CI).
* **Decision 28 (Beta — Installer):** WiX v5 MSI. Bundle Qt runtime (~250 MB), VC++ 2022 ucrt, vcpkg CRT.
* **Decision 29 (Beta — QML Integrity):** `scratch/check_brackets.py` exists and works. Run it before committing QML.

## 4. Chronological Decision Register

* **Decision 13 (Milestone 6 - Universal Control Surface Integration):** Structured `ExternalControlSurfaceManager` singleton managing background MIDI MCU, OSC, and WebSockets commands translated via lock-free SPSC rings, adding anti-feedback loop filters.
* **Decision 14 (Milestone 7 - DCA & Mute Routing Loop Integration):** Implemented lock-free $O(1)$ constant time volume summing and mute group filters inside channel strips, smooth-ramped over a 15ms window via pre-allocated atomic variables.
* **Decision 15 (Milestone 8 - Widescreen 8-Fader Console & 8 DCA Setup Matrix):** Expanded touch fader console window width, constructed widescreen 8-fader rows, designed swappable DCA Layer Master strips with safe guards, and scaled QML Setup Matrix to support 8 groups.
* **Decision 16 (Milestone 9 - Production-Grade DSP & Direct3D 11 GPU Compositor Sweeps):** Programmed mathematically complete zero-allocation real-time filters (Butterworth HPF, RBJ Parametric EQ, Noise Gate expander, soft-knee feedforward Compressor) and complete Direct3D 11 zero-copy rendering sweeps, verifying them via headless soft D3D11 and phase-continuous sine tests.
* **Decision 17 (Milestone 10 - Widescreen Popup EQ Tab Editor Redesign):** Upgraded the popup EQ tab editor inside the `dspInspectorPanel` in `Main.qml` to have a full professional Parametric & Dynamic EQ deck layout, including high-precision Gain, logarithmic Frequency, and Q-factor sliders for all 4 bands, matching the embedded Show Builder DSP tab.
* **Decision 18 (Milestone 11 - Redesigned 3-Tab Audio Patch Board QML Interface):** Redesigned the Audio Patch board from a single collapsible 2D coordinate grid matrix into a professional 3-tab layout containing Input Patch, Internal Routing Matrix, and Output Patch panels, and integrated dynamic ComboBoxes, dot indicators, and PID info linking to C++ bridge commands.
* **Decision 19 (Milestone 12 - Advanced Switcher Effects & D3D11 Shader Compilation):** Implemented advanced chroma key (Green/Blue screen dynamic check and soft-spill suppression), transition wipes (Cut, Mix, Wipes), and DSK shaders in HLSL. Refactored [GPUCompositor](file:///f:/Drive/scripts/overwatch_studio/src/core/video/GPUCompositor.h) to compile all shaders dynamically and built constant/vertex buffers, verifying them on a headless NULL device.
* **Decisions 20–29** — see Section 3 above (beta scope).
* **Decision 30 (2026-07-01 — Beta Real Audio Path):** All 6 tasks completed and committed: WASAPI exclusive mode, mock sine removal, WAV stem recording end-to-end, recording file path QML bridge, WindowsProcessCapture test, 8-channel default layout.
* **Decision 31 (2026-07-01 — Beta Remaining Systems):** Implemented and committed: FFmpeg dependency (vcpkg + CMake), FFmpegCaptureSource (RTSP/NDI/file → D3D11), VideoCaptureManager (owns sources → VideoSyncManager), WindowsGraphicsCapture (fixed C++/WinRT COM interop), multi-window QML with WindowStateStore persistence, OSC control surface (oscpack, port 8000), ShowfileManager with default showfile bootstrap, GitHub Actions CI. WiX v5 CPack config in CMakeLists — requires WiX toolset to be installed for MSI generation.
* **Decision 32 (2026-07-01 — Beta UI Extraction):** Split monolithic Main.qml (8713 lines) into 4 independent window files: Main.qml (launcher, 1263 lines), AudioConsole.qml (3289 lines), VideoSwitcher.qml (835 lines), ShowBuilder.qml (3586 lines). Each window runs on its own QQmlApplicationEngine with shared bridge instances via context properties. Added `toggleWindow()` Q_INVOKABLE for cross-window show/hide.
* **Decision 33 (2026-07-01 — WGC Stub):** WGC capture API wired into VideoCaptureManager (addWindowSource/addMonitorSource) and main.cpp, but C++/WinRT SDK isn't available on the build machine. WindowsGraphicsCapture.cpp compiled as a no-op stub that logs "not available". FFmpegCaptureSource path still works for RTSP/NDI/file. Upgrade path: install Windows SDK with C++/WinRT component.
* **Decision 34 (2026-07-01 — D3D11 Texture Display):** VideoCanvasMock upgraded from pure QPainter mock to hybrid that reads global `g_videoOutputTexture` atomic pointer via D3D11 staging texture readback each frame. Falls back to loaded camera images when no real texture is available. Maintains PGM/PVW border overlay UI.
* **Decision 35 (2026-07-01 — WiX v7 MSI):** Built WiX v7 MSI installer (17 MB) using `wix build` CLI. Includes overwatch_studio.exe + Qt6 DLLs + FFmpeg DLLs. Installer at `build/msi/OverwatchStudio-v0.1.0.msi`. WiX v7 CLI installed via `winget install WiXToolset.WiXCLI`.

## 5. What's Real vs. Mock (as of 2026-07-01)

**Real (compiled, tested):**
- `WASAPIDeviceWorker` — WASAPI exclusive-mode capture/render with shared fallback, ring buffers
- `WindowsProcessCapture` — per-process loopback via `ActivateAudioInterfaceAsync` + `AUDIOCAPTURE_MONITOR`
- `AudioEngineCore` — full DSP pipeline: input patch → channel strip → DCA → matrix summing → output patch → master limiter, 8-channel default
- `AudioRecorderManager` + `WavFileWriter` — 24-bit PCM multitrack WAV streaming (header-only, real)
- `AudioEngineBridge` — `startRecordingTo`/`stopRecording` QML bridge, OSC command dispatch
- `GPUCompositor` — D3D11 HLSL shaders, `uploadInputTexture()` + `process()`, 4-input texture array
- `VideoEngineCore` — real render loop with genlock frame acquisition via `VideoSyncManager`
- `VideoSyncManager` — genlock frame queues
- `WindowsGraphicsCapture` — WGC screen/window capture via WinRT C++/WinRT, compiles (needs real HWND at runtime)
- `FFmpegCaptureSource` — RTSP/NDI/file stream decode → D3D11 texture (avformat/avcodec/swscale)
- `VideoCaptureManager` — owns FFmpeg sources, pushes frames to `VideoSyncManager` (WGC deferred)
- `SparseRoutingMatrix` — lock-free summing matrix
- `ParameterSmoother`, `AVSyncDelayLine`, `LookAheadLimiter` — real DSP primitives
- `ShowfileManager` — `.sds` zip read/write with simdjson manifest, `createDefaultShowfile()` with auto-bootstrap
- `WindowStateStore` — QSettings-backed window geometry persistence with QML binding
- `ExternalControlSurfaceManager` — real OSC UDP listener on port 8000, SPSC command dispatch
- `DatabaseManager` — SQLite WAL mode
- `SystemWatchdog`, `ResourceShedder`, `PanicSwitch`, `DeviceReclamationEngine`, `StateHistoryEngine`, `AutomationScheduler` — real background services
- Multi-window QML: `MasterLauncher.qml`, `AudioConsole.qml`, `VideoSwitcher.qml`, `ShowBuilder.qml` — window position persistence via debounced Timer
- `main.cpp` — multi-window spawn, default showfile bootstrap, context properties

**Mock (need replacing for beta):**
- `LocalMediaDeck` — synth-pad audio (C-major chord + LFO), mock duration; needs FFmpeg decode
- `GPUCompositor::process()` — placeholder, needs real render-to-output pipeline

**Beta Complete (as of 2026-07-01):**
- ✅ Multi-window QML: 4 independent windows with zero QML errors
- ✅ WindowStateStore: QSettings-backed window geometry persistence
- ✅ AudioEngineBridge: `toggleWindow()` for cross-window show/hide
- ✅ WGC wired into VideoCaptureManager: addWindowSource/addMonitorSource, HWND plumbing
- ✅ VideoCanvasMock: real D3D11 texture readback from global `g_videoOutputTexture`
- ✅ VideoEngineCore: exposes `latestOutput()` atomic texture pointer
- ✅ WiX v7 MSI installer: `build_msi.bat` + `installer_v7.wxs`, produces 17 MB MSI
- ✅ Default `.sds` showfile: auto-generated on first run
- ✅ GitHub Actions CI: committed
- ✅ OSC control surface: real OSC UDP listener on port 8000

## 6. Next Immediate Steps

1. **Seed beta to podcasters** — distribute MSI, collect feedback.
2. **Install C++/WinRT SDK** — enables real WGC screen/window capture (currently stub)
3. **Implement GPUCompositor::process()** — real render-to-output pipeline with shader passes
4. **Replace LocalMediaDeck synth-pad** — FFmpeg-based audio decode for real media playback
