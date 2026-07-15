# Overwatch Studio: Software-Defined Live Production Ecosystem

## Project Overview
Overwatch Studio is a single-executable, multi-window, high-performance live production machine designed to compete with enterprise hardware platforms. It integrates a professional-grade live audio mixing engine (SDSC) with a GPU-accelerated live video switcher (SDVS) and media presenter.

### Core Architecture
- **Frameworks:** Qt 6.6.2 LTS (UI Shell), JUCE 7.0.9 (Audio/Plugin Host), libobs 30.1.2 (Video Core).
- **Real-Time Constraints:** Round-trip audio latency $< 2\text{ms}$, video rendering at $60\text{fps}$ ($16.67\text{ms}$ window).
- **Concurrency:** Uses `moodycamel::ReaderWriterQueue` (SPSC) for lock-free communication between UI and real-time threads to prevent priority inversion.
- **Memory Management:** Strictly **zero real-time allocations** (`malloc`, `free`, `new`, `delete`) in audio/video threads.
- **GPU Centric:** Zero-copy GPU texture sharing for video capture/switching to minimize PCIe bandwidth and CPU overhead.
- **State Management:** `.sds` (Software-Defined Show) containers are zip-based bundles with `manifest.json` (`simdjson`) and SQLite (WAL mode) for asset metadata.

## Directory Structure
- `/src/core/audio/`: Real-time, lock-free ASIO/WASAPI DSP callback threads.
- `/src/core/video/`: Headless `libobs` compositor and GPU texture synchronizers.
- `/src/core/control/`: Background automation, OSC/MIDI translation, and SPSC queues.
- `/src/ui/`: Qt 6 QML workspace layouts (Multi-window: Audio, Video, Show Builder).
- `/builder/`: Technical specifications and project context ledger.
- `/libs/`: Git submodules for JUCE and libobs.

## Building and Running
The project uses **CMake (3.25+)** with **vcpkg Manifest Mode** for dependency management.

### Prerequisites
- **Compiler:** MSVC 2022 (v143 Toolchain).
- **SDK:** Windows 10 SDK (10.0.22621.0) or higher (Required for `AUDIOCAPTURE_MONITOR` and WGC).
- **vcpkg:** Must be installed and pointed to in the CMake toolchain file.

### Build Commands
```powershell
# Configure the project
cmake -B build -S . -DCMAKE_TOOLCHAIN_FILE="[path_to_vcpkg]/scripts/buildsystems/vcpkg.cmake"

# Build the project (Release)
cmake --build build --config Release
```

# Overwatch Studio: Software-Defined Live Production Ecosystem

## Project Overview
Overwatch Studio is a single-executable, multi-window, high-performance live production machine designed to compete with enterprise hardware platforms. It integrates a professional-grade live audio mixing engine (SDSC) with a GPU-accelerated live video switcher (SDVS) and media presenter.

### Core Architecture
- **Frameworks:** Qt 6.6.2 LTS (UI Shell), JUCE 7.0.9 (Audio/Plugin Host), libobs 30.1.2 (Video Core).
- **Real-Time Constraints:** Round-trip audio latency $< 2\text{ms}$, video rendering at $60\text{fps}$ ($16.67\text{ms}$ window).
- **Concurrency:** Uses `moodycamel::ReaderWriterQueue` (SPSC) for lock-free communication between UI and real-time threads to prevent priority inversion.
- **Memory Management:** Strictly **zero real-time allocations** (`malloc`, `free`, `new`, `delete`) in audio/video threads.
- **GPU Centric:** Zero-copy GPU texture sharing for video capture/switching to minimize PCIe bandwidth and CPU overhead.
- **State Management:** `.sds` (Software-Defined Show) containers are zip-based bundles with `manifest.json` (`simdjson`) and SQLite (WAL mode) for asset metadata.

## Directory Structure
- `/src/core/audio/`: Real-time, lock-free ASIO/WASAPI DSP callback threads.
- `/src/core/video/`: Headless `libobs` compositor and GPU texture synchronizers.
- `/src/core/control/`: Background automation, OSC/MIDI translation, and SPSC queues.
- `/src/ui/`: Qt 6 QML workspace layouts (Multi-window: Audio, Video, Show Builder).
- `/builder/`: Technical specifications and project context ledger.
- `/libs/`: Git submodules for JUCE and libobs.

## Building and Running
The project uses **CMake (3.25+)** with **vcpkg Manifest Mode** for dependency management.

### Prerequisites
- **Compiler:** MSVC 2022 (v143 Toolchain).
- **SDK:** Windows 10 SDK (10.0.22621.0) or higher (Required for `AUDIOCAPTURE_MONITOR` and WGC).
- **vcpkg:** Must be installed and pointed to in the CMake toolchain file.

### Build Commands
```powershell
# Configure the project
cmake -B build -S . -DCMAKE_TOOLCHAIN_FILE="[path_to_vcpkg]/scripts/buildsystems/vcpkg.cmake"

# Build the project (Release)
cmake --build build --config Release
```

## Development Conventions
- **Memory Safety:** No heap allocations in the audio/video loops. Use `RTSan` (Real-Time Sanitizer) for verification.
- **Lock-Free Code:** All inter-thread parameter updates must flow through SPSC rings with 64-byte cache-line alignment (`alignas(64)`).
- **Performance:** Code is optimized for AVX2 instructions (`/arch:AVX2`).
- **Context Preservation:** Always consult and update `/builder/project_context_ledger.md` to maintain session continuity and track milestone progress.

## Key Documentation
- `builder/master_builder.md`: The absolute master technical specification and architectural blueprint.
- `builder/project_context_ledger.md`: Live tracking of project state, decisions, and development progress.

## Superpowers Skills & Agent Behavior
- **Explicit Instruction Enforcement:** Always invoke the `/using-superpowers` skill and related workflow templates (such as brainstorming, test-driven development, writing plans, and verification check gates) for any creative work, layout changes, features, bug fixes, or modifications requested by the user.
