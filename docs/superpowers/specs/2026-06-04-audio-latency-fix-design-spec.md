# 2026-06-04 Audio Latency Fix Design Spec

This specification details the implementation plan to eliminate the ~1 second latency in the WASAPI audio capture and render loops of Overwatch Studio.

## Problem Statement
The WASAPI multi-device capture and render system currently has an unacceptable delay of nearly one second. This latency stems from two main sources:
1. **Ring Buffer Sample Accumulation:** When the capture worker starts, it fills the ring buffer immediately. Since the simulated audio thread consumes samples sequentially from the oldest index (`m_ringReadPos`), the buffer remains permanently full, introducing a static delay of at least $16,384 \text{ samples} \div 48,000 \text{ Hz} \approx 341\text{ms}$ per worker (capture and render combined is ~682ms).
2. **Inaccurate Timer Sleep on Windows:** The simulated audio thread sleeps for 5ms inside its loop. Without high-resolution timer adjustments on Windows, this sleep defaults to 15.6ms, causing the thread to run at roughly 34% of real-time speed. This mismatch causes capture buffers to overflow and render buffers to underflow, leading to stuttering and accumulated lag.

## Proposed Changes

### 1. Low-Latency Ring Buffer Catch-Up
Modify [WASAPIDeviceWorker.cpp](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WASAPIDeviceWorker.cpp) to discard stale samples when the ring buffer fill level exceeds a low-latency threshold:
* **Capture Mode:** In `WASAPIDeviceWorker::readCapturedSamples`, calculate the backlog. If the backlog is greater than 512 samples (~10.6ms), advance `m_ringReadPos` to keep exactly the most recent 512 samples.
* **Render Mode:** In the render background thread (`runLoop`), check the backlog before calling WASAPI's `GetBuffer`. If the backlog is greater than `framesToWrite + 512`, advance `m_ringReadPos` to discard older samples and keep exactly the most recent `framesToWrite + 256` samples.
* **Add Backlog Getter:** Add `size_t getBufferedSampleCount() const noexcept` to `WASAPIDeviceWorker` to expose the current buffer fill level.

### 2. High-Precision Audio Pacing Loop
In [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp), replace the blind `sleep_for(5)` inside `m_simulatedAudioThread` with an adaptive, hardware-aligned pacing system:
* **Hardware-Paced Mode (When Capture Devices Are Active):** Check the buffered sample count of the first capture worker. If it is less than 256 samples, sleep for 1ms and yield. If it has at least 256 samples, immediately process a 256-sample block. This locks the processing thread directly to the capture device's hardware clock.
* **Timer-Paced Mode (When No Capture Devices Are Active):** Use a high-precision `steady_clock` loop that sleeps/yields for exactly `5333` microseconds (256 samples @ 48kHz).
* **Enable High-Resolution Windows Scheduler:** Call `timeBeginPeriod(1)` and `timeEndPeriod(1)` inside the simulated thread to set the Windows system scheduler resolution to 1ms.

## Verification Plan

### Automated Tests
* Build the test suite: `cmake --build build --config Release`
* Run: `.\build\bin\Release\AudioEngineTests.exe` to verify all DSP unit tests pass.

### Manual Verification
* Run the app: `.\build\bin\Release\overwatch_studio.exe`
* Verify the mapped hardware input meters respond to your voice immediately.
* Verify there is no noticeable latency or stuttering in playback.
