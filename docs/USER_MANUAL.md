# Overwatch Studio — User Manual

> **Version 0.1.0 (Beta)** — Software-defined sound console + video switcher for live production.
> Target: at-home podcasters with 2+ monitors.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Master Launcher](#2-master-launcher)
3. [Audio Console](#3-audio-console)
4. [Video Switcher](#4-video-switcher)
5. [Show Builder](#5-show-builder)
6. [Audio Engine (C++ Bridge)](#6-audio-engine)
7. [Video Pipeline](#7-video-pipeline)
8. [Control Surface (OSC / MIDI)](#8-control-surface)
9. [Showfile Format (.sds)](#9-showfile-format)
10. [System I/O Configuration](#10-system-io-configuration)
11. [Recording](#11-recording)
12. [Keyboard / Mouse Reference](#12-keyboard--mouse-reference)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Getting Started

### Launch

Run `overwatch_studio.exe`. On first launch the app creates a default showfile (`assets/shows/default.sds`) with 8 input channels, 2 buses, 8 DCAs, and 3 cue slots.

The **Master Launcher** window opens automatically. All other windows are opened from the launcher's toggle switches.

### Window Layout

| Window | Default Size | Purpose |
|--------|-------------|---------|
| Master Launcher | 360×520 | Central hub — open/close other windows, panic button |
| Audio Console | 1920×1080 | 24-ch fader bank, EQ, dynamics, routing, recording |
| Video Switcher | 1920×1080 | 4-camera PGM/PVW, transitions, media deck, DSK |
| Show Builder | 1920×1080 | Diagnostics sandbox, cue editor, scene snapshots |

All windows stay on top by default. Window positions persist across sessions via QSettings.

### Color Language

| Color | Meaning |
|-------|---------|
| `#00d084` Green | Active / enabled / master |
| `#00BDD6` Cyan | Selected / editing / routes |
| `#00a0f0` Blue | Video program / active camera |
| `#00E676` Green | Preview / monitoring |
| `#ffb300` Amber | Solo / warning / DCA |
| `#ff3b30` Red | Mute / panic / recording |
| `#E040FB` Magenta | Peak meters / saturator |
| `#7c4dff` Purple | RMS meters / compressor GR |
| `#8a8d98` Gray | Labels / inactive |
| `#1c1f25` Dark | Card backgrounds |
| `#0a0c10` Black | Window backgrounds |

---

## 2. Master Launcher

The launcher is a 360×520 panel that controls which windows are visible.

### Module Toggles

Three toggle switches open/close the child windows:

| Toggle | Window | Accent |
|--------|--------|--------|
| Audio Touch Console | Audio Console | Green `#00d084` |
| GPU Video Switcher | Video Switcher | Blue `#00a0f0` |
| Show Builder Sandbox | Show Builder | Amber `#f0b000` |

Click the toggle or the card to open/close. The switch animates when active.

### Emergency Panic (FTB)

The red **EMERGENCY PANIC (FTB)** button at the bottom toggles **Fade to Black**. When active:
- Button turns red with pulsating glow
- Text changes to "FTB ACTIVE"
- All video outputs fade to black
- Audio master mutes (engine-level, not just UI)

Press again to release. This is also accessible via OSC (`/video/ftb`).

---

## 3. Audio Console

The main mixing interface. 1920×1080, organized into 4 tabs.

### Tab Bar

| Tab | Purpose |
|-----|---------|
| AUDIO FADERS | Channel strips, master, EQ, dynamics |
| OUTPUT MATRIX | Route grid, output patches, tap points |
| SYSTEM I/O | WASAPI device selection, sample rate, buffer |
| RECORDING | Multitrack WAV transport and routing |

### Edit Layer (Bank Selector)

Above the channel strips, 5 bank buttons select which channels are displayed:

| Bank | Channels Shown |
|------|---------------|
| Ch 1–8 | Input channels 1–8 |
| Ch 9–16 | Input channels 9–16 |
| Ch 17–24 | Input channels 17–24 |
| DCA 1–8 | DCA master faders |
| ASSIGN | DCA group assignment mode |

The active bank is highlighted in cyan. All faders, meters, and DSP controls update to reflect the selected bank.

### Channel Strip

Each of the 12 visible strips (per bank) contains:

```
┌─────────────┐
│  Ch 1 Label  │  ← Cyan, 8px
├─────────────┤
│  Peak Meter  │  ← Magenta (#E040FB), 4×180px
│  RMS Meter   │  ← Purple (#7c4dff), 4×180px
├─────────────┤
│              │
│   Fader      │  ← Vertical slider, 0–100%, cyan accent
│   (180px)    │
│              │
├─────────────┤
│  Pan Knob    │  ← 28×28 circle, amber indicator
│  [-100..+100]│
├─────────────┤
│  [S]  [M]    │  ← Solo (amber) / Mute (red)
├─────────────┤
│  DCA Label   │  ← Shows DCA group assignment
│  Input Src   │  ← Source device name
└─────────────┘
```

**Fader:** Drag vertically. Range 0.0–1.0 (0–100%). Pushes volume to engine in real-time via SPSC queue.

**Pan Knob:** Click and drag horizontally. Left = -100 (hard left), Center = 0, Right = +100 (hard right). Amber dot shows current position.

**Solo (S):** Click to solo this channel. Only soloed channels pass to the solo bus. Multiple channels can be soloed simultaneously.

**Mute (M):** Click to mute. Red background when active. Mute is pre-fader (affects channel before bus routing).

**DCA Label:** Shows which DCA group this channel belongs to (e.g., "DCA 1" through "DCA 8"). DCA assignment is done in the ASSIGN bank or via the routing matrix.

**Input Source:** Shows the hardware input device name. Truncated if long.

### Per-Channel DSP Panel

Click the channel label or a dedicated DSP button to expand the DSP panel (430×260). Contains three processing blocks:

#### Gate

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| Threshold | -60–0 dB | -40 dB | Level below which gate closes |
| Attack | 0.1–100 ms | 1 ms | How fast gate opens |
| Hold | 10–1000 ms | 100 ms | How long gate stays open after signal drops |
| Release | 50–500 ms | 100 ms | How fast gate closes |
| Bypass | on/off | off | Skips gate processing |

GR (gain reduction) meter shown in amber.

#### Compressor

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| Threshold | -40–0 dB | -20 dB | Level above which compression begins |
| Ratio | 1–20 | 4:1 | Compression ratio |
| Attack | 0.1–100 ms | 10 ms | How fast compressor responds |
| Release | 50–500 ms | 200 ms | How fast compressor releases |
| Bypass | on/off | off | Skips compressor processing |

GR meter shown in purple.

#### Saturator

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| Drive | 0–30 | 0 | Saturation amount |
| Output | 0.5–1.5 | 1.0 | Output level compensation |
| Bypass | on/off | off | Skips saturator processing |

Drive meter shown in magenta.

### EQ Section (Per Channel)

4-band parametric EQ, displayed as a 2×2 knob grid:

| Band | Knobs | Range |
|------|-------|-------|
| Band 0 | Freq / Gain | 20–20000 Hz / ±15 dB |
| Band 1 | Freq / Gain | 20–20000 Hz / ±15 dB |
| Band 2 | Freq / Gain | 20–20000 Hz / ±15 dB |
| Band 3 | Freq / Gain | 20–20000 Hz / ±15 dB |

Each band also has:
- **Q knob:** 0.1–10 (logarithmic), controls bandwidth
- **Type selector:** Peaking, LowShelf, HighShelf, Notch

Drag knobs vertically to change values. Frequency uses logarithmic mapping (dragging 1px at low freq = small change, at high freq = large change).

### Master Section

Located at the right side of the fader bank:

- **Master Fader:** 260px vertical slider, green accent (`#00d084`). Range 0–100%.
- **Master Mute:** 32×32 red button. Mutes the master bus output.
- **Limiter Controls:**
  - Threshold: -1–0 dB (brickwall ceiling)
  - Ratio: 1–20 (limiter ratio)
  - Release: 10–1000 ms
  - Gain: 0–24 dB (makeup gain)
  - Bypass toggle

### Output Matrix Tab

The routing grid shows all sources (rows) against all destinations (columns):

**Sources (33 rows):**
- ASIO IN 1–16 (hardware inputs)
- 1kHz SINE / PINK NOISE (test generators)
- DCA 1–8
- BUS 1–8
- MASTER

**Destinations (10 columns):**
- OUT 1–8 (hardware outputs)
- REC L/R (recording bus)
- MASTER SUM

**Cell colors indicate tap point:**
| Color | Tap Point |
|-------|-----------|
| Cyan `#00BDD6` | Pre-Fader |
| Amber `#ffb300` | Post-Fader |
| Green `#00E676` | Post-Matrix |

Click any cell to toggle the route on/off. Right-click or use the route editor popup to adjust gain trim and tap point.

### Route Editor Popup

Appears when you click a route cell. 200×155 panel with:
- Source / Destination labels
- Gain trim slider: 0–2.0 (1.0 = unity)
- Tap point buttons: Pre-EQ, Pre-Fader, Post-Fader
- UNPATCH button (red) — removes the route
- CLOSE button

### System I/O Tab

| Control | Options | Description |
|---------|---------|-------------|
| Audio Device | Discovered WASAPI devices | Select capture/render device |
| Sample Rate | 44100, 48000, 88200, 96000 | Engine sample rate |
| Buffer Size | 128, 256, 512, 1024 | WASAPI buffer (lower = less latency) |
| Refresh | Button | Re-scans WASAPI devices |
| Scan Input | Button | Enumerates input devices |
| Scan Output | Button | Enumerates output devices |

Device cards show discovered devices with name and status.

---

## 4. Video Switcher

1920×1080 video production switcher with 4-camera support.

### Tab Bar

| Tab | Purpose |
|-----|---------|
| INPUTS / LAYERS | Camera inputs, source assignment |
| OUTPUT / MONITOR | Program/preview output, color correction |
| MEDIA DECK | Clip playback (load, play, scrub) |
| ADVANCED | DSK, upstream keyer, transition settings |

### Camera Strip

4 camera slots arranged horizontally (320×180 each):

| Border Color | Meaning |
|-------------|---------|
| Blue `#00a0f0` | Program (live) |
| Green `#00E676` | Preview (cued) |
| Gray `#252b36` | Inactive |

**Click** a camera to set it as Preview. **Ctrl+Click** to set it as Program (take).

**Drag and drop** between cameras to swap input sources. The source name appears below each camera.

A small "GPU" label appears when the source is connected to the D3D11 compositor.

### Control Bar

| Button | Color | Action |
|--------|-------|--------|
| CUT | Blue outline | Instant cut — swaps Program and Preview |
| AUTO | Blue filled | Automatic transition — animates over transition time |
| FTB | Red pulsing | Fade to Black toggle |

**Transition types** (5 buttons):
1. **Cut** — Instant switch
2. **Dissolve** — Crossfade
3. **Wipe L→R** — Horizontal wipe
4. **Push L→R** — Push transition
5. **Blur Dissolve** — Crossfade with blur

**T-bar:** Manual transition progress slider (0–100%). Drag to manually execute transitions.

### Preview Monitor

640×360 preview display showing:
- Current preview source
- Frame counter (top-right)
- GPU render status (top-left)
- Border color: green = preview, red = program

### Downstream Keyer (DSK)

Toggle switch at the bottom. When active:
- "DSK ACTIVE" label (green)
- Overlays the downstream keyer output on program

### Media Deck

Clip playback controls:
- **LOAD** (cyan) — Opens file dialog to load a clip
- **PLAY/PAUSE** (green) — Toggles playback
- **STOP** (amber) — Stops playback, resets to start
- **Scrub slider** — Drag to seek within the clip
- **Duration bar** — Shows position/total time

### Color Correction

3 sliders for per-source color adjustment:
- **Hue:** 0–360° (magenta accent)
- **Saturation:** 0–100% (amber accent)
- **Gain:** 0–200% (green accent)

### Output Selector

| Output | Assignment |
|--------|-----------|
| Output 1 (PGM) | Program output |
| Output 2 (AUX) | Auxiliary output |
| Output 3 (Multiview) | Multi-camera grid |
| Output 4 (Stream) | Streaming output |

Preview output modes: PGM + PVW Grid, Clean Feed, Downstream Keyed.

---

## 5. Show Builder

Diagnostics sandbox and cue management. Structurally similar to the Audio Console but focused on show state.

### Scene Snapshots

8 scene slots with per-scene controls:

| Button | Action |
|--------|--------|
| Save (cyan) | Saves current mixer state to this scene slot |
| Recall (green) | Restores mixer state from this scene slot |
| FadeTime (amber) | Sets transition time for recall (0–5000ms, default 500ms) |
| Merge | Merges scene state with current state |
| Replace | Overwrites scene with current state |

**Recall with fade:** When FadeTime > 0, parameters interpolate smoothly from current state to saved state over the specified duration.

### DCA Group Assignment

In the DCA bank, each channel strip shows 8 DCA assignment buttons. Click to toggle assignment. Active assignments shown in red.

### Cue List

3 cue slots (from default showfile):
1. **Intro** — 1000ms crossfade
2. **Main** — 500ms crossfade
3. **Outro** — 1000ms crossfade

Cues can be triggered via OSC (`/cue/trigger`) or the automation scheduler.

### Recording Tab (Show Builder)

Multitrack WAV recording controls:

| Button | Action |
|--------|--------|
| ARM REC | Arms recording (ready to record) |
| RECORD | Starts recording (red when active) |
| STOP | Stops recording |

Format selector: WAV 24-bit, WAV 16-bit, FLAC, Opus.

Per-channel stem routing toggles enable/disable individual channels in the recording.

---

## 6. Audio Engine

The C++ backend powering all audio. Not directly visible to users but affects behavior.

### Signal Flow

```
WASAPI Capture → Input Patch → Channel Strip → DCA → Routing Matrix → Output Patch → Master Limiter → WASAPI Render
                                    ↓
                              EQ (4-band)
                              Gate
                              Compressor
                              Saturator
                              Pan
                              Fader
```

### Key Parameters

| Parameter | Channels | Range | Default |
|-----------|----------|-------|---------|
| Volume | 24 input + 8 bus + 8 DCA + master | 0.0–1.0 | 1.0 (0.8 for master) |
| Mute | 24 input + 8 bus + 8 DCA + master | bool | false |
| Pan | 24 input | -100 to +100 | 0 (center) |
| Solo | 24 input | bool | false |

### Latency

- **WASAPI exclusive mode:** < 2ms round-trip (preferred)
- **WASAPI shared mode:** 5–15ms (fallback, used when exclusive fails)
- **Buffer sizes:** 128/256/512/1024 samples at 48kHz

### Real-Time Safety

All audio processing runs in the WASAPI callback thread with zero heap allocations:
- Lock-free SPSC ring buffers for all cross-thread communication
- Pre-allocated channel strips, routing nodes, and meter arrays
- `alignas(64)` cache-line alignment on all shared structs

---

## 7. Video Pipeline

### Architecture

```
Capture Sources → VideoSyncManager → GPUCompositor → Output
     ↓                                    ↓
  D3D11 Textures              HLSL Shader Passes
```

### Capture Sources

| Source | Protocol | Status |
|--------|----------|--------|
| Windows Graphics Capture | WinRT screen/window capture | Stub (needs C++/WinRT SDK) |
| FFmpeg Capture | RTSP/NDI/file decode | Real (FFmpeg avformat) |
| Camera PNG | Static placeholder images | Fallback |

### GPU Compositor Passes

7 HLSL shaders, compiled at runtime:

| Shader | Purpose |
|--------|---------|
| proc_amp | Brightness, contrast, saturation, gamma, hue |
| chroma_key | Green/blue screen key with spill suppression |
| transition | Cut, dissolve, wipe, push, blur dissolve |
| dsk | Downstream keyer overlay |
| upstream_keyer | Picture-in-picture |
| fill_key_blend | Fill/key compositing |
| quad | Fullscreen quad rendering |

### Genlock

Software genlock via `VideoSyncManager`:
- 4 input channels, 3-frame ring buffer per channel
- PTS-based closest-frame acquisition
- Frame-accurate switching on transition commands

---

## 8. Control Surface

### OSC (Open Sound Control)

UDP port 8000 (input) / 9000 (output).

| Address | Direction | Description |
|---------|-----------|-------------|
| `/ch/{N}/volume` | In | Set channel N volume (0.0–1.0) |
| `/ch/{N}/mute` | In | Set channel N mute (0/1) |
| `/ch/{N}/pan` | In | Set channel N pan (-100–+100) |
| `/dca/{N}/volume` | In | Set DCA N volume |
| `/master/volume` | In | Set master volume |
| `/master/mute` | In | Set master mute |
| `/video/cut` | In | Execute cut transition |
| `/video/auto` | In | Execute auto transition |
| `/video/ftb` | In | Toggle fade to black |
| `/cue/trigger` | In | Trigger cue by index |
| `/video/program` | In | Set program camera index |
| `/video/preview` | In | Set preview camera index |

### MIDI

WinMM MIDI input support:
- **CC 0–7:** Channel 1–8 volume
- **CC 16–23:** Channel 1–8 mute
- **CC 80–87:** DCA 1–8 volume
- **CC 90:** Master volume
- **Note On 0–7:** Channel 1–8 mute toggle
- **Note On 127:** Panic (FTB)

MIDI Learn mode: Enable in Audio Console → MIDI section. Move a controller, then select a parameter to map.

### Stream Deck (WebSocket)

WebSocket server on `localhost:8100`. Accepts Stream Deck JSON commands:

```json
{"action": "keyDown", "key": 0, "state": 1}
{"action": "keyUp", "key": 0, "state": 0}
```

Keys 0–7 toggle channel mutes. Key 127 triggers panic.

---

## 9. Showfile Format

`.sds` (Software-Defined Show) files are ZIP archives containing:

| File | Format | Contents |
|------|--------|----------|
| `manifest.json` | JSON (simdjson) | Show metadata, channel names, cue list, transitions |
| `show.db` | SQLite (WAL mode) | Full mixer state: channels, buses, DCAs, routing, global |

### Default Schema

```json
{
  "version": "1.0",
  "name": "Default Show",
  "channels": 8,
  "buses": 2,
  "dcas": 8,
  "sampleRate": 48000,
  "videoResolution": "1920x1080",
  "videoFps": 60,
  "cues": [
    {"index": 0, "label": "Intro", "transition": {"type": "CROSSFADE", "duration_ms": 1000}},
    {"index": 1, "label": "Main", "transition": {"type": "CROSSFADE", "duration_ms": 500}},
    {"index": 2, "label": "Outro", "transition": {"type": "CROSSFADE", "duration_ms": 1000}}
  ]
}
```

### Database Tables

| Table | Columns |
|-------|---------|
| Channels | id, name, volume, mute, solo, pan, dca_group, bus_assignments |
| Buses | id, name, volume, mute |
| DCAs | id, name, volume, mute |
| Cues | id, name, index, transition_type, transition_duration_ms |
| Routing | source_type, source_index, dest_type, dest_index, gain, tap_point |
| GlobalState | key, value (masterVolume, masterMute, programCamera, previewCamera) |

---

## 10. System I/O Configuration

### Audio Device Selection

1. Open Audio Console → SYSTEM I/O tab
2. Click **Scan Input** / **Scan Output** to discover WASAPI devices
3. Select device from the dropdown
4. Set sample rate and buffer size
5. Click **Refresh** if devices changed

### Recommended Settings

| Use Case | Sample Rate | Buffer Size | Latency |
|----------|------------|-------------|---------|
| Podcasting | 48000 | 256 | ~5ms |
| Live production | 48000 | 128 | ~3ms |
| High-quality recording | 96000 | 512 | ~5ms |

### WASAPI Mode

- **Exclusive mode** (preferred): Lowest latency, direct hardware access. Fails if another app is using the device.
- **Shared mode** (fallback): Higher latency, shares device with other apps. Used automatically when exclusive fails.

---

## 11. Recording

### Multitrack WAV Recording

1. Open Show Builder → RECORDING tab
2. Click **ARM REC** to arm recording
3. Select format (WAV 24-bit recommended)
4. Toggle per-channel stem routing
5. Click **RECORD** to start
6. Click **STOP** to end

Recording creates 8 mono WAV files (24-bit PCM, 48kHz):
```
recording_2026-07-15_143022/
  ch01_Mic1.wav
  ch02_Mic2.wav
  ...
  ch08_Mic8.wav
```

### Monitor Section

- **Monitor Mix knob:** Adjusts monitoring level
- **Monitor Mute:** Mutes monitor output
- **Level bar:** Green, shows current monitor level

---

## 12. Keyboard / Mouse Reference

### Audio Console

| Action | Input |
|--------|-------|
| Adjust fader | Vertical drag on slider |
| Adjust pan | Horizontal drag on pan knob |
| Adjust EQ/dynamics knobs | Vertical drag on knob |
| Toggle solo | Click S button |
| Toggle mute | Click M button |
| Open DSP panel | Click channel label |
| Adjust route gain | Drag slider in route popup |
| Change tap point | Click Pre-EQ / Pre-Fader / Post-Fader |

### Video Switcher

| Action | Input |
|--------|-------|
| Set preview | Click camera |
| Take (set program) | Ctrl+Click camera |
| Cut | Click CUT button |
| Auto transition | Click AUTO button |
| Manual transition | Drag T-bar |
| Swap sources | Drag camera onto another |
| Load clip | Click LOAD in Media Deck |
| Play/Pause clip | Click PLAY/PAUSE |
| Scrub clip | Drag scrub slider |

### Master Launcher

| Action | Input |
|--------|-------|
| Toggle window | Click module toggle |
| Toggle FTB | Click EMERGENCY PANIC button |

---

## 13. Troubleshooting

### Window doesn't appear

The app needs the Qt bin directory on PATH. If windows don't show:
1. Ensure `libs/Qt/6.6.2/msvc2019_64/bin` is on your system PATH, OR
2. Run from the repo root directory

### WASAPI exclusive mode fails

This is normal if another audio app is using the device. The engine falls back to shared mode automatically. To use exclusive mode, close all other audio applications (browsers, Discord, etc.) before launching.

### No audio input

1. Open Audio Console → SYSTEM I/O
2. Click **Scan Input** to discover devices
3. Select your microphone/input device
4. Check that the channel isn't muted (M button)

### Video shows black

The D3D11 compositor requires a GPU with shader model 5.0+ support. If the compositor fails:
- Check that `D3Dcompiler_47.dll` is in the exe directory
- Ensure GPU drivers are up to date
- The app will fall back to camera placeholder images

### Showfile won't load

`.sds` files must be valid ZIP archives containing `manifest.json` and `show.db`. If loading fails:
1. Check the realtime log (`overwatch_studio_realtime.log`)
2. Try re-creating the default showfile (delete `assets/shows/default.sds` and relaunch)

### Log file location

`overwatch_studio_realtime.log` is created in the working directory on every launch. Contains all Qt messages, WASAPI status, engine state, and errors.

### OSC not receiving

1. Check that no other app is using UDP port 8000
2. Verify the OSC client is sending to `localhost:8000` (not the broadcast address)
3. Check firewall settings

### MIDI not receiving

1. Open Audio Console → MIDI section
2. Verify MIDI device appears in the device list
3. Click the device to select it
4. Check that no other app has exclusive MIDI access
