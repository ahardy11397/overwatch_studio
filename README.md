# Overwatch Studio

**Software-defined sound console + video switcher for live production.**

A single-executable, multi-window production mixer built in C++20 with Qt Quick, D3D11 GPU compositing, and WASAPI audio. Targeted at at-home podcasters with 2+ monitors.

---

## Features

- **24-channel audio console** with per-channel DSP (HPF, fader, pan, mute, solo)
- **D3D11 GPU video compositor** — chroma key, transitions, upstream/downstream keyers, PiP
- **Multi-window UI** — Audio Console, Video Switcher, Show Builder, Master Launcher
- **Lock-free audio engine** — zero heap allocations in real-time paths, SPSC ring buffers
- **WASAPI exclusive mode** — sub-2ms round-trip latency
- **Per-process app capture** — loopback audio from individual Windows applications
- **Multitrack recording** — 8-channel 24-bit WAV stem recording
- **OSC control surface** — UDP 8000 in / 9000 out, Stream Deck compatible
- **`.sds` showfile format** — zip archive with manifest + SQLite database
- **WiX MSI installer** — bundles Qt runtime, VC++ redist, default showfile

## Screenshots

> *Coming soon — run the app and capture your own.*

---

## Requirements

| Requirement | Version |
|-------------|---------|
| Windows SDK | 10.0.22621+ |
| MSVC | 2022 (v19.3x+) |
| CMake | 3.25+ |
| Qt | 6.6.2 |
| vcpkg | latest |

### vcpkg Dependencies

Installed automatically via `vcpkg.json` manifest:

- soxr (sample rate conversion)
- simdjson (fast JSON parsing)
- libzip (.sds archive read/write)
- gtest (unit testing)
- sqlite3 (database persistence)
- readerwriterqueue (lock-free SPSC rings)
- ffmpeg (stream decode)

---

## Build

### 1. Bootstrap vcpkg (one-time)

```powershell
cd $env:USERPROFILE\vcpkg
.\bootstrap-vcpkg.bat
```

### 2. Configure

```powershell
cmake -B build -S . `
  -DCMAKE_TOOLCHAIN_FILE="$env:USERPROFILE\vcpkg\scripts\buildsystems\vcpkg.cmake"
