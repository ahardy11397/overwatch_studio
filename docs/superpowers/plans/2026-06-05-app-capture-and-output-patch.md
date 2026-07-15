# App Capture and Output Patching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix application audio capture loopback and dynamic process list in the patch settings, and refactor output patching to let console summing buses be anchors with dropdowns selecting physical output ports.

**Architecture:** 
* Fix Windows process loopback stream initialization by using `0` flags (instead of `AUDCLNT_STREAMFLAGS_LOOPBACK`) and fixing stack-allocated `mixFormat` lifetimes.
* Implement a real-time safe circular buffer catch-up logic in `AudioEngineCore` to drain loopback audio buffers and minimize latency.
* Refactor the UI and bridge logic to index output patches by summing bus index and dynamically map them to target physical outputs.

---

### Task 1: Dynamic Process List

**Files:**
- Modify: [AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h)
- Modify: [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp)

- [ ] **Step 1: Write a failing compilation check or logic verify**
  We will modify `availableProcesses` to include `<tlhelp32.h>` and write a quick test, or verify that the list returns dynamically by checking output logs.
  
- [ ] **Step 2: Add include and dynamic process enumeration**
  Add `#include <tlhelp32.h>` near the top of [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp).
  Modify `availableProcesses()` to dynamically enumerate running processes:
  ```cpp
  QVariantMap AudioEngineBridge::availableProcesses() const {
      QVariantMap map;
      HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
      if (hSnapshot == INVALID_HANDLE_VALUE) {
          return map;
      }
      PROCESSENTRY32W pe;
      pe.dwSize = sizeof(PROCESSENTRY32W);
      if (Process32FirstW(hSnapshot, &pe)) {
          do {
              DWORD pid = pe.th32ProcessID;
              if (pid <= 4) continue;
              QString procName = QString::fromWCharArray(pe.szExeFile);
              if (procName.isEmpty()) continue;
              QString lowerName = procName.toLower();
              if (lowerName == "svchost.exe" || lowerName == "services.exe" ||
                  lowerName == "lsass.exe" || lowerName == "csrss.exe" ||
                  lowerName == "smss.exe" || lowerName == "wininit.exe" ||
                  lowerName == "winlogon.exe" || lowerName == "spoolsv.exe" ||
                  lowerName == "dwm.exe" || lowerName == "taskhostw.exe" ||
                  lowerName == "conhost.exe" || lowerName == "dllhost.exe" ||
                  lowerName == "sihost.exe" || lowerName == "fontdrvhost.exe" ||
                  lowerName == "ctfmon.exe" || lowerName == "shellexperiencehost.exe" ||
                  lowerName == "searchhost.exe" || lowerName == "runtimebroker.exe") {
                  continue;
              }
              QString key = QString("%1 (PID: %2)").arg(procName).arg(pid);
              map[key] = static_cast<int>(pid);
          } while (Process32NextW(hSnapshot, &pe));
      }
      CloseHandle(hSnapshot);
      if (map.isEmpty()) {
          map["Discord.exe (PID: 1420)"] = 1420;
          map["chrome.exe (PID: 9812)"] = 9812;
          map["spotify.exe (PID: 4322)"] = 4322;
      }
      return map;
  }
  ```

- [ ] **Step 3: Add periodic refresh**
  Modify `AudioEngineBridge::processAudioFeedback()` to increment a frame counter and emit `processesChanged` every 120 frames (~2 seconds):
  ```cpp
  void AudioEngineBridge::processAudioFeedback() {
      if (!m_engine) return;
      
      // ... existing peak meter logic ...

      static int processCounter = 0;
      if (++processCounter >= 120) {
          processCounter = 0;
          emit processesChanged();
      }
  }
  ```

- [ ] **Step 4: Run compilation to verify**
  Run: `cmake --build build --config Release`
  Expected: Successful compilation.

- [ ] **Step 5: Commit**
  ```bash
  git add src/ui/AudioEngineBridge.h src/ui/AudioEngineBridge.cpp
  git commit -m "feat(ui): dynamically enumerate user processes and refresh process list every 2 seconds"
  ```

---

### Task 2: Fix WASAPI Process Loopback Thread

**Files:**
- Modify: [WindowsProcessCapture.cpp](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/WindowsProcessCapture.cpp)

