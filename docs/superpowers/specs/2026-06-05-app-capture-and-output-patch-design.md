# Design Specification: App Capture Fix and Output Patching Refactoring

Date: 2026-06-05  
Status: Approved  

## Goal
1. Fix the application audio capture functionality: resolve the WASAPI process loopback initialization failure (incorrect flags) and the dangling pointer bug in `WindowsProcessCapture.cpp`, and dynamically enumerate running user processes instead of returning placeholders.
2. Refactor the output patching system so that the 8 summing buses are the "anchors" (rows) and the target physical output ports are selected via dropdown, matching the input patch layout.

---

## Proposed Changes

### 1. WASAPI App Capture & Circular Buffer Catch-Up

#### [MODIFY] [WindowsProcessCapture.cpp](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WindowsProcessCapture.cpp)
* Declare `WAVEFORMATEXTENSIBLE wfx` at the top of `captureLoop` to extend its lifetime to the entire function execution.
* Point `mixFormat = reinterpret_cast<WAVEFORMATEX*>(&wfx)` to this local structure.
* For process-specific loopback, call `audioClient->Initialize` with `0` for stream flags instead of `AUDCLNT_STREAMFLAGS_LOOPBACK`.
* For system-wide loopback, fetch the mix format into `wfx` and release the system pointer using `CoTaskMemFree`.

#### [MODIFY] [AudioEngineCore.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioEngineCore.h)
* In `AudioEngineCore::audioDeviceIOCallbackWithContext`, pull samples from `appCaptureQueues[c]` using a circular buffer to catch up and discard backlog:
  ```cpp
  size_t writeIdx = 0;
  size_t poppedCount = 0;
  while (auto sampleOpt = queue->pop()) {
      dest[writeIdx] = *sampleOpt;
      writeIdx = (writeIdx + 1) % samples;
      poppedCount++;
  }
  if (poppedCount >= samples) {
      std::rotate(dest, dest + writeIdx, dest + samples);
  } else {
      std::fill(dest + writeIdx, dest + samples, 0.0f);
  }
  ```

---

### 2. Dynamic Process List & Periodic Refresh

#### [MODIFY] [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp)
* Include `<tlhelp32.h>` in `AudioEngineBridge.cpp`.
* Implement dynamic process enumeration in `availableProcesses()` using `CreateToolhelp32Snapshot` and the `Process32FirstW`/`Process32NextW` APIs.
* Filter out system processes (e.g. `svchost.exe`, `lsass.exe`, PIDs <= 4, etc.).
* Return a `QVariantMap` mapping `"ProcessName.exe (PID: 1234)" -> 1234`.
* Inside `AudioEngineBridge::processAudioFeedback()`, increment a frame counter and emit `processesChanged()` once every 120 frames (~2 seconds) to refresh the process list dynamically in the UI.

---

### 3. Output Patching UI/UX Refactoring

#### [MODIFY] [AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h)
* Update `setOutputPatch` signature:
  ```cpp
  Q_INVOKABLE void setOutputPatch(int busIdx, int hwOutputIdx, bool active);
  ```

#### [MODIFY] [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp)
* Re-index `m_uiOutputPatches` so it is indexed by `busIdx` (0 to 7) instead of `hwOutputIdx`.
* Implement `setOutputPatch` to support this inverted layout and automatically resolve physical output mapping conflicts:
  * If a new patch is activated for `hwOutputIdx`, clear any other bus that was patched to it.
  * If the target physical output for the current bus has changed, unpatch the old physical output.
  * Update the current bus patch's `hwOutputIdx` and `active` status.
  * Push the corresponding `SetOutputPatch` command to the DSP engine.

#### [MODIFY] [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml)
* Refactor the Output Patch panel layout so that:
  * Rows = 8 summing buses (Master L/R, Aux 1-4, Rec L/R).
  * ComboBox selects the target physical output from:
    `["Unpatched", "ASIO Output 1", "ASIO Output 2", ..., "ASIO Output 8"]`.
  * ComboBox `currentIndex` is bound to `patch.hwOutputIdx + 1` if active, else 0.
  * ComboBox `onActivated` calls `audioCore.setOutputPatch(busIdx, index - 1, index > 0)`.

---

## Verification Plan

### Automated Tests
* Run the existing test suite:
  `build/bin/Release/AudioEngineTests.exe`
* Add or adapt a unit test in `tests/DynamicAudioEngineTests.cpp` verifying that:
  - Process-specific app capture queues are successfully instantiated.
  - DSP routing command processes `SetOutputPatch` correctly.

### Manual Verification
* Run the application: `build/bin/Release/overwatch_studio.exe`.
* Verify that the App Capture process dropdown dynamically shows running processes (with PIDs) on the system.
* Verify that setting App Capture streams audio correctly.
* Verify that Output Patching rows display Master L/R, Aux 1-4, Rec L/R, and their dropdowns allow selecting physical ASIO output ports.
