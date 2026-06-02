# 2026-06-02 Audio Console Metering and Control Design

This specification establishes a thread-safe, low-latency control and feedback loop between the Qt/QML UI thread and the real-time DSP thread for Overwatch Studio's Software-Defined Sound Console (SDSC).

## Problem Statement
Currently, the audio mixing console's faders and mute buttons only update local QML properties and mock logs, without propagating parameters to the real-time DSP channel strips (`AudioChannelStrip`). Additionally, visual level meters simulate signal levels with a static sine wave based on a single bridge property (`audioCore.peakMeter`). As a result, no real audio is passed or attenuated, and visual feedback is completely simulated.

## Proposed Changes

### 1. Control Command Serializing (C++ Core & Bridge)
* We add `SetChannelVolume` and `SetChannelMute` commands to `RoutingCommandType` in `RoutingPatchMap.h`.
* When a fader value is adjusted or a mute is toggled in QML:
  - Input faders map to input channel indexes (`0..23`, type `0`).
  - Summing bus faders map to summing bus channel indexes (`64..71`, type `1`).
  - Aux faders map to aux channel indexes (`80..87`, type `2`).
  - Master faders map to the master output (`24`, type `3`).
* These changes are pushed as serializable `RoutingCommand` structs to the lock-free Single Producer Single Consumer (SPSC) queue `uiToDspQueue`.

### 2. Real-Time Safety & DSP Adjustments (AudioEngineCore)
* In the real-time callback loop of `AudioEngineCore`:
  - Process `SetChannelVolume` and `SetChannelMute` from the queue.
  - Set the corresponding channel strip fader and mute properties in `channelPool` (under inputs, buses, or auxes).
  - Apply mute attenuation (silence samples early) and fader smoothing in the channel strips.
  - Sum inputs into `busBuffers`.
  - Process summing bus channel strips (`channelPool[MaxInputs + b]`) on the bus buffers to apply summing EQ, compression, volume, and mute states.
  - Apply Master Volume and Master Mute to the final output buffers in Stage 4/5.

### 3. Real-Time Peak Meter Tracking (DSP to UI)
* In the real-time callback loop, compute block peak levels:
  - Input channel peaks: max absolute amplitude in Stage 2.
  - Summing bus peaks: max absolute amplitude in Stage 3 post-processing.
  - Master output peak: max absolute amplitude across all hardware outputs.
* Store these peak values in atomic floats inside `AudioEngineCore` using relaxed memory order stores.
* In the UI thread timer (`AudioEngineBridge::processAudioFeedback`), read these atomic values and apply an exponential decay envelope follower to provide a natural visual release time on the meters.
* Expose these levels as list properties to QML: `channelPeaks`, `busPeaks`, `masterPeak`.

### 4. QML Meter Visual Binding (Main.qml)
* Wire channel fader meters to `audioCore.channelPeaks[resolvedIdx]`, `audioCore.busPeaks[resolvedIdx]`, and DCA faders to the max peak of their assigned input channels.
* Wire the Master fader meter to `audioCore.masterPeak`.
* Initialize all 24 channels to route to the Master bus (Bus 0 & 1) by default on startup.

## Verification Plan

### GTests
- Verify that sending `SetChannelVolume` and `SetChannelMute` commands correctly updates channel strip targets and silences buffers.
- Verify that input/bus peak calculation correctly identifies the maximum absolute sample in a block.

### Manual Verification
- Compile and run the application.
- Patch a Sine generator to channel 0.
- Verify channel 0 and Master meters light up immediately (due to default routing).
- Drag channel 0 fader or Master fader down and verify meters smoothly descend.
- Toggle mute and verify the meter drops to zero.
