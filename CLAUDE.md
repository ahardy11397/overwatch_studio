# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Overwatch Studio — a Windows single-executable, multi-window live production mixer ("software-defined sound console" + "software-defined video switcher"). C++20, Qt 6.6.2, MSVC 2022, CMake 3.25+, vcpkg manifest mode.

Hard runtime constraints: round-trip audio latency < 2 ms, 60 FPS video, **zero heap allocations in audio/video real-time threads**, all inter-thread parameter flow through lock-free SPSC rings (`moodycamel::ReaderWriterQueue`, `alignas(64)` cache-line alignment). The codebase is aggressively AVX2 (`/arch:AVX2`, `-mavx2 -mfma`), with RealtimeSanitizer (`-fsanitize=realtime`) on Clang.

## Current Development Stage

**Next release: BETA (target: at-home podcasters, 2+ monitors).**

The alpha is mock-heavy; the beta requires **real audio AND real video**, not simulations. Two plans drive this:

- `docs/superpowers/plans/2026-06-29-beta-real-audio-path.md` — real WASAPI capture → DSP → render, per-process app capture, 8-channel 24-bit WAV stem recording
- `docs/superpowers/plans/2026-06-29-beta-remaining-systems.md` — real video capture (Windows GraphicsCapture + FFmpeg for NDI/RTSP), multi-window QML with position persistence, OSC control surface (oscpp), default `.sds` showfile, GitHub Actions CI, WiX v5 installer

### Beta scope decisions (ahard, 2026-06-29)

- **Persona:** at-home podcasters, 2+ monitors. Not broadcast engineers.
- **Audio:** WASAPI exclusive mode for beta; ASIO deferred to v1. Round-trip < 2 ms.
- **Video:** Windows Graphics Capture (screen/window) + FFmpeg (RTSP/NDI) for beta. libOBS deferred — too heavy to build.
- **Channels:** user-programmable in spec, but beta ships fixed 8-channel / 2-bus / 8-DCA default.
- **Recording:** 8 mono 24-bit WAV stems (hard beta requirement). Mix-only not acceptable.
- **Control surface:** OSC-only for beta (oscpp, UDP 8000 in / 9000 out). MIDI/MCU deferred.
- **Codecs:** WAV-only for beta. AAC/FLAC/Opus for full release.
- **Persistence:** window positions persist across runs via `QSettings`. Showfiles via `.sds` (zip + manifest.json + SQLite WAL).
- **CI:** GitHub Actions Windows runner, unit tests + D3D11 NULL device shader compile tests. Audio/video smoke-tests validated by humans.
- **Installer:** WiX v5 MSI. Bundle Qt runtime (~250 MB), VC++ 2022 ucrt, vcpkg CRT.
- **QML brace-checker:** `scratch/check_brackets.py` exists and works. Run it before committing QML.

### What's real vs. mock (as of 2026-06-29)

**Real (compiled, tested):**
- `WASAPIDeviceWorker` — WASAPI shared-mode capture/render with ring buffers
- `WindowsProcessCapture` — per-process loopback via `ActivateAudioInterfaceAsync` + `AUDIOCAPTURE_MONITOR`, with system-loopback fallback
- `AudioEngineCore` — full DSP pipeline: input patch → channel strip → DCA → matrix summing → output patch → master limiter
- `AudioRecorderManager` + `WavFileWriter` — 24-bit PCM multitrack WAV streaming (header-only, real)
- `GPUCompositor` — D3D11 HLSL shaders (proc_amp, chroma_key, transition, DSK, etc.) embedded as string literals
- `VideoSyncManager` — genlock frame queues
- `SparseRoutingMatrix` — lock-free summing matrix
- `ParameterSmoother`, `AVSyncDelayLine`, `LookAheadLimiter` — real DSP primitives
- `ShowfileManager` — `.sds` zip read with simdjson manifest parse
- `DatabaseManager` — SQLite WAL mode
- `SystemWatchdog`, `ResourceShedder`, `PanicSwitch`, `DeviceReclamationEngine`, `StateHistoryEngine`, `AutomationScheduler` — real background services