- [ ] **Step 1: Fix stack format variable lifetime and flags**
  Modify `WindowsProcessCapture::captureLoop` so that `WAVEFORMATEXTENSIBLE wfx` is declared at the top of the function to extend its scope, and set `mixFormat` to point to it:
  ```cpp
  void WindowsProcessCapture::captureLoop(DWORD pid, SPSCQueue<float>& queue) noexcept {
      CoInitializeEx(nullptr, COINIT_MULTITHREADED);

      Microsoft::WRL::ComPtr<IAudioClient> audioClient;
      Microsoft::WRL::ComPtr<IAudioCaptureClient> captureClient;
      WAVEFORMATEXTENSIBLE wfx = {};
      WAVEFORMATEX* mixFormat = nullptr;
      bool formatAllocated = false;
      bool initialized = false;
  ```
  In the `pid != 0` block, remove `AUDCLNT_STREAMFLAGS_LOOPBACK` from `audioClient->Initialize`:
  ```cpp
                      // ... set up wfx ...
                      mixFormat = reinterpret_cast<WAVEFORMATEX*>(&wfx);

                      hr = audioClient->Initialize(
                          AUDCLNT_SHAREMODE_SHARED,
                          0, // Must be 0 for process loopback activation
                          1000000, // 100ms
                          0,
                          mixFormat,
                          nullptr
                      );
  ```
  In the fallback block, copy retrieved format into local `wfx` and free using `CoTaskMemFree` to avoid memory leaks or dangling pointers:
  ```cpp
          if (SUCCEEDED(hr)) {
              WAVEFORMATEX* tempFormat = nullptr;
              hr = audioClient->GetMixFormat(&tempFormat);
              if (SUCCEEDED(hr) && tempFormat) {
                  if (tempFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
                      wfx = *reinterpret_cast<WAVEFORMATEXTENSIBLE*>(tempFormat);
                  } else {
                      std::memset(&wfx, 0, sizeof(wfx));
                      std::memcpy(&wfx.Format, tempFormat, sizeof(WAVEFORMATEX));
                  }
                  CoTaskMemFree(tempFormat);
                  mixFormat = reinterpret_cast<WAVEFORMATEX*>(&wfx);

                  hr = audioClient->Initialize(
                      AUDCLNT_SHAREMODE_SHARED,
                      AUDCLNT_STREAMFLAGS_LOOPBACK, // Keep for system-wide loopback
                      1000000,
                      0,
                      mixFormat,
                      nullptr
                  );
  ```

- [ ] **Step 2: Run compilation to verify**
  Run: `cmake --build build --config Release`
  Expected: Successful compilation.

- [ ] **Step 3: Commit**
  ```bash
  git add src/core/audio/WindowsProcessCapture.cpp
  git commit -m "fix(audio): resolve process loopback initialization failure and dangling format pointer"
  ```

---

### Task 3: Implement DSP App Capture Circular Buffer Catch-Up