```

> If Qt is not in the default location (`./libs/Qt/6.6.2/msvc2019_64`), set `-DQt6_DIR=` to your install.

### 3. Build

```powershell
cmake --build build --config Release
```

### 4. Run

```powershell
./build/bin/Release/overwatch_studio.exe
```

### 5. Run Tests

```powershell
cd build && ctest --output-on-failure -C Release
```

Or run a single test by name:

```powershell
./build/bin/Release/AudioEngineTests --gtest_filter="AudioEngineTest.VerifySparseMatrixMath"
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     UI Layer (Qt Quick)                      │
│  MasterLauncher │ AudioConsole │ VideoSwitcher │ ShowBuilder │
│         ↕              ↕              ↕              ↕       │
│  AudioEngineBridge   ShowBuilderBridge   VideoCanvasMock     │
├─────────────────────────────────────────────────────────────┤
│                   SPSC Lock-Free Rings                       │
├──────────────────┬──────────────────┬───────────────────────┤
│   Audio Engine   │  Video Engine    │   Control Layer       │
│   (WASAPI I/O)   │  (D3D11 GPU)     │   (OSC/MIDI/SQLite)  │
│                  │                  │                       │
│  AudioEngineCore │ GPUCompositor    │ ExternalCtrlSurface   │
│  ChannelStrip    │ VideoSyncManager │ ShowfileManager       │
│  RoutingMatrix   │ FFmpegCapture    │ DatabaseManager       │
│  LookAheadLimiter│ WinGraphicsCap   │ AutomationScheduler   │
│  WASAPIDevice    │ VideoCaptureMgr  │ StateHistoryEngine    │
│  ProcessCapture  │                  │ SystemWatchdog        │
│  RecorderManager │                  │ PanicSwitch           │
└──────────────────┴──────────────────┴───────────────────────┘
```

### Engine Layer (`src/core/`)

The engine is split into three subsystems, all sharing the same lock-free SPSC ring protocol for cross-thread communication:

**Audio** — `AudioEngineCore` owns the full DSP pipeline: input patch → channel strip (HPF, fader, pan) → DCA → sparse routing matrix → output patch → master limiter. `WASAPIDeviceWorker` handles actual I/O. `WindowsProcessCapture` provides per-process loopback via `ActivateAudioInterfaceAsync`. `AudioRecorderManager` streams multitrack 24-bit PCM to disk.

**Video** — `GPUCompositor` compiles 7 HLSL shaders (proc_amp, chroma_key, transition, DSK, upstream_keyer, fill_key_blend, quad) and builds constant/vertex buffers. `VideoSyncManager` provides software genlock with 3-frame ring buffers per input. `FFmpegCaptureSource` decodes RTSP/NDI/file streams to D3D11 textures. `WindowsGraphicsCapture` handles screen/window capture via WinRT.

**Control** — `ExternalControlSurfaceManager` runs an OSC UDP listener and WebSocket server. `ShowfileManager` handles `.sds` zip archives (manifest.json + SQLite). `AutomationScheduler` executes cue stacks with sub-frame timecode. `SystemWatchdog` monitors buffer jitter and triggers `ResourceShedder` under CPU pressure. `PanicSwitch` provides fade-to-black.

### UI Layer (`src/ui/`)

Four independent QML windows, each on its own `QQmlApplicationEngine`:

| Window | Purpose |
|--------|---------|
| **Master Launcher** | 360×520 launcher panel, opens other windows |
| **Audio Console** | 24-ch fader bank with meters, DSP, patch, DCA |
| **Video Switcher** | PGM/PVW multiview, transition controls, upstream/downstream keyers |
| **Show Builder** | Cue editor, routing matrix, diagnostics sandbox |

`AudioEngineBridge` and `ShowBuilderBridge` are the **only** C++ ↔ QML boundary — all engine interaction crosses through them via SPSC pushes.

### Real-Time Safety

All code on the audio/video callback path follows these rules:

- **Zero heap allocations** — pre-allocated pools (`std::array`, sized `std::vector`)
- **Lock-free SPSC rings** — `moodycamel::ReaderWriterQueue` for all inter-thread parameter flow
- **Cache-line alignment** — `alignas(64)` on all cross-thread structs (`RouteNode`, `VideoFrame`, `ControlCommand`)
- **`REALTIME_SAFE` annotation** — `[[clang::nonblocking]]` on Clang, no-op on MSVC

---

## Project Structure

```
overwatch_studio/
├── src/
│   ├── main.cpp                    # Entry point, 4-window setup
│   ├── core/
│   │   ├── audio/                  # WASAPI, DSP, routing, recording
│   │   ├── video/                  # D3D11 compositor, capture, sync
│   │   └── control/                # OSC, showfile, database, watchdog
│   └── ui/
│       ├── *.qml                   # QML windows
│       ├── *Bridge.*               # C++ ↔ QML boundary
│       └── assets/                 # Camera placeholder images
├── tests/                          # GoogleTest (4 files)
├── docs/superpowers/
│   ├── specs/                      # 13 design specifications
│   └── plans/                      # 15 implementation plans
├── builder/                        # Master spec, research docs
├── installer/                      # WiX v5 MSI installer
├── libs/Qt/6.6.2/                  # Local Qt installation
├── assets/shows/default.sds        # Default showfile
├── vcpkg.json                      # vcpkg manifest
└── CMakeLists.txt                  # Build system
```

---

## Testing

Four GoogleTest files covering all subsystems:

| File | Tests |
|------|-------|
| `AudioEngineTests.cpp` | Sparse matrix math, parameter smoothing, AV sync delay, WASAPI capture |
| `DynamicAudioEngineTests.cpp` | Pre-allocated pools, fader mapping, HPF, DCA, WAV recording, routing |
| `ControlEngineTests.cpp` | SPSC queue, DatabaseManager, ShowfileManager, default showfile |
| `VideoEngineTests.cpp` | Genlock sync, struct alignment, D3D11 shader compilation, render loop |

```powershell
# Run all tests
cd build && ctest --output-on-failure -C Release

# Run a specific test
./build/bin/Release/AudioEngineTests --gtest_filter="VideoEngineTest.ShaderCompilation"
```

---

## CI/CD

GitHub Actions runs on every push/PR to `master`:

- Windows runner, Debug + Release matrix
- vcpkg dependency install
- CMake build + CTest
- D3D11 shader compilation check (NULL device)
- Release artifact upload (7-day retention)

---

## Installer

WiX v5 MSI installer packages:

- `overwatch_studio.exe`
- Qt 6.6.2 runtime (Core, Gui, Qml, Quick, Widgets, Network, Svg)
- VC++ 2022 redistributable
- Default `.sds` showfile
- Start Menu + Desktop shortcuts

```powershell
# Build installer
.\installer\build-installer.ps1 -Config Release
# Output: build\installer\OverwatchStudio-Setup.msi
```

---

## Showfile Format (`.sds`)

A "Software-Defined Show" is a ZIP archive containing:

| File | Description |
|------|-------------|
| `manifest.json` | Show metadata, channel/bus/DCA names, cue list with transitions |
| `show.db` | SQLite database (WAL mode) with full state: channels, buses, DCAs, routing, global state |

Default schema includes 8 channels, 2 buses, 8 DCAs, 3 cues, and routing tables. Generated automatically on first launch.

---

## License

*Not yet specified.*

---

## Contributing

This project is in active beta development. See `builder/project_context_ledger.md` for the current development state and `docs/superpowers/plans/` for implementation roadmaps.

Key conventions:

- No heap allocations in real-time paths
- All cross-thread state flows through `SPSCQueue`
- Cache-line alignment (`alignas(64)`) on shared structs
- Match existing code style (PascalCase, `#pragma once`, `std::span`)
- Run QML brace checker before committing: `python scratch/check_brackets.py`