**Mock (need replacing for beta):**
- `AudioEngineBridge::m_simulatedAudioThread` — generates sine+noise for unpatched channels; must be replaced with real-device-only path
- `LocalMediaDeck` — synth-pad audio (C-major chord + LFO), mock duration; needs FFmpeg decode
- `VideoCanvasMock` — QPainter fallback rendering; needs real D3D11 texture interop
- `VideoEngineCore` — header-only, no real render loop
- `ExternalControlSurfaceManager` — simulator threads (sleep loops), no real OSC/UDP

**Not yet started (new code for beta):**
- `FFmpegCaptureSource` — NDI/RTSP stream capture
- `WindowsGraphicsCapture` — screen/window capture via WinRT/C++/WinRT
- `VideoCaptureManager` — owns capture sources, feeds `VideoSyncManager`
- Multi-window QML (Master Launcher + 3 child windows)
- `WindowStateStore` — `QSettings`-backed position persistence
- Default `.sds` showfile generator
- GitHub Actions CI workflow
- WiX v5 installer

## Build / test commands

All commands below are PowerShell/bash-flavored — run in the shell of your choice. **No separate `make` or Ninja generator is used**; the project is a single-configuration CMake build driven by MSVC.

```powershell
# 1. Bootstrap vcpkg (one-time)
cd $env:USERPROFILE\vcpkg          # or wherever you cloned it
.\bootstrap-vcpkg.bat

# 2. Configure build — repo's existing CMakeCache points vcpkg to
#    C:/Users/ahard/vcpkg/scripts/buildsystems/vcpkg.cmake and Qt to
#    ./libs/Qt/6.6.2/msvc2019_64. Adjust if your install differs.
cmake -B build -S . `
  -DCMAKE_TOOLCHAIN_FILE="$env:USERPROFILE\vcpkg\scripts\buildsystems\vcpkg.cmake"

# 3. Build everything (Debug or Release)
cmake --build build --config Debug
cmake --build build --config Release

# 4. Run the full test suite
cd build && ctest --output-on-failure -C Debug

# 5. Run a single GoogleTest by name
./build/bin/AudioEngineTests --gtest_filter="AudioEngineTest.VerifySparseMatrixMath"

