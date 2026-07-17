# AGENTS.md

## What is this

C++20 / Qt 6.6.2 / MSVC 2022 single-executable live production mixer (audio console + video switcher). Windows-only. CMake 3.25+, vcpkg manifest mode.

## Build & test

```powershell
# Configure (one-time, or after CMakeLists.txt changes)
cmake -B build -S . -DCMAKE_TOOLCHAIN_FILE="$env:USERPROFILE\vcpkg\scripts\buildsystems\vcpkg.cmake"

# Build
cmake --build build --config Debug   # or Release

# Run all tests (GoogleTest)
cd build && ctest --output-on-failure -C Debug

# Run a single test
./build/bin/Debug/AudioEngineTests --gtest_filter="AudioEngineTest.VerifySparseMatrixMath"

# Run the app (after Release build)
./build/bin/Release/overwatch_studio.exe
# Or use _run.bat which sets up PATH for Qt DLLs
```

**Qt DLLs:** `_run.bat` calls VsDevCmd.bat and prepends Qt bin + QML import paths to PATH. If you run the exe directly without this, Qt plugins won't load. The exe also walks up from its own directory looking for `libs/Qt/6.6.2/msvc2019_64/bin` at startup.

**vcpkg:** Dependencies are in `vcpkg.json`. Installed to `vcpkg_installed/` (gitignored). If configure fails with missing packages, run `vcpkg install` from the repo root.

## Critical constraints (audio/video real-time paths)

- **Zero heap allocations** — no `malloc`/`new` in audio/video callback threads. Use pre-allocated `std::array`, sized `std::vector`, or `SPSCQueue`.
- **SPSC rings for all cross-thread state** — `SPSCQueue<T>` wraps `moodycamel::ReaderWriterQueue`. Never write raw atomics or shared variables for UI→engine flow.
- **Cache-line alignment** — `alignas(64)` on any struct read/written across threads (e.g. `RouteNode`, `VideoFrame`).
- **`REALTIME_SAFE`** = `[[clang::nonblocking]]` on Clang, no-op on MSVC. This is intentional, not a bug.
- **AVX2** — `/arch:AVX2` on MSVC, `-mavx2 -mfma` on Clang. RealtimeSanitizer (`-fsanitize=realtime`) on Clang only.

## Architecture

Two layers, connected by SPSC queues:

**Engine layer (`src/core/`)** — INTERFACE library `overwatch_engine`:
- `core/audio/` — WASAPI I/O, DSP pipeline, routing matrix, WAV recording
- `core/video/` — D3D11 GPU compositor, HLSL shaders, capture sources, genlock sync
- `core/control/` — SPSC queue wrapper, OSC, showfile (zip+json+sqlite), watchdog, automation

**UI layer (`src/ui/`)** — Qt Quick multi-window:
- `AudioEngineBridge` and `ShowBuilderBridge` are the **only** C++↔QML boundary
- 4 independent QML windows: `MasterLauncher.qml`, `AudioConsole.qml`, `VideoSwitcher.qml`, `ShowBuilder.qml`
- Each window gets its own `QQmlApplicationEngine`; bridges shared via context properties
- `Main_recovered.qml` is a safety-net backup — never delete it

**File layout** is flat within each subdir (no per-feature folders). Common prefixes: `*Bridge` (QML boundary), `*Engine` (callback owner), `*Manager` (background service).

**`libs/`** contains JUCE 7.0.9 and libobs 30.1.2 submodules. CMake conditionally compiles them or falls back to header mocks.

## Real-time log

`qInstallMessageHandler` writes to `overwatch_studio_realtime.log` at repo root on every run. First thing to check when the app misbehaves.

## QML

- **Brace checker:** `scratch/check_brackets.py` — run before committing any QML changes. The `scratch/` directory is gitignored.
- QML files are registered via `qt_add_qml_module` in CMakeLists.txt. If you add a new `.qml` file, add it to the `QML_FILES` list.
- Style: `QQuickStyle::setStyle("Basic")` in main.cpp.

## Tests

Single executable `AudioEngineTests` (name is misleading) compiled from 4 files:
- `AudioEngineTests.cpp` — sparse matrix, parameter smoothing, AV sync, WASAPI
- `DynamicAudioEngineTests.cpp` — pools, fader, HPF, DCA, WAV recording, routing
- `ControlEngineTests.cpp` — SPSC queue, DatabaseManager, ShowfileManager
- `VideoEngineTests.cpp` — genlock, alignment, D3D11 shader compilation, render loop

## Design docs

Read in this order if you need deep context:
1. `builder/master_builder.md` — master technical spec (formulas, SPSC layout, safety constraints)
2. `builder/project_context_ledger.md` — live state tracker, decision register, next steps
3. `docs/superpowers/specs/` — 13 design specs (math + component decisions)
4. `docs/superpowers/plans/` — implementation plans with `- [ ]` task tracking

## Code style

No formatter config. Match the file you're editing: PascalCase classes, `#pragma once`, `std::span`/`std::array` in DSP, no `m_` member prefix.

## Gotchas

- `scratch/` is gitignored — throwaway scripts only, never load-bearing code.
- `src/ui/*.py` (`update_main*.py`, `fix_duplicates.py`) are historical QML regeneration scripts — not part of the build.
- `ui_sandbox.db` + its `-shm`/`-wal` sidecars are real dev state, not junk.
- `test_show.sds` at repo root is a test fixture.
- When adding new source files to the engine, add them to **both** the `AudioEngineTests` target and the `overwatch_studio` target in CMakeLists.txt.
- Shader files in `src/core/video/shaders/` must stay paired with `GPUCompositor.h`.
- WiX MSI build requires WiX toolset installed (`winget install WiXToolset.WiXCLI`). Use `build_msi.bat`.

## Open Design (MCP)

For UI/QML work, start the Open Design daemon first:
```bash
node ~/open-design/apps/daemon/bin/od.mjs --port 7456 --no-open
```
Or run `_start_open_design.bat`. Configured as MCP server in `.mcp.json`.