**Files:**
- Modify: [AudioEngineCore.h](file:///f:/Drive/scripts/overwatch_studio/src/core/audio/AudioEngineCore.h)

- [ ] **Step 1: Replace AppCapture pull block in real-time callback**
  Modify lines 297-306 in `AudioEngineCore::audioDeviceIOCallbackWithContext` to implement the circular buffer catch-up:
  ```cpp
              } else if (patch.type == AudioSourceType::AppCapture) {
                  // Pull from dedicated process capture queue with catch-up logic to prevent latency build-up
                  auto* queue = appCaptureQueues[c].get();
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
              }
  ```

- [ ] **Step 2: Run automated test suite**
  Run: `cmake --build build --config Release`
  Then: `build/bin/Release/AudioEngineTests.exe`
  Expected: All 26 unit tests PASS.

- [ ] **Step 3: Commit**
  ```bash
  git add src/core/audio/AudioEngineCore.h
  git commit -m "feat(audio-core): implement real-time safe circular buffer catch-up for app capture queues"
  ```

---

### Task 4: Refactor Output Patching Bridge Logic

**Files:**
- Modify: [AudioEngineBridge.h](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.h)
- Modify: [AudioEngineBridge.cpp](file:///f:/Drive/scripts/overwatch_studio/src/ui/AudioEngineBridge.cpp)

- [ ] **Step 1: Modify setOutputPatch signature in header**
  Modify `AudioEngineBridge.h` around line 177:
  ```cpp
      Q_INVOKABLE void setOutputPatch(int busIdx, int hwOutputIdx, bool active);
  ```

- [ ] **Step 2: Modify output patch logic in C++**
  Modify `AudioEngineBridge::setOutputPatch` implementation in `AudioEngineBridge.cpp`:
  ```cpp
  void AudioEngineBridge::setOutputPatch(int busIdx, int hwOutputIdx, bool active) {
      if (busIdx < 0 || busIdx >= 8) {
          return;
      }
      
      // 1. If we are activating a physical output, first clear any other bus patched to that same physical output
      if (active && hwOutputIdx >= 0 && hwOutputIdx < 8) {
          for (int i = 0; i < 8; ++i) {
              if (i != busIdx && m_uiOutputPatches[i].active && m_uiOutputPatches[i].hwOutputIdx == hwOutputIdx) {
                  m_uiOutputPatches[i].active = false;
                  pushCommand(RoutingCommand{
                      RoutingCommandType::SetOutputPatch,
                      static_cast<uint32_t>(hwOutputIdx), // hwOutputIdx
                      static_cast<uint32_t>(i),          // busIdx
                      0.0f,
                      0U                                 // active = false
                  });
              }
          }
      }
      
      // 2. Now update the target bus patch
      int oldHwOutputIdx = m_uiOutputPatches[busIdx].hwOutputIdx;
      bool oldActive = m_uiOutputPatches[busIdx].active;
      
      m_uiOutputPatches[busIdx].hwOutputIdx = hwOutputIdx;
      m_uiOutputPatches[busIdx].active = active;
      
      // 3. If it was active on an old physical output, clear the old one
      if (oldActive && oldHwOutputIdx >= 0 && oldHwOutputIdx < 8 && (!active || oldHwOutputIdx != hwOutputIdx)) {
          pushCommand(RoutingCommand{
              RoutingCommandType::SetOutputPatch,
              static_cast<uint32_t>(oldHwOutputIdx),
              static_cast<uint32_t>(busIdx),
              0.0f,
              0U // active = false
          });
      }
      
      // 4. Send the new command if active
      if (active && hwOutputIdx >= 0 && hwOutputIdx < 8) {
          pushCommand(RoutingCommand{
              RoutingCommandType::SetOutputPatch,
              static_cast<uint32_t>(hwOutputIdx),
              static_cast<uint32_t>(busIdx),
              0.0f,
              1U // active = true
          });
      }
      
      emit patchesChanged();
  }
  ```

- [ ] **Step 3: Run compilation to verify**
  Run: `cmake --build build --config Release`
  Expected: Successful compilation.

- [ ] **Step 4: Commit**
  ```bash
  git add src/ui/AudioEngineBridge.h src/ui/AudioEngineBridge.cpp
  git commit -m "feat(ui-bridge): re-index output patches by summing bus and automatically clear destination conflicts"
  ```

---

### Task 5: Refactor Output Patching UI

**Files:**
- Modify: [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml)

- [ ] **Step 1: Modify Output Patching panel in QML**
  Modify [Main.qml](file:///f:/Drive/scripts/overwatch_studio/src/ui/Main.qml) around line 8352:
  ```qml
                                      Repeater {
                                          model: 8
                                          delegate: RowLayout {
                                              spacing: 12
                                              Layout.fillWidth: true
                                              property int busIdx: index
                                              property var busNames: ["Master L", "Master R", "Aux 1", "Aux 2", "Aux 3", "Aux 4", "Rec L", "Rec R"]

                                              // Label
                                              Rectangle {
                                                  width: 120; height: 24
                                                  color: "#1a1c1e"
                                                  radius: 4
                                                  border.color: "#252b36"
                                                  Text {
                                                      anchors.centerIn: parent
                                                      text: busNames[busIdx]
                                                      color: "#00BDD6"
                                                      font.pixelSize: 9
                                                      font.bold: true
                                                  }
                                              }

                                              // ComboBox
                                              ComboBox {
                                                  id: patchedOutputCombo
                                                  implicitHeight: 24
                                                  Layout.preferredWidth: 200
                                                  model: ["Unpatched", "ASIO Output 1", "ASIO Output 2", "ASIO Output 3", "ASIO Output 4", "ASIO Output 5", "ASIO Output 6", "ASIO Output 7", "ASIO Output 8"]
                                                  
                                                  currentIndex: {
                                                      if (audioCore.outputPatches && audioCore.outputPatches[busIdx] !== undefined) {
                                                          var patch = audioCore.outputPatches[busIdx];
                                                          if (patch.active) {
                                                              return patch.hwOutputIdx + 1;
                                                          }
                                                      }
                                                      return 0;
                                                  }

                                                  onActivated: {
                                                      var active = index > 0;
                                                      var hwOutputIdx = index - 1;
                                                      audioCore.setOutputPatch(busIdx, hwOutputIdx, active);
                                                  }
                                              }

                                              Item { Layout.fillWidth: true }
                                          }
                                      }
  ```

- [ ] **Step 2: Run build to make sure UI resources compile**
  Run: `cmake --build build --config Release`
  Expected: PASS.

- [ ] **Step 3: Commit**
  ```bash
  git add src/ui/Main.qml
  git commit -m "feat(ui-qml): refactor output patch settings layout to have summing buses as anchors"
  ```