# 6. Run the application (after a successful build)
./build/bin/overwatch_studio.exe
```

The Qt-style `qInstallMessageHandler` writes to `overwatch_studio_realtime.log` at the repo root on every run — it's the first thing to check when the app misbehaves.

## Architecture (the parts you can't afford to re-read every time)

**Engine layer (`src/core/*`)** lives in `overwatch_engine`, an INTERFACE library that groups three sub-include dirs (`audio/`, `control/`, `video/`) and the third-party libs (soxr, simdjson, libzip). The executable and the test target both link it.

- `core/audio/` — real-time DSP. `AudioEngineCore` is the WASAPI/ASIO callback owner; `AudioChannelStrip`, `SparseRoutingMatrix`, `LookAheadLimiter`, `ParameterSmoother`, `AVSyncDelayLine` are the per-channel DSP pipeline. `WindowsProcessCapture` + `WASAPIDeviceWorker` are the actual I/O threads; `RoutingPatchMap` defines tap points (`PreFader`/`PostFader`/etc.) used everywhere. `AudioRecorderManager` streams background multitrack PCM to disk over SPSC.
- `core/video/` — headless D3D11 compositor. `GPUCompositor` compiles HLSL shaders (`shaders.hlsl`) and builds constant/vertex buffers; `VideoEngineCore` + `VideoSyncManager` drive the frame loop. Several shader files are tracked: `chroma_key.hlsl`, `transition.hlsl`, `dsk.hlsl`, `quad.hlsl`, plus composite passes (`proc_amp.hlsl`, `fill_key_blend.hlsl`, `upstream_keyer.hlsl`).
- `core/control/` — background automation/OSC/MIDI and the plumbing. `SPSCQueue<T>` wraps `moodycamel::ReaderWriterQueue` with a `REALTIME_SAFE` annotation (`[[clang::nonblocking]]` on Clang, no-op elsewhere). `RealtimeLogger` is the singleton sink Qt messages route to; `SystemWatchdog` and `ResourceShedder` handle CPU pressure; `StateHistoryEngine`, `ShowfileManager`, `DatabaseManager`, `ExternalControlSurfaceManager`, `PanicSwitch`, `DeviceReclamationEngine`, `AutomationScheduler` are independent services.

**UI layer (`src/ui/`)** is the Qt Quick shell. `AudioEngineBridge` and `ShowBuilderBridge` are the **only sanctioned C++ ↔ QML boundary** — all engine interaction crosses through them, and all heavy work they do is marshalled into SPSC pushes. `Main.qml` is the QML root; `src/ui/Main_recovered.qml` is a backup kept because QML edits have a history of being clobbered (do not delete it — it's the safety net). `VideoCanvasMock` is a stand-in GPU surface used while the real D3D11 pipeline lands. `LocalMediaDeck` is the audio/video clip playback subsystem.

**File layout is intentionally flat within each subdir** (no per-feature subfolders) — grep the headers for `class <Name>` to map ownership quickly. Common prefixes to know: `*Bridge` (QML boundary), `*Engine` (callback owner), `*Manager` (background service), `*Switch`/`*Scheduler` (control-plane logic).

**`libs/` is the JUCE 7.0.9 and libobs 30.1.2 submodule tree**. `CMakeLists.txt` branches at configure time — if `libs/juce/CMakeLists.txt` exists the real JUCE is compiled; otherwise a local header mock configuration is generated so that code that only/audio-frees-standing classes still links. Don't edit the mock branch unless you are deliberately test-driving without the submodule checked out.

**State containers**: `.sds` "Software-Defined Show" files are just zip archives containing `manifest.json` (parsed with `simdjson`) plus a SQLite database in WAL mode. `test_show.sds` at the repo root is a fixture; `ui_sandbox.db` is the dev SQLite state file (WAL-mode, so the `-shm` and `-wal` sidecars are real state, not junk).

## Tests

Four GoogleTest files under `tests/`: `AudioEngineTests.cpp`, `DynamicAudioEngineTests.cpp`, `ControlEngineTests.cpp`, `VideoEngineTests.cpp`. They are all compiled together into the single `AudioEngineTests` executable defined in `CMakeLists.txt`. Tests exercise the lock-free queues, routing matrix math, QML bridge round-trip, WASAPI capture, and video compositor stages — so changes in `core/` or `ui/` often need a new test in the matching file even though the executable name is misleading. `cd build && ctest --output-on-failure -C Debug` to run, or call the binary directly and use `--gtest_filter`.

## Docs that matter

- `builder/master_builder.md` — absolute master technical spec (formulas, SPSC ring layout, safety constraints). This is the design source of truth and the bootstrapping entry for any context load.
- `builder/project_context_ledger.md` — live session-state tracker: chronological decision register, milestone checklists, and "next immediate steps". Update it after completing any non-trivial task; it doubles as memory across sessions.
- `docs/superpowers/specs/` — design specifications (math + layout + component layout decisions). These are the *agreed* design. List by topic: `2026-05-23-dca-mute-groups-design.md` (lock-free mute groups), `2026-05-25-ultimate-channel-strip-spec.md` (UDCS-1 strip math), `2026-05-25-mixer-dsp-integration-design.md`, `2026-05-29-hybrid-eq-design.md` (touch-node EQ curves), `2026-05-30-audio-patch-board-design.md`, `2026-05-30-dynamic-routing-and-layers-design.md`, `2026-06-02-audio-backend-recording-design.md` (WAV streaming), `2026-06-02-audio-console-metering-and-control-design.md`, `2026-06-03-visuals-and-meters-design.md`, `2026-06-04-audio-latency-fix-design-spec.md`, `2026-06-05-app-capture-and-output-patch-design.md`, `2026-06-06-individual-device-routing-design.md`, `2026-06-06-qml-layout-and-syntax-fix-design.md`.
- `docs/superpowers/plans/` — implementation plans dated by topic. These are concrete step-by-step task lists with `- [ ]` tracking; the most recent un-closed plans are the live work items. Referenced from the ledger's "Next Immediate Steps".
- `builder/UI Specification Research.md`, `builder/Blackmagic Switcher Tech Report.md`, `builder/Media_Graphics_Engines_Architecture.md` — vendor/market research; informative but not normative.

## Conventions specific to this codebase

- Do not introduce heap allocations in anything called from the audio/video callback path. The spec and CMake both enforce this; prefer pre-allocated pools (`std::array`, `std::vector` sized at init) and the existing `SPSCQueue`.
- When you need to ship state from UI → engine, push through a queue in `SPSCQueue.h`, never by writing to a raw atomic or (worse) a shared variable.
- Cache-line alignment is load-bearing: any struct read/written across threads is `alignas(64)` (see `RouteNode`).
- `REALTIME_SAFE` is Clang-only (`[[clang::nonblocking]]`). MSVC builds silently elide it; this is a known gap, not a bug to fix casually.
- Three tracked shader files in `src/core/video/shaders/` must stay paired with `GPUCompositor.h` — if you add a new pass, update both.
- The `scratch/` directory at the repo root is throwaway (gitignored in practice). Use it for one-off scripts; do not put load-bearing code there.
- `src/ui/*.py` (`update_main.py`, `update_main2.py`, `update_main3.py`, `fix_duplicates.py`) are historical QML regeneration scripts — they are not part of the build and are offline references only.

## Tooling

No clang-format / clang-tidy / `.editorconfig` at the repo root. No Cursor rules, no Copilot instructions. Style empirically follows the predominant existing patterns (PascalCase classes, `m_` member prefix is *not* used, `#pragma once` everywhere, heavy use of `std::span` and `std::array` in DSP). Match the file you're editing rather than imposing a new style.

If you are on Windows, MSVC 19.3x+, Windows SDK 10.0.22621+, and a working vcpkg checkout are all load-bearing — configure errors are almost always "Qt6_DIR not found" (point it at `./libs/Qt/6.6.2/msvc2019_64`) or "vcpkg deps not installed" (re-run `vcpkg install`).

## Open Design MCP (UI Design Assistant)

[Open Design](https://github.com/open-design) (`~/open-design/`) provides a local daemon with 70+ design skills covering UI prototyping, design systems, component design, and frontend review. It's configured as an MCP server in `.mcp.json` for this project.

**Before a session where you'll work on UI/QML:** start the daemon:
```bash
node ~/open-design/apps/daemon/bin/od.mjs --port 7456 --no-open
```
Or run `_start_open_design.bat` to start it in the background.

**Relevant skills available through Open Design:**
- `frontend-design` — production-grade UI with strong visual direction
- `platform-design` — 300+ design rules from Apple HIG, Material 3, WCAG 2.2
- `design-taste-frontend` — anti-slop frontend for landing pages, portfolios, redesigns
- `stitch-loop` — iterative design-to-code feedback loop (critique → adjust → ship)
- `theme-factory` — professional font/color themes for artifacts
- `design-review` — visual audit with before/after
- `ui-skills` — opinionated constraints for UI output quality

**To use a skill in a session:** invoke it via the `/skill` command or the Skill tool with the Open Design MCP server name.
